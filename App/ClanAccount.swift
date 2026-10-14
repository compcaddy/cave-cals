import SwiftUI
import AuthenticationServices
import CryptoKit
import PhotosUI

struct ClanSignInResult: Decodable { let session: String; let personId: String; let isNew: Bool; let displayName: String }

// MARK: Sign-in

enum ClanSignIn {
    /// A random nonce; the identity token carries its SHA-256 so it can't be replayed.
    static func rawNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }
    static func sha256(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static var googleClientID: String? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return id.isEmpty || id.hasPrefix("$(") ? nil : id
    }

    @MainActor static func send(_ fields: [String: Any]) async throws {
        let result = try await AIBackend.shared.clanSignIn(fields.merging(["acceptedTerms": true]) { a, _ in a })
        await ClanStore.shared.didSignIn(session: result.session)
        UsageStats.shared.event("clan.signIn", ["provider": fields["provider"] as? String ?? "", "new": result.isNew ? "yes" : "no"])
    }

    /// Google: the system sign-in window with PKCE (the same window Google's SDK uses), then the code is swapped
    /// for an ID token here. No client secret: it's an iOS client.
    @MainActor static func google(anchor: ASPresentationAnchor) async throws {
        guard let clientID = googleClientID else { throw ClanError(code: "not_configured", message: "Google sign-in isn’t set up yet.") }
        let scheme = "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = rawNonce() + rawNonce()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let nonce = rawNonce(), state = rawNonce()
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect), .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid profile"), .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "nonce", value: sha256(nonce)), .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: auth.url!, callbackURLScheme: scheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? ClanError(code: "canceled", message: "Sign-in was canceled.")) }
            }
            let provider = AnchorProvider(anchor: anchor)
            session.presentationContextProvider = provider
            objc_setAssociatedObject(session, &AnchorProvider.key, provider, .OBJC_ASSOCIATION_RETAIN)
            session.start()
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state, let code = items.first(where: { $0.name == "code" })?.value else {
            throw ClanError(code: "invalid_sign_in", message: "Google sign-in didn’t finish. Please try again.")
        }
        var token = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        token.httpMethod = "POST"
        token.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "client_id", value: clientID), .init(name: "code", value: code), .init(name: "code_verifier", value: verifier),
                           .init(name: "grant_type", value: "authorization_code"), .init(name: "redirect_uri", value: redirect)]
        token.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        struct Tokens: Decodable { let id_token: String }
        let (data, _) = try await URLSession.shared.data(for: token)
        guard let idToken = try? JSONDecoder().decode(Tokens.self, from: data).id_token else {
            throw ClanError(code: "invalid_sign_in", message: "Google sign-in didn’t finish. Please try again.")
        }
        try await send(["provider": "google", "identityToken": idToken, "rawNonce": nonce])
    }
    private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        static var key = 0
        let anchor: ASPresentationAnchor
        init(anchor: ASPresentationAnchor) { self.anchor = anchor }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
    }
}

