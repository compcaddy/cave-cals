import Foundation
import CryptoKit
import DeviceCheck
import OSLog
import Security

struct AIAccount: Decodable {
    let accountId: UUID
    let active: Bool
    let canScan: Bool
    let freeScansRemaining: Int
    let scansUsed: Int
    let regularLogCount: Int
    var testing: Bool? = nil
    let productIds: [String]
    let dailyLimit: Int
    let monthlyLimit: Int
}
struct AIFoodEstimate: Codable, Identifiable {
    var id: String { name + portion }
    var name: String
    var calories: Double
    var portion: String
    // Optional so results cached by the previous backend contract still work.
    var servingSize: String?
    var servings: Double?
    var confidence: String
}
struct AIResult: Codable {
    var items: [AIFoodEstimate]
    var notes: String
    var transcript: String?
    func drafts(at date: Date, source: String) -> [EntryDraft] {
        items.map { item in
            var draft = EntryDraft(name: item.name, calories: item.calories, timestamp: date)
            let size = item.servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
            let microscopic = size?.range(
                of: #"\b(grain|kernel|crumb|drop|noodle|flake)s?\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            let structuredCount = item.servings.flatMap {
                $0.isFinite && $0 > 0 && $0 <= 100 && size?.isEmpty == false && !microscopic ? $0 : nil
            }
            let count = structuredCount ?? 1
            draft.source = source
            draft.servingDescription = structuredCount == nil ? item.portion : size!
            draft.servings = count
            draft.perServing = (item.calories / count).rounded()
            return draft
        }
    }
}
struct AIMealImportResult: Codable {
    var mealName: String
    var items: [AIFoodEstimate]
    var notes: String

    func drafts(at date: Date, source: String) -> [EntryDraft] {
        AIResult(items: items, notes: notes, transcript: nil).drafts(at: date, source: source)
    }
}
struct AIServiceError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}
enum AIConfiguration {
    static let productionURL = URL(string: "https://cavecals.vercel.app")!
    static var developerSettingsAvailable: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
    static var savedDeveloperToken: String? {
        guard developerSettingsAvailable else { return nil }
        let value = (KeychainValue.read("ai.debug.token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    static func selectedURL(token: String?, override: String?) -> URL? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return productionURL }
        return validURL(override ?? "http://127.0.0.1:3000", allowLocal: true)
    }
    static var baseURL: URL? {
        selectedURL(token: savedDeveloperToken, override: UserDefaults.standard.string(forKey: "ai.debug.url"))
    }
    static var testAccess: [String: Any]? {
        guard developerSettingsAvailable, UserDefaults.standard.bool(forKey: "ai.test.enabled"),
              baseURL == productionURL,
              let key = KeychainValue.read("ai.test.key"), !key.isEmpty else { return nil }
        return ["key": key, "active": UserDefaults.standard.bool(forKey: "ai.test.upgraded")]
    }
    static func validURL(_ value: String, allowLocal: Bool) -> URL? {
        guard let url = URL(string: value), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        if url.scheme == "https" { return url }
        if allowLocal && url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        return nil
    }
    static var developerToken: String? {
        // Local developer credentials must never be sent to a remote server.
        guard let url = baseURL, ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "") else { return nil }
        return savedDeveloperToken
    }

}
enum KeychainValue {
    private static let service = "com.philstarkovich.cavecals.backend"
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:key, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String?, key: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:key]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var item = query; item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AIServiceError(code: "keychain", message: "Could not save the device credential. Please try again.") }
    }
}

