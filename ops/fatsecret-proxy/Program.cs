using System.Buffers;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

// A password-protected HTTPS tunnel (HTTP CONNECT) that only reaches FatSecret. The Vercel backend
// routes FatSecret calls through it so they leave from this server's static IP.
var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options => options.ServiceName = "CaveCalsFatSecretProxy");
builder.Services.Configure<ProxyOptions>(builder.Configuration.GetSection("Proxy"));
builder.Services.AddHostedService<ConnectProxy>();
builder.Build().Run();

public sealed class ProxyOptions
{
    public int Port { get; set; } = 31280;
    public string Username { get; set; } = "";
    /// <summary>Lowercase hex SHA-256 of the password. The password itself is never stored here.</summary>
    public string PasswordSha256 { get; set; } = "";
    public string[] AllowedHosts { get; set; } = [];
    public int MaxConnections { get; set; } = 64;
}

public sealed class ConnectProxy(IOptions<ProxyOptions> options, ILogger<ConnectProxy> logger) : BackgroundService
{
    const int MaxHeaderBytes = 8192;
    static readonly TimeSpan HeaderTimeout = TimeSpan.FromSeconds(10);
    static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(10);
    static readonly TimeSpan IdleTimeout = TimeSpan.FromSeconds(60);
    static readonly byte[] HeaderEnd = "\r\n\r\n"u8.ToArray();

