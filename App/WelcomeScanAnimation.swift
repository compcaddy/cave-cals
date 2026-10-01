import SwiftUI

/// The welcome logo, animated: the caveman lifts his phone, scans the drumstick (brackets, rays, a flash,
/// and a 0–100% label), lowers it, and rests before the next loop.
///
/// Adapted from the September 30, 2026 animation kit. Its body, arm, and wordmark layers
/// (`WelcomeScanBody`/`Arm`/`Wordmark`) share one 1086×1448 canvas, the same size as `WelcomeLogo`,
/// so it drops into the logo's frame unchanged. Reduce Motion shows the still `WelcomeLogo` instead.
struct WelcomeScanAnimation: View {
    /// Starts (or resumes) the loop. The first lift waits a moment so the intro's last line can land.
    var isRunning: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = WelcomeScanClock()
    @State private var isVisible = false

    static let canvas = CGSize(width: 1086, height: 1448)
    private var shouldRun: Bool { isRunning && isVisible && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shouldRun)) { _ in
            WelcomeScanArtwork(frame: WelcomeScanFrame(elapsed: clock.elapsed(at: ProcessInfo.processInfo.systemUptime)))
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
        .onAppear { isVisible = true; updateClock() }
        .onDisappear { isVisible = false; updateClock() }
        .onChange(of: scenePhase) { updateClock() }
        .onChange(of: isRunning) { updateClock() }
    }

    private func updateClock() { clock.setRunning(shouldRun, at: ProcessInfo.processInfo.systemUptime) }
}

/// One moment of the loop, in the kit's timing (seconds from the start of each loop).
struct WelcomeScanFrame {
    /// Extra hold before the very first lift, while the intro's last line lands.
    static let leadIn = 0.5
    /// Each loop holds still this long before lifting the phone.
    static let lift = 0.45
    static let scanStart = 2.85
    /// The label fills 0–100% in 1.425 s.
    static let scanEnd = scanStart + 1.425
    /// The phone is fully lowered again.
    static let lowered = scanEnd + 2.1
    /// The still pose between loops, from the phone coming down to the next lift.
    static let restPause = 2.0
    static let loopDuration = lowered + restPause - lift

    /// 0 holds the phone up to scan; 1 is the lowered resting pose.
    var armLowering: Double
    var corners: Double
    var rays: Double
    var rayLength: Double
    var rayPulse: Double
    var flash: Double
    var label: Double
    var progress: Double
    var isComplete: Bool

    init(elapsed: TimeInterval) {
        let time = max(0, elapsed - Self.leadIn).truncatingRemainder(dividingBy: Self.loopDuration)
        let end = Self.scanEnd
        let fade = 1 - Self.smooth(end + 0.6, end + 1.15, time)
        armLowering = 1 - Self.smooth(Self.lift, 1.55, time) + Self.smooth(end + 1.25, Self.lowered, time)
        corners = Self.smooth(1.6, 1.95, time) * fade
        rays = Self.smooth(2.02, 2.28, time) * (1 - Self.smooth(end + 0.05, end + 0.3, time))
        rayLength = Self.smooth(2.05, 2.58, time)
        rayPulse = 0.75 + 0.25 * sin(time * 6.5)
        flash = max(0, 1 - abs(time - 2.38) / 0.19)
        label = Self.smooth(2.55, Self.scanStart, time) * fade
        progress = Self.smooth(Self.scanStart, end, time)
        isComplete = time >= end
    }

    /// Smoothstep from 0 at `start` to 1 at `end`.
    private static func smooth(_ start: Double, _ end: Double, _ value: Double) -> Double {
        let fraction = min(1, max(0, (value - start) / (end - start)))
        return fraction * fraction * (3 - 2 * fraction)
    }
}

/// Elapsed running time that doesn't advance while paused (backgrounded or off screen), so the loop
/// resumes where it stopped. Uses uptime so clock changes can't jump it.
struct WelcomeScanClock {
    private var accumulated = 0.0
    private var runningSince: Double?

