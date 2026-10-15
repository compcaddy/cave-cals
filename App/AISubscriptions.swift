import SwiftUI
import StoreKit
import RevenueCat
import RevenueCatUI

@MainActor @Observable final class AISubscriptions {
    var account: AIAccount?
    var products: [StoreKit.Product] = []
    var trialEligible: Set<String> = []
    var busy = false
    var message: String?
    var messageIsError = false
    /// RevenueCat's current offering. In-app discount codes were removed October 13, 2026 (App Review, 3.1.1).
    var offering: Offering?

    private func connectRevenueCat() async {
        guard !AppEnvironment.isDevelopment, let account else { return }
        let userID = account.accountId.uuidString.lowercased()
        if !Purchases.isConfigured {
            Purchases.configure(with: Configuration.Builder(withAPIKey: "appl_zPaidztOuPJEvGUwaUUrNxfALHk")
                .with(appUserID: userID)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build())
        } else if Purchases.shared.appUserID != userID {
            _ = try? await Purchases.shared.logIn(userID)
        }
        offering = try? await Purchases.shared.offerings().current
    }
    func refresh(regularLogCount: Int = 0) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            account = try await AIBackend.shared.status(regularLogCount: regularLogCount)
            if AppEnvironment.isDevelopment {
                products = []; trialEligible = []; offering = nil
                message = "Purchases are disabled in Cave Cals Dev. Use Developer settings for private AI test access."
                messageIsError = false
                return
            }
            if account?.active == false && account?.testing != true {
                for await result in StoreKit.Transaction.currentEntitlements {
                    if case .verified(let transaction) = result, account?.productIds.contains(transaction.productID) == true {
                        try await AIBackend.shared.purchase(result.jwsRepresentation)
                        account = try await AIBackend.shared.status()
                        break
                    }
                }
            }
            products = try await StoreKit.Product.products(for: account?.productIds ?? []).filter { $0.type == .autoRenewable }.sorted { $0.price < $1.price }
            trialEligible = []
            for product in products {
                if let subscription = product.subscription,
                   subscription.introductoryOffer?.paymentMode == .freeTrial,
                   await subscription.isEligibleForIntroOffer {
                    trialEligible.insert(product.id)
                }
            }
            await connectRevenueCat()
            message = nil; messageIsError = false
            if let account { UsageStats.shared.noteMembership(account.active) }
        } catch {
            message = error.localizedDescription
            messageIsError = true
            UsageStats.shared.error(.subscription, error)
        }
    }
    @discardableResult
    func buy(_ product: StoreKit.Product) async -> (userCancelled: Bool, error: Error?) {
        guard !AppEnvironment.isDevelopment else { return (false, Self.devPurchaseError) }
        guard let account, !busy else { return (false, AIServiceError(code:"busy",message:"Please wait for access to finish loading.")) }
        busy = true; defer { busy = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(account.accountId)]) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { throw AIServiceError(code:"purchase",message:"The purchase could not be verified.") }
                try await AIBackend.shared.purchase(verification.jwsRepresentation)
                await transaction.finish()
                self.account = try await AIBackend.shared.status(); message = nil; messageIsError = false
                await connectRevenueCat()
                if Purchases.isConfigured { _ = try? await Purchases.shared.syncPurchases() }
                return (false, nil)
            case .pending: throw AIServiceError(code:"pending",message:"Your purchase is awaiting approval.")
            case .userCancelled: return (true, nil)
            @unknown default: throw AIServiceError(code:"purchase",message:"The purchase could not be completed.")
            }
        } catch {
            message = error.localizedDescription
            messageIsError = true
            UsageStats.shared.error(.subscription, error)
            return (false, error)
        }
    }
    private static var devPurchaseError: AIServiceError {
        AIServiceError(code: "dev_purchase", message: "Purchases and restores are disabled in Cave Cals Dev. Your normal Cave Cals subscription is separate.")
    }
    @discardableResult
    func restore() async -> (success: Bool, error: Error?) {
        guard !AppEnvironment.isDevelopment else {
            message = Self.devPurchaseError.localizedDescription; messageIsError = true
            return (false, Self.devPurchaseError)
        }
        guard !busy else { return (false, AIServiceError(code:"busy",message:"Please wait for access to finish loading.")) }
        busy = true; defer { busy = false }
        do {
            try await StoreKit.AppStore.sync()
            var restored = false
            for await result in StoreKit.Transaction.currentEntitlements {
                guard case .verified(let transaction) = result, account?.productIds.contains(transaction.productID) == true else { continue }
                try await AIBackend.shared.purchase(result.jwsRepresentation); restored = true; break
            }
            account = try await AIBackend.shared.status()
            message = restored ? "Purchase restored." : "No active subscription was found for this App Store account."
            messageIsError = false
            await connectRevenueCat()
            if Purchases.isConfigured { _ = try? await Purchases.shared.syncPurchases() }
            return (restored && account?.active == true, nil)
        } catch {
            message = error.localizedDescription
            messageIsError = true
            UsageStats.shared.error(.subscription, error)
            return (false, error)
        }
    }
    static func listenForPurchases() async {
        guard !AppEnvironment.isDevelopment else { return }
        for await result in StoreKit.Transaction.updates {
            guard !Task.isCancelled, AIConfiguration.baseURL != nil, case .verified(let transaction) = result else { continue }
            do { try await AIBackend.shared.purchase(result.jwsRepresentation); await transaction.finish() }
            catch { /* Leave unfinished; StoreKit will redeliver and Restore Purchases can retry. */ }
        }
    }
}