    readonly ProxyOptions settings = options.Value;
    byte[] usernameBytes = [];
    byte[] passwordHash = [];
    HashSet<string> allowedHosts = [];
    SemaphoreSlim slots = new(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (string.IsNullOrWhiteSpace(settings.Username) || settings.PasswordSha256.Length != 64 || settings.AllowedHosts.Length == 0)
            throw new InvalidOperationException("Proxy:Username, Proxy:PasswordSha256 (64 hex characters) and Proxy:AllowedHosts are required.");
        usernameBytes = Encoding.UTF8.GetBytes(settings.Username);
        passwordHash = Convert.FromHexString(settings.PasswordSha256);
        allowedHosts = new HashSet<string>(settings.AllowedHosts.Select(h => h.Trim().ToLowerInvariant()));
        slots = new SemaphoreSlim(settings.MaxConnections);

        var listener = new TcpListener(IPAddress.IPv6Any, settings.Port);
        listener.Server.DualMode = true;
        listener.Start();
        logger.LogWarning("FatSecret proxy listening on port {Port} for {Hosts}", settings.Port, string.Join(", ", allowedHosts));
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(stoppingToken);
                // Shed load instead of queueing when every slot is busy.
                if (!slots.Wait(0)) { client.Dispose(); continue; }
                _ = Task.Run(async () =>
                {
                    try { await HandleAsync(client, stoppingToken); }
                    catch (Exception error) when (error is IOException or SocketException or OperationCanceledException) { }
                    catch (Exception error) { logger.LogWarning(error, "Proxy connection failed"); }
                    finally { client.Dispose(); slots.Release(); }
                }, CancellationToken.None);
            }
        }
        catch (OperationCanceledException) { }
        finally { listener.Stop(); }
    }

    async Task HandleAsync(TcpClient client, CancellationToken stoppingToken)
    {
        client.NoDelay = true;
        var downstream = client.GetStream();
        using var headerDeadline = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        headerDeadline.CancelAfter(HeaderTimeout);
        var (header, leftover) = await ReadHeaderAsync(downstream, headerDeadline.Token);
        if (header is null) return;

        var lines = header.Split("\r\n");
        var request = lines[0].Split(' ');
        // Only HTTPS tunnels to an allowed host on 443; refuse before asking for credentials.
        if (request.Length != 3 || request[0] != "CONNECT" || !TryParseTarget(request[1], out var host, out var port)
            || port != 443 || !allowedHosts.Contains(host))
        {
            logger.LogDebug("Refused {Request}", lines[0]);
            await RespondAsync(downstream, "403 Forbidden", stoppingToken);
            return;
        }
        var authorization = lines.Skip(1)
            .FirstOrDefault(line => line.StartsWith("Proxy-Authorization:", StringComparison.OrdinalIgnoreCase))?
            ["Proxy-Authorization:".Length..].Trim();
        if (!IsAuthorized(authorization))
        {
            logger.LogDebug("Authentication required for {Host}", host);
            await RespondAsync(downstream, "407 Proxy Authentication Required", stoppingToken,
                "Proxy-Authenticate: Basic realm=\"Cave Cals proxy\"\r\n");
            return;
        }

        using var upstreamClient = new TcpClient();
        using (var connectDeadline = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken))
        {
            connectDeadline.CancelAfter(ConnectTimeout);
            try { await upstreamClient.ConnectAsync(host, port, connectDeadline.Token); }
            catch (Exception error) when (error is SocketException or OperationCanceledException)
            {
                logger.LogWarning("Could not reach {Host}: {Message}", host, error.Message);
                await RespondAsync(downstream, "502 Bad Gateway", stoppingToken);
                return;
            }
        }
        upstreamClient.NoDelay = true;
        var upstream = upstreamClient.GetStream();
        await downstream.WriteAsync("HTTP/1.1 200 Connection established\r\n\r\n"u8.ToArray(), stoppingToken);
        if (leftover.Length > 0) await upstream.WriteAsync(leftover, stoppingToken);
        logger.LogInformation("Tunnel opened to {Host}", host);

        // Relay both directions until either side closes or the tunnel sits idle.
        using var idle = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        idle.CancelAfter(IdleTimeout);
        var toUpstream = PumpAsync(downstream, upstream, idle);
        var toDownstream = PumpAsync(upstream, downstream, idle);
        await Task.WhenAny(toUpstream, toDownstream);
        idle.Cancel();
        await Task.WhenAll(toUpstream, toDownstream);
    }

    bool IsAuthorized(string? header)
    {
        if (header is null || !header.StartsWith("Basic ", StringComparison.OrdinalIgnoreCase)) return false;
        byte[] decoded;
        try { decoded = Convert.FromBase64String(header[6..].Trim()); } catch (FormatException) { return false; }
        var separator = Array.IndexOf(decoded, (byte)':');
        if (separator < 0) return false;
        var userMatches = CryptographicOperations.FixedTimeEquals(decoded.AsSpan(0, separator), usernameBytes);
        var passwordMatches = CryptographicOperations.FixedTimeEquals(SHA256.HashData(decoded.AsSpan(separator + 1)), passwordHash);
        return userMatches & passwordMatches;
    }

    static bool TryParseTarget(string target, out string host, out int port)
    {
        host = ""; port = 0;
        var colon = target.LastIndexOf(':');
        if (colon <= 0 || !int.TryParse(target[(colon + 1)..], out port)) return false;
        host = target[..colon].Trim('[', ']').ToLowerInvariant();
        return host.Length > 0;
    }

    static async Task<(string? Header, byte[] Leftover)> ReadHeaderAsync(Stream stream, CancellationToken token)
    {
        var buffer = new byte[MaxHeaderBytes];
        var length = 0;
        while (length < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(length), token);
            if (read == 0) return (null, []);
            length += read;
            var end = buffer.AsSpan(0, length).IndexOf(HeaderEnd);
            if (end >= 0)
                return (Encoding.ASCII.GetString(buffer, 0, end), buffer[(end + HeaderEnd.Length)..length]);
        }
        return (null, []);
    }

    static Task RespondAsync(Stream stream, string status, CancellationToken token, string extraHeaders = "") =>
        stream.WriteAsync(Encoding.ASCII.GetBytes($"HTTP/1.1 {status}\r\n{extraHeaders}Content-Length: 0\r\nConnection: close\r\n\r\n"), token).AsTask();

    static async Task PumpAsync(Stream from, Stream to, CancellationTokenSource idle)
    {
        var buffer = ArrayPool<byte>.Shared.Rent(16 * 1024);
        try
        {
            int read;
            while ((read = await from.ReadAsync(buffer, idle.Token)) > 0)
            {
                await to.WriteAsync(buffer.AsMemory(0, read), idle.Token);
                idle.CancelAfter(IdleTimeout);
            }
        }
        catch (Exception error) when (error is IOException or SocketException or OperationCanceledException or ObjectDisposedException) { }
        finally { ArrayPool<byte>.Shared.Return(buffer); }
    }
}