/// The campfire's first screen for someone signed out: what clans are, the rules, and the sign-in buttons.
struct ClanSignInView: View {
    @State private var agreed = false
    @State private var busy = false
    @State private var message: String?
    @State private var appleNonce = ClanSignIn.rawNonce()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("CaveCampfire").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 84, height: 84).foregroundStyle(Color.caveOrange).padding(.top, 12).accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Clans").font(.cave(.largeTitle))
                    Text("Keep each other on track around the fire.").font(.cave(.callout)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    point("flame", "Streaks and challenges with friends, family, or your coach.")
                    point("eye.slash", "Your food stays private. Clanmates see only whether your day counted.")
                    point("person.crop.circle.badge.questionmark", "Join as a Cave person if you’d rather not show your name.")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 16))
                Button { agreed.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: agreed ? "checkmark.square.fill" : "square").font(.title3).foregroundStyle(Color.caveOrange)
                        Text("I agree to the clan rules: no hateful, sexual, or bullying names or photos. Reported people can be removed.")
                            .font(.cave(.footnote)).foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .hapticFeel(.selection)
                .accessibilityIdentifier("clanAgree")
                .accessibilityValue(agreed ? "Checked" : "Not checked")
                Link("Read the terms", destination: URL(string: "https://cavecals.com/terms")!).font(.cave(.footnote))
                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        appleNonce = ClanSignIn.rawNonce()
                        request.requestedScopes = [.fullName]
                        request.nonce = ClanSignIn.sha256(appleNonce)
                    } onCompletion: { result in apple(result) }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50).clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(!agreed || busy).opacity(agreed ? 1 : 0.5)
                    .accessibilityIdentifier("clanSignInApple")
                    if ClanSignIn.googleClientID != nil {
                        Button { google() } label: {
                            HStack(spacing: 10) { Text("G").font(.system(size: 20, weight: .bold)); Text("Sign in with Google").font(.system(size: 19, weight: .medium)) }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.caveSurface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.4)))
                                .foregroundStyle(Color.primary)
                        }
                        .disabled(!agreed || busy).opacity(agreed ? 1 : 0.5)
                        .accessibilityIdentifier("clanSignInGoogle")
                    }
                    if AIConfiguration.developerToken != nil {
                        Button("Developer sign-in (local backend)") { developer() }
                            .font(.cave(.footnote)).disabled(!agreed || busy).accessibilityIdentifier("clanSignInDeveloper")
                    }
                }
                if busy { ProgressView() }
                if let message { Text(message).font(.cave(.footnote)).foregroundStyle(.red).multilineTextAlignment(.center) }
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.caveOrange).frame(width: 26)
            Text(text).font(.cave(.callout))
        }
    }
    private func apple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { message = "Sign in with Apple didn’t finish. Please try again." }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { return }
            var fields: [String: Any] = ["provider": "apple", "identityToken": token, "rawNonce": appleNonce]
            if let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) { fields["authorizationCode"] = code }
            if let name = credential.fullName?.givenName, !name.isEmpty { fields["name"] = name }
            run { try await ClanSignIn.send(fields) }
        }
    }
    private func google() {
        guard let anchor = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        run { try await ClanSignIn.google(anchor: anchor) }
    }
    private func developer() {
        let key = "clan.devSubject"
        let subject = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(subject, forKey: key)
        run { try await ClanSignIn.send(["provider": "dev", "devSubject": subject, "name": "Tester"]) }
    }
    private func run(_ work: @escaping () async throws -> Void) {
        busy = true; message = nil
        Task {
            do { try await work(); Haptics.play(.success) }
            catch {
                if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin && (error as? ClanError)?.code != "canceled" {
                    message = error.localizedDescription
                    UsageStats.shared.error(.clans, error)
                }
            }
            busy = false
        }
    }
}

// MARK: Avatars

/// A clanmate's photo, initials, or the Cave person figure.
struct ClanAvatar: View {
    var photoId: String?
    var name: String
    var anonymous = false
    var size: CGFloat = 40
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Circle().fill(Color.caveOrange.opacity(0.16))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if anonymous || name.hasPrefix("Cave person") {
                CaveIcon(.person, size: size * 0.6).foregroundStyle(Color.caveOrange)
            } else {
                Text(initials).font(.system(size: size * 0.4, weight: .semibold, design: .rounded)).foregroundStyle(Color.caveOrange)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: photoId) {
            image = nil
            guard let photoId, let data = await ClanClient.shared.photo(photoId) else { return }
            image = UIImage(data: data)
        }
    }
    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: Photo cropping

/// Drag and pinch the photo inside the circle; Use Photo saves a 512-px square.
struct AvatarCropper: View {
    let image: UIImage
    var onDone: (Data) -> Void
    var onCancel: () -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    private let side: CGFloat = 300