/// RevenueCat owns the paywall UI; the app still verifies purchases with its backend.
@MainActor final class PaywallDismissalGate {
    private(set) var hasRequestedDismissal = false

    func request(_ action: () -> Void) {
        guard !hasRequestedDismissal else { return }
        hasRequestedDismissal = true
        action()
    }
}

/// Reports one showing of the paywall and how it ended, whichever way the screen goes away.
@MainActor final class PaywallStatsReport {
    private var shown = false, finished = false
    func show(_ trigger: PaywallTrigger) {
        guard !shown else { return }
        shown = true
        UsageStats.shared.paywallShown(trigger)
    }
    func finish(_ trigger: PaywallTrigger, _ result: String, product: String? = nil) {
        guard shown, !finished else { return }
        finished = true
        UsageStats.shared.paywallResult(trigger, result, product: product)
    }
}

struct AIUpgradePaywall: View {
    let subscriptions: AISubscriptions
    /// What put the paywall on screen, for the stats.
    let trigger: PaywallTrigger
    var onAccessGranted: () -> Void = {}
    let onDismissRequested: () -> Void
    @State private var dismissalGate = PaywallDismissalGate()
    @State private var report = PaywallStatsReport()

    var body: some View {
        Group {
            if let offering = subscriptions.offering {
                PaywallView(offering: offering, fonts: CustomPaywallFontProvider(fontName: "Schoolbell-Regular"), displayCloseButton: true, performPurchase: { package in
                    guard subscriptions.offering?.identifier == offering.identifier,
                          let product = subscriptions.products.first(where: { $0.id == package.storeProduct.productIdentifier }) else {
                        return (false, AIServiceError(code: "product", message: "This subscription is unavailable. Please try again."))
                    }
                    let trial = subscriptions.trialEligible.contains(product.id)
                    let result = await subscriptions.buy(product)
                    if result.error == nil && !result.userCancelled && subscriptions.account?.active == true {
                        report.finish(trigger, trial ? "trial" : "purchased", product: product.id)
                        grantAccessAndDismiss()
                    }
                    return result
                }, performRestore: {
                    let result = await subscriptions.restore()
                    if result.success {
                        report.finish(trigger, "restored")
                        grantAccessAndDismiss()
                    }
                    return result
                })
                .onRequestedDismissal { requestDismissal() }
            } else {
                ContentUnavailableView {
                    Label { Text("Subscriptions unavailable") } icon: { CaveIcon(.warning, size: 48) }
                } description: {
                    Text(AppEnvironment.isDevelopment ? "Purchases are disabled in Cave Cals Dev. Private AI test access is configured in Developer settings." : "Please close this screen and try again.")
                } actions: {
                    if !AppEnvironment.isDevelopment {
                        Button("Try Again") { Task { await subscriptions.refresh() } }
                            .hapticButtonStyle(.bordered)
                            .disabled(subscriptions.busy)
                    }
                    Button("Close") { requestDismissal() }
                }
            }
        }
        .accessibilityIdentifier("aiUpgradePaywall")
        .navigationBarBackButtonHidden(true)
        .onAppear { report.show(trigger) }
        .onDisappear { report.finish(trigger, subscriptions.offering == nil ? "unavailable" : "closed") }
    }

    private func grantAccessAndDismiss() {
        dismissalGate.request {
            onAccessGranted()
            onDismissRequested()
        }
    }

    private func requestDismissal() {
        dismissalGate.request(onDismissRequested)
    }
}

/// Setup is already saved. "Where did you hear about Cave Cals?" comes first while
/// Cave Cals+ loads behind it, then the offer. Neither may block access to the diary.
struct OnboardingUpgradeView: View {
    @Environment(AppStore.self) private var store
    @State private var subscriptions = AISubscriptions()
    @State private var loading = true
    @State private var askingSource = DiscoverySourceView.shouldAsk
    @State private var dismissalGate = PaywallDismissalGate()
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if askingSource {
                    DiscoverySourceView { sourceAnswered() }
                } else if loading {
                    ProgressView("Loading Cave Cals+…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AIUpgradePaywall(subscriptions: subscriptions, trigger: .onboarding, onDismissRequested: finish)
                }
            }
            .caveScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !askingSource {
                    Button("Skip for now", action: finish)
                        .font(.cave(.body))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 8)
                        .background(Color.caveBackground)
                        .hapticButtonStyle(.plain)
                        .accessibilityIdentifier("skipOnboardingPaywall")
                }
            }
            .task {
                #if DEBUG
                // Keep onboarding UI tests independent of App Attest and the storefront.
                if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                    loading = false
                    return
                }
                #endif
                await subscriptions.refresh(regularLogCount: store.regularLogCount)
                guard !Task.isCancelled else { return }
                // Members skip the offer, but not a question that's still on screen.
                if subscriptions.account?.active == true && !askingSource { finish() }
                loading = false
            }
        }
        .accessibilityIdentifier("onboardingPaywall")
    }

    private func sourceAnswered() {
        if subscriptions.account?.active == true { finish(); return }
        askingSource = false
    }

    private func finish() { dismissalGate.request(onComplete) }
}