    func elapsed(at uptime: Double) -> Double {
        accumulated + (runningSince.map { max(0, uptime - $0) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at uptime: Double) {
        if running, runningSince == nil { runningSince = uptime }
        if !running, runningSince != nil {
            accumulated = elapsed(at: uptime)
            runningSince = nil
        }
    }
}

/// Draws one frame. Coordinates are in the art's 1086×1448 canvas.
private struct WelcomeScanArtwork: View {
    let frame: WelcomeScanFrame

    /// The arm swings around the shoulder; lowered is 0.15 rad clockwise.
    private static let armPivot = UnitPoint(x: 382 / 1086, y: 638 / 1448)
    /// The label is drawn this much larger than the kit's so it can be read at welcome-screen size.
    /// It grows up and to the right from its lower-left corner, past the art's edge into the page margin.
    private static let labelBoost = 2.5
    private static let labelSize = CGSize(width: 308, height: 92)
    private static let labelOrigin = CGPoint(x: 744, y: 249)

    private static let bracketColor = Color(red: 71 / 255, green: 37 / 255, blue: 16 / 255)
    private static let rayColor = Color(red: 248 / 255, green: 97 / 255, blue: 18 / 255)
    private static let rayHighlight = Color(red: 1, green: 199 / 255, blue: 99 / 255)
    private static let labelColor = Color(red: 57 / 255, green: 37 / 255, blue: 23 / 255)
    private static let labelText = Color(red: 1, green: 244 / 255, blue: 223 / 255)
    private static let labelTrack = Color(red: 114 / 255, green: 80 / 255, blue: 54 / 255)
    private static let labelFill = Color(red: 1, green: 138 / 255, blue: 37 / 255)

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / WelcomeScanAnimation.canvas.width
            let unit = scale * Self.labelBoost
            ZStack(alignment: .topLeading) {
                Image("WelcomeScanBody").resizable()
                Image("WelcomeScanArm").resizable()
                    .rotationEffect(.radians(frame.armLowering * 0.15), anchor: Self.armPivot)
                Image("WelcomeScanWordmark").resizable()
                Canvas { context, _ in
                    context.scaleBy(x: scale, y: scale)
                    drawBrackets(in: context)
                    drawRays(in: context)
                    drawFlash(in: context)
                }
                if frame.label > 0 {
                    Canvas { context, _ in
                        context.scaleBy(x: unit, y: unit)
                        drawLabel(in: context)
                    }
                    .frame(width: Self.labelSize.width * unit, height: Self.labelSize.height * unit)
                    .opacity(frame.label)
                    // Rises a little as it fades in.
                    .offset(x: Self.labelOrigin.x * scale,
                            y: Self.labelOrigin.y * scale - Self.labelSize.height * unit + (1 - frame.label) * 8 * scale)
                }
            }
        }
    }

    /// Four corner brackets around the drumstick, closing in as they appear.
    private func drawBrackets(in context: GraphicsContext) {
        guard frame.corners > 0 else { return }
        var context = context
        context.opacity *= frame.corners
        let gap = (1 - frame.corners) * 17
        let corners: [(x: Double, y: Double, dx: Double, dy: Double)] = [
            (817 - gap, 273 - gap, 1, 1), (1036 + gap, 273 - gap, -1, 1),
            (817 - gap, 493 + gap, 1, -1), (1036 + gap, 493 + gap, -1, -1),
        ]
        for corner in corners {
            stroke([CGPoint(x: corner.x, y: corner.y + corner.dy * 32), CGPoint(x: corner.x, y: corner.y),
                    CGPoint(x: corner.x + corner.dx * 32, y: corner.y)],
                   in: context, color: Self.bracketColor, width: 12)
        }
    }

    /// Three pulsing rays from the phone to the drumstick.
    private func drawRays(in context: GraphicsContext) {
        guard frame.rays > 0 else { return }
        let phone = CGPoint(x: 741, y: 405)
        for target in [CGPoint(x: 819, y: 339), CGPoint(x: 819, y: 402), CGPoint(x: 819, y: 461)] {
            let end = CGPoint(x: phone.x + (target.x - phone.x) * frame.rayLength,
                              y: phone.y + (target.y - phone.y) * frame.rayLength)
            var ray = context
            ray.opacity *= frame.rays * frame.rayPulse
            stroke([phone, end], in: ray, color: Self.rayColor, width: 10)
            var highlight = context
            highlight.opacity *= frame.rays * 0.45
            stroke([phone, end], in: highlight, color: Self.rayHighlight, width: 3)
        }
    }

    /// A brief glow at the phone as the scan starts.
    private func drawFlash(in context: GraphicsContext) {
        guard frame.flash > 0 else { return }
        var context = context
        context.opacity *= frame.flash * 0.8
        let gradient = Gradient(stops: [
            .init(color: Color(red: 1, green: 254 / 255, blue: 241 / 255), location: 0),
            .init(color: Color(red: 1, green: 232 / 255, blue: 160 / 255), location: 0.18),
            .init(color: .clear, location: 1),
        ])
        context.fill(Path(ellipseIn: CGRect(x: 669, y: 333, width: 144, height: 144)),
                     with: .radialGradient(gradient, center: CGPoint(x: 741, y: 405), startRadius: 0, endRadius: 72))
    }

    /// “SCANNING CALORIES” with a filling bar and percentage, then “SCAN COMPLETE”. In the label's own coordinates.
    private func drawLabel(in context: GraphicsContext) {
        let size = Self.labelSize
        context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18), with: .color(Self.labelColor))
        context.draw(Text(frame.isComplete ? "SCAN COMPLETE" : "SCANNING CALORIES")
            .font(.system(size: 21, weight: .semibold)).foregroundColor(Self.labelText),
                     at: CGPoint(x: 18, y: 26), anchor: .leading)
        context.draw(Text("\(Int((frame.progress * 100).rounded(.down)))%")
            .font(.system(size: 21, weight: .bold).monospacedDigit()).foregroundColor(Self.labelFill),
                     at: CGPoint(x: size.width - 18, y: 58), anchor: .trailing)
        let track = CGRect(x: 18, y: 52, width: 206, height: 12)
        context.fill(Path(roundedRect: track, cornerRadius: 6), with: .color(Self.labelTrack))
        if frame.progress > 0 {
            var fill = track
            fill.size.width = max(12, track.width * frame.progress)
            context.fill(Path(roundedRect: fill, cornerRadius: 6), with: .color(Self.labelFill))
        }
    }

    private func stroke(_ points: [CGPoint], in context: GraphicsContext, color: Color, width: Double) {
        var path = Path()
        path.addLines(points)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