    var body: some View {
        VStack(spacing: 24) {
            Text("Move and scale").font(.cave(.title3)).foregroundStyle(.white).padding(.top, 24)
            ZStack {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: side * scale, height: side * scale)
                    .offset(offset)
                    .frame(width: side, height: side)
                    .clipped()
                Rectangle().fill(.black.opacity(0.55)).mask {
                    Rectangle().overlay(Circle().frame(width: side, height: side).blendMode(.destinationOut)).compositingGroup()
                }.allowsHitTesting(false)
                Circle().stroke(.white.opacity(0.8), lineWidth: 2).frame(width: side, height: side).allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                offset = clamped(CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height))
            }.onEnded { _ in lastOffset = offset })
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                scale = min(4, max(1, lastScale * value.magnification)); offset = clamped(offset)
            }.onEnded { _ in lastScale = scale; lastOffset = offset })
            .accessibilityLabel("Photo crop")
            Spacer()
            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) { onCancel() }
                    .font(.cave(.headline)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 50)
                    .accessibilityIdentifier("cropCancel")
                Button { if let data = render() { onDone(data) } } label: {
                    Text("Use Photo").font(.cave(.headline)).frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.caveOrange, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }.hapticFeel(.success).accessibilityIdentifier("cropUse")
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
    }
    /// Keeps the photo covering the whole circle.
    private func clamped(_ value: CGSize) -> CGSize {
        let limit = (side * scale - side) / 2
        return CGSize(width: min(limit, max(-limit, value.width)), height: min(limit, max(-limit, value.height)))
    }
    private func render() -> Data? {
        let output: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: output, height: output), format: {
            let f = UIGraphicsImageRendererFormat.default(); f.scale = 1; return f
        }())
        let rendered = renderer.image { _ in
            // The same fill as on screen: the photo's short side fits the circle, then scale and offset apply.
            let base = image.size, fill = max(output / base.width, output / base.height) * scale
            let drawn = CGSize(width: base.width * fill, height: base.height * fill)
            let ratio = output / side
            let origin = CGPoint(x: (output - drawn.width) / 2 + offset.width * ratio, y: (output - drawn.height) / 2 + offset.height * ratio)
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }
}

// MARK: Profile

/// Your clan profile: photo, name, birth month (for weight challenges), and the account.
struct ClanProfileView: View {
    @State private var clans = ClanStore.shared
    @State private var name = ""
    @State private var birthMonth = 0
    @State private var birthYear = 0
    @State private var picked: PhotosPickerItem?
    @State private var cropping: UIImage?
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    var firstTime = false