// Serialize authenticated requests so App Attest counters reach the server in order.
actor AIBackend {
    static let shared = AIBackend()
    private static let verificationLogger = Logger(subsystem: "com.philstarkovich.cavecals", category: "AppAttest")
    private var gate: Task<Void, Never>?
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 240; config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }
    func status(regularLogCount: Int = 0) async throws -> AIAccount { try await signed("account/status", fields: ["regularLogCount": regularLogCount]) }
    func purchase(_ jws: String) async throws {
        struct Result: Decodable { let accountId: UUID }
        let _: Result = try await signed("purchase/verify", fields: ["signedTransaction":jws])
    }
    func identify(data: Data, kind: String, mime: String, existingUpload: String? = nil, regularLogCount: Int = 0, onUpload: @Sendable (String) async -> Void = { _ in }) async throws -> AIResult {
        let uploadId: String
        if let existingUpload { uploadId = existingUpload }
        else {
            struct Upload: Decodable { let uploadId: String; let uploadURL: URL; let contentType: String }
            let upload: Upload = try await signed("uploads/sign", fields: ["regularLogCount":regularLogCount,"kind":kind,"mime":mime,"byteLength":data.count,"sha256":SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()])
            var request = URLRequest(url:upload.uploadURL);request.httpMethod="PUT"
            request.setValue(upload.contentType, forHTTPHeaderField:"Content-Type")
            if let base = AIConfiguration.baseURL, upload.uploadURL.host == base.host, upload.uploadURL.port == base.port, let token = AIConfiguration.developerToken { request.setValue("Bearer \(token)", forHTTPHeaderField:"Authorization") }
            let (_, response) = try await session.upload(for:request,from:data)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AIServiceError(code:"upload_failed",message:"The upload failed. Please try again.") }
            uploadId=upload.uploadId
            await onUpload(uploadId)
        }
        return try await signed("food/analyze",fields:["uploadId":uploadId,"regularLogCount":regularLogCount])
    }
    func importMeal(from url: URL) async throws -> AIMealImportResult {
        try await signed("meal/import", fields: ["url": url.absoluteString])
    }
    private func signed<T: Decodable>(_ path: String, fields: [String:Any]) async throws -> T {
        let previous = gate
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gate = Task { for await _ in stream {} }
        await previous?.value
        defer { continuation.finish() }
        try Task.checkCancellation()
        guard let base = AIConfiguration.baseURL else { throw AIServiceError(code:"not_configured", message:"AI logging is not available yet. Please try again after the app’s service is configured.") }
        // Recover a stale App Attest key once, without re-entering the request gate.
        for attempt in 0...1 {
            do {
                return try await authenticatedRequest(path, fields: fields, base: base)
            } catch {
                if attempt == 0, Self.needsNewDeviceKey(error) {
                    let detail = error as NSError
                    Self.verificationLogger.notice("Replacing an unusable App Attest key after \(detail.domain, privacy: .public) code \(detail.code)")
                    try KeychainValue.save(nil, key: credentialName(base))
                    continue
                }
                throw Self.customerFacingError(error)
            }
        }
        throw AIServiceError(code: "attestation", message: "Device verification could not be restored.")
    }
    static func needsNewDeviceKey(_ error: Error) -> Bool {
        if let service = error as? AIServiceError { return service.code == "unknown_device" }
        let apple = error as NSError
        return apple.domain == DCError.errorDomain && [DCError.invalidInput.rawValue, DCError.invalidKey.rawValue].contains(apple.code)
    }
    static func customerFacingError(_ error: Error) -> Error {
        let apple = error as NSError
        guard apple.domain == DCError.errorDomain else { return error }
        verificationLogger.error("App Attest failed with \(apple.domain, privacy: .public) code \(apple.code)")
        if apple.code == DCError.serverUnavailable.rawValue {
            return AIServiceError(
                code: "attestation_unavailable",
                message: "Cave Cals+ couldn’t contact Apple’s device verification service. Check your internet connection and try again."
            )
        }
        return AIServiceError(
            code: "attestation",
            message: "Cave Cals+ couldn’t verify this device right now. Please try again."
        )
    }
    func resetDeviceVerification() async throws {
        let previous = gate
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gate = Task { for await _ in stream {} }
        await previous?.value
        defer { continuation.finish() }
        guard let base = AIConfiguration.baseURL else { return }
        try KeychainValue.save(nil, key: credentialName(base))
    }
    private func authenticatedRequest<T: Decodable>(_ path: String, fields: [String: Any], base: URL) async throws -> T {
        var body = fields
        if let testAccess = AIConfiguration.testAccess { body["testAccess"] = testAccess }
        var request = URLRequest(url: base.appendingPathComponent("api/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if AIConfiguration.testAccess != nil && ["account/status", "uploads/sign", "food/analyze", "meal/import"].contains(path) {
            // The separately issued owner capability authorizes testing without App Attest.
            request.setValue("1", forHTTPHeaderField: "X-Cave-Owner-Test")
            body["nonce"] = UUID().uuidString
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        } else if let token = AIConfiguration.developerToken {
            body["nonce"] = UUID().uuidString
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        } else {
            let key = try await deviceKey(base: base)
            let nonce = try await getChallenge(base: base, key: key, purpose: "request")
            body["nonce"] = nonce
            let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            let payload = Data("POST\n\(request.url!.path)\n".utf8) + data
            let assertion = try await DCAppAttestService.shared.generateAssertion(key, clientDataHash: Data(SHA256.hash(data: payload)))
            request.setValue(key, forHTTPHeaderField: "X-App-Key")
            request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Assertion")
            request.httpBody = data
        }
        return try await send(request)
    }
    private func credentialName(_ base: URL) -> String { "ai.attest." + base.absoluteString }
    private func deviceKey(base: URL) async throws -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw AIServiceError(code:"unsupported_device",message:"Secure AI logging requires a supported physical iPhone. Use local developer settings for Simulator testing.") }
        if let key = KeychainValue.read(credentialName(base)) { return key }
        let key = try await service.generateKey()
        let nonce = try await getChallenge(base:base,key:key,purpose:"register")
        let attestation = try await service.attestKey(key,clientDataHash:Data(SHA256.hash(data:Data(nonce.utf8))))
        var request=URLRequest(url:base.appendingPathComponent("api/v1/device/register"));request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["keyId":key,"nonce":nonce,"attestation":attestation.base64EncodedString()])
        struct Registration: Decodable {let accountId:UUID}
        let _:Registration=try await send(request)
        try KeychainValue.save(key,key:credentialName(base))
        return key
    }
    private func getChallenge(base: URL,key: String,purpose: String) async throws -> String {
        var request=URLRequest(url:base.appendingPathComponent("api/v1/device/challenge"));request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["keyId":key,"purpose":purpose])
        struct Challenge:Decodable {let nonce:String}
        let result:Challenge=try await send(request);return result.nonce
    }
    private struct Failure:Decodable {struct Detail:Decodable {let code:String;let message:String};let error:Detail}
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse else {throw URLError(.badServerResponse)}
        guard (200..<300).contains(http.statusCode) else {
            if let failure=try? JSONDecoder().decode(Failure.self,from:data) {throw AIServiceError(code:failure.error.code,message:failure.error.message)}
            throw AIServiceError(code:"server",message:"The service is unavailable. Please try again.")
        }
        return try JSONDecoder().decode(T.self,from:data)
    }
}
