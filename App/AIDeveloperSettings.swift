import SwiftUI
struct AIDeveloperSettings: View {
    @AppStorage("ai.debug.url") private var url = "http://127.0.0.1:3000"
    @AppStorage("ai.test.enabled") private var testing = false
    @AppStorage("ai.test.upgraded") private var upgraded = false
    @State private var token = KeychainValue.read("ai.debug.token") ?? ""
    @State private var testKey = KeychainValue.read("ai.test.key") ?? ""
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section {
                SecureField("DEV_API_TOKEN (optional)", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    TextField("Local backend URL", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                Button("Save and test connection") { saveConnection() }.disabled(busy)
                Button("Reset device verification") {
                    busy = true
                    Task {
                        do {
                            try await AIBackend.shared.resetDeviceVerification()
                            checkAccess()
                        } catch { busy = false; message = error.localizedDescription }
                    }
                }.disabled(busy)
                Text("No developer token means production: https://cavecals.vercel.app. A local developer token is only sent to localhost.")
                    .font(.cave(.footnote)).foregroundStyle(.secondary)
            } header: { Text("API connection") }
            Section {
                SecureField("Private test-access key", text: $testKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save test-access key") {
                    do {
                        try KeychainValue.save(testKey.trimmingCharacters(in: .whitespacesAndNewlines), key: "ai.test.key")
                        checkAccess()
                    } catch { message = error.localizedDescription }
                }.disabled(busy)
                Toggle("Override subscription for testing", isOn: $testing)
                    .disabled(busy || testKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .onChange(of: testing) { _, _ in checkAccess() }
                if testing {
                    Toggle("Upgraded access", isOn: $upgraded)
                        .accessibilityIdentifier("developerUpgradedAccess")
                        .disabled(busy)
                        .onChange(of: upgraded) { _, _ in checkAccess() }
                }
                Text("With an authorized test key, Upgraded access ON runs real meal and voice analysis. OFF tests the free experience, even if you have a subscription. Turn off the override to use your actual subscription. Production usage limits still apply.")
                    .font(.cave(.footnote)).foregroundStyle(.secondary)
            } header: { Text("Subscription testing") }
            if busy { ProgressView("Checking access…") }
            if let message { Section { Text(message).font(.cave(.footnote)) } }
        }.navigationTitle("Developer settings")
    }
    private func saveConnection() {
        do {
            let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                guard let endpoint = AIConfiguration.validURL(url, allowLocal: true),
                      ["localhost", "127.0.0.1", "::1"].contains(endpoint.host ?? "") else {
                    throw AIServiceError(code: "url", message: "Use a localhost URL for the local developer token, or clear the token to use production.")
                }
            }
            try KeychainValue.save(clean, key: "ai.debug.token")
            checkAccess()
        } catch { message = error.localizedDescription }
    }
    private func checkAccess() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let account = try await AIBackend.shared.status()
                let mode = account.testing == true ? "Test override" : "Subscription"
                message = "\(mode): \(account.active ? "upgraded access" : "free access"). Connected to \(AIConfiguration.baseURL?.host ?? "backend")."
            } catch { message = error.localizedDescription }
        }
    }
}