    var body: some View {
        HapticForm {
            Section {
                HStack(spacing: 16) {
                    ClanAvatar(photoId: clans.me?.photoId, name: name.isEmpty ? "?" : name, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $picked, matching: .images) { Text("Choose photo") }
                            .accessibilityIdentifier("clanChoosePhoto")
                        if clans.me?.photoId != nil {
                            Button("Remove photo", role: .destructive) { removePhoto() }
                        }
                    }
                }.padding(.vertical, 6)
            } footer: { Text("Shown to your clanmates, except in clans where you’re a Cave person.").font(.cave(.caption2)) }
            Section("Name") {
                TextField("First name", text: $name).textContentType(.givenName).submitLabel(.done)
                    .onSubmit { saveName() }.accessibilityIdentifier("clanName")
                    .keyboardInputArea()
            }
            Section {
                Picker("Birth month", selection: $birthMonth) {
                    Text("Not set").tag(0)
                    ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
                }.hapticSelection(on: birthMonth)
                Picker("Birth year", selection: $birthYear) {
                    Text("Not set").tag(0)
                    ForEach((1920...(Calendar.current.component(.year, from: Date()) - 13)).reversed(), id: \.self) { Text(String($0)).tag($0) }
                }.hapticSelection(on: birthYear)
            } header: { Text("Birthday") } footer: {
                Text("Only needed for weight challenges, which are for adults. Never shown to anyone.").font(.cave(.caption2))
            }
            if firstTime {
                Section {
                    Button { saveName(); if !name.trimmingCharacters(in: .whitespaces).isEmpty { dismiss() } } label: {
                        Text("Continue").frame(maxWidth: .infinity)
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("clanProfileContinue")
                }
            } else {
                Section {
                    Button("Sign out of clans") { signOut() }
                    Button("Delete clan account", role: .destructive) { confirmDelete = true }.accessibilityIdentifier("clanDeleteAccount")
                } footer: {
                    Text("Deleting removes your clan profile, photo, and history from Cave Cals’ server and takes you out of every clan. Your food diary stays on this iPhone.").font(.cave(.caption2))
                }
            }
            if let message { Section { Text(message).foregroundStyle(.red).font(.cave(.footnote)) } }
        }
        .caveScreenBackground()
        .tapOutsideClosesKeyboard()
        .navigationTitle(firstTime ? "Your clan profile" : "Clan profile").navigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .onAppear {
            name = clans.me?.displayName ?? ""
            birthMonth = clans.me?.birthMonth ?? 0; birthYear = clans.me?.birthYear ?? 0
        }
        .onChange(of: birthMonth) { saveBirth() }
        .onChange(of: birthYear) { saveBirth() }
        .onChange(of: picked) {
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) { cropping = image }
                self.picked = nil
            }
        }
        .fullScreenCover(item: Binding(get: { cropping.map(CropItem.init) }, set: { if $0 == nil { cropping = nil } })) { item in
            AvatarCropper(image: item.image, onDone: { data in cropping = nil; upload(data) }, onCancel: { cropping = nil })
        }
        .confirmationDialog("Delete your clan account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete clan account", role: .destructive) { Haptics.play(.warning); deleteAccount() }.hapticFeel(.none)
            Button("Cancel", role: .cancel) { Haptics.play(.tap) }.hapticFeel(.none)
        } message: { Text("You’ll leave every clan. This can’t be undone.") }
    }
    private struct CropItem: Identifiable { let image: UIImage; var id: ObjectIdentifier { ObjectIdentifier(image) } }
    private func update(_ fields: [String: Any]) async throws {
        let profile: ClanProfile = try await ClanClient.shared.call("clan/me/update", fields)
        clans.setProfile(profile)
    }
    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != clans.me?.displayName else { return }
        Task {
            do { try await update(["displayName": trimmed]); message = nil; Haptics.play(.success) }
            catch { message = error.localizedDescription }
        }
    }
    private func saveBirth() {
        guard birthMonth != (clans.me?.birthMonth ?? 0) || birthYear != (clans.me?.birthYear ?? 0) else { return }
        var fields: [String: Any] = [:]
        if birthMonth > 0 { fields["birthMonth"] = birthMonth }
        if birthYear > 0 { fields["birthYear"] = birthYear }
        guard !fields.isEmpty else { return }
        Task { try? await update(fields) }
    }
    private func upload(_ jpeg: Data) {
        busy = true
        Task {
            do {
                struct Saved: Decodable { let photoId: String? }
                let _: Saved = try await ClanClient.shared.call("clan/me/photo", ["jpeg": jpeg.base64EncodedString()])
                let profile: ClanProfile = try await ClanClient.shared.call("clan/me")
                clans.setProfile(profile); Haptics.play(.success)
            } catch { message = error.localizedDescription; UsageStats.shared.error(.clans, error) }
            busy = false
        }
    }
    private func removePhoto() {
        Task {
            struct Saved: Decodable { let photoId: String? }
            let _: Saved? = try? await ClanClient.shared.call("clan/me/photo/remove")
            if let profile: ClanProfile = try? await ClanClient.shared.call("clan/me") { clans.setProfile(profile) }
        }
    }
    private func signOut() {
        Task {
            let _: [String: Bool]? = try? await ClanClient.shared.call("clan/signout")
            clans.signedOut(); dismiss()
        }
    }
    private func deleteAccount() {
        busy = true
        Task {
            do {
                let _: [String: Bool] = try await ClanClient.shared.call("clan/account/delete")
                clans.signedOut(); UsageStats.shared.event("clan.accountDeleted"); dismiss()
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