/// Settings' one-line Cave Cals+ row (October 14, 2026): status at a glance, the full card a tap away,
/// so Settings doesn't open on a 190-pt logo.
struct AISubscriptionRow: View {
    let subscriptions: AISubscriptions

    var body: some View {
        Section {
            NavigationLink { CaveCalsPlusView(subscriptions: subscriptions).hapticOnPush() } label: {
                HStack(spacing: 12) {
                    CaveIcon(.plus, size: 26).foregroundStyle(Color.caveOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cave Cals+").foregroundStyle(Color.primary)
                        if let detail {
                            Text(detail).font(.cave(.footnote)).foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    status
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("caveCalsPlusRow")
        }
    }

    /// Nothing until the membership is known, so a member is never told to upgrade.
    @ViewBuilder private var status: some View {
        if let account = subscriptions.account {
            if account.active {
                Text("Active").foregroundStyle(Color.secondary)
            } else {
                Text("Upgrade").foregroundStyle(Color.caveOrange)
            }
        } else if subscriptions.busy {
            ProgressView()
        }
    }

    private var detail: String? {
        guard let account = subscriptions.account, !account.active, account.canScan else { return nil }
        return account.freeScansRemaining == 1 ? "1 free scan left" : "\(account.freeScansRemaining) free scans left"
    }
}

/// Settings → Cave Cals+: the full membership card, with the paywall pushed from here.
struct CaveCalsPlusView: View {
    let subscriptions: AISubscriptions
    @State private var showingPaywall = false

    var body: some View {
        HapticForm {
            AISubscriptionSection(subscriptions: subscriptions) { showingPaywall = true }
        }
        .caveScreenBackground()
        .navigationTitle("Cave Cals+").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingPaywall) {
            AIUpgradePaywall(subscriptions: subscriptions, trigger: .settings, onDismissRequested: { showingPaywall = false })
        }
    }
}

struct AISubscriptionSection: View {
    @Environment(AppStore.self) private var store
    let subscriptions: AISubscriptions
    let openPaywall: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 16) {
                // The caveman logo is tall, so its height sets the size.
                Image("CaveCalsPlusLogo")
                    .resizable()
                    .scaledToFit()
                    .creamBadgeInDarkMode(cornerRadius: 24, padding: 12)
                    .frame(maxHeight: 190)
                    .accessibilityLabel("Cave Cals Plus")

                if subscriptions.busy {
                    ProgressView("Checking membership…")
                        .frame(minHeight: 64)
                } else if subscriptions.account?.active == true {
                    membershipStatus
                } else {
                    upgradeInvitation
                }

                if let message = subscriptions.message {
                    Text(message)
                        .font(.cave(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if subscriptions.messageIsError {
                        Button("Try Again") {
                            Task { await subscriptions.refresh(regularLogCount: store.regularLogCount) }
                        }
                        .hapticButtonStyle(.bordered)
                        .frame(minHeight: 44)
                        .disabled(subscriptions.busy)
                        .accessibilityIdentifier("retryAIConnection")
                    }
                }

                membershipActions
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var membershipStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            CaveIcon(.check, size: 24)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("You’re a Cave Cals+ member")
                    .font(.cave(.headline))
                Text("Premium meal logging is ready whenever you are.")
                    .font(.cave(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var upgradeInvitation: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                if let account = subscriptions.account, account.canScan {
                    Text("\(account.freeScansRemaining) free scans remaining")
                        .font(.cave(.headline))
                    Text("Shared between Meal Scan and Voice Log, until you’ve logged 100 regular food entries.")
                        .font(.cave(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Text("Smarter logging, carved for real life.")
                    .font(.cave(.headline))
                    .multilineTextAlignment(.center)
                Text("Snap a meal, speak what you ate, or import a recipe. Cave Cals+ turns it into an editable log in seconds.")
                    .font(.cave(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: openPaywall) {
                HStack(spacing: 8) {
                    CaveIcon(.plus, size: 18)
                    Text("Explore Cave Cals+")
                }
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .hapticButtonStyle(.borderedProminent)
            .disabled(subscriptions.offering == nil)
            .accessibilityIdentifier("aiPaywall")
        }
    }

    @ViewBuilder private var membershipActions: some View {
        if subscriptions.account?.active == true {
            HStack(spacing: 12) {
                Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Text("·").foregroundStyle(.tertiary)
                restoreButton
            }
            .font(.cave(.footnote))
        } else {
            restoreButton
                .font(.cave(.footnote))
        }
    }

    private var restoreButton: some View {
        Button("Restore purchases") { Task { await subscriptions.restore() } }
            .hapticButtonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(subscriptions.busy || subscriptions.account == nil)
    }
}
