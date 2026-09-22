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
    var offering: Offering?

    private func connectRevenueCat() async {
        guard let account else { return }
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
            message = nil
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
    @discardableResult
    func buy(_ product: StoreKit.Product) async -> (userCancelled: Bool, error: Error?) {
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
            return (false, error)
        }
    }
    @discardableResult
    func restore() async -> (success: Bool, error: Error?) {
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
            return (false, error)
        }
    }
    static func listenForPurchases() async {
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

struct AIUpgradePaywall: View {
    let subscriptions: AISubscriptions
    var onAccessGranted: () -> Void = {}
    let onDismissRequested: () -> Void
    @State private var dismissalGate = PaywallDismissalGate()

    var body: some View {
        Group {
            if let offering = subscriptions.offering {
                PaywallView(offering: offering, fonts: CustomPaywallFontProvider(fontName: "Schoolbell-Regular"), displayCloseButton: true, performPurchase: { package in
                    guard let product = subscriptions.products.first(where: { $0.id == package.storeProduct.productIdentifier }) else {
                        return (false, AIServiceError(code: "product", message: "This subscription is unavailable. Please try again."))
                    }
                    let result = await subscriptions.buy(product)
                    if result.error == nil && !result.userCancelled && subscriptions.account?.active == true {
                        grantAccessAndDismiss()
                    }
                    return result
                }, performRestore: {
                    let result = await subscriptions.restore()
                    if result.success { grantAccessAndDismiss() }
                    return result
                })
                .onRequestedDismissal { requestDismissal() }
            } else {
                ContentUnavailableView {
                    Label { Text("Subscriptions unavailable") } icon: { CaveIcon(.warning, size: 48) }
                } description: {
                    Text("Please close this screen and try again.")
                } actions: {
                    Button("Close") { requestDismissal() }
                }
            }
        }
        .accessibilityIdentifier("aiUpgradePaywall")
        .navigationBarBackButtonHidden(true)
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

struct AISubscriptionSection: View {
    @Environment(AppStore.self) private var store
    let subscriptions: AISubscriptions
    let openPaywall: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 16) {
                Image("CaveCalsPlusLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
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
                        .buttonStyle(.bordered)
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
            .buttonStyle(.borderedProminent)
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
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(subscriptions.busy || subscriptions.account == nil)
    }
}
