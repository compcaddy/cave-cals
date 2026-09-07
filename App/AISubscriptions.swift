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
    func refresh() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            account = try await AIBackend.shared.status()
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
        } catch { message = error.localizedDescription }
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
                self.account = try await AIBackend.shared.status(); message = nil
                await connectRevenueCat()
                if Purchases.isConfigured { _ = try? await Purchases.shared.syncPurchases() }
                return (false, nil)
            case .pending: throw AIServiceError(code:"pending",message:"Your purchase is awaiting approval.")
            case .userCancelled: return (true, nil)
            @unknown default: throw AIServiceError(code:"purchase",message:"The purchase could not be completed.")
            }
        } catch { message = error.localizedDescription; return (false, error) }
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
            await connectRevenueCat()
            if Purchases.isConfigured { _ = try? await Purchases.shared.syncPurchases() }
            return (restored && account?.active == true, nil)
        } catch { message = error.localizedDescription; return (false, error) }
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
struct AIUpgradePaywall: View {
    @Environment(\.dismiss) private var dismiss
    let subscriptions: AISubscriptions
    var onAccessGranted: () -> Void = {}
    var body: some View {
        if let offering = subscriptions.offering {
            PaywallView(offering: offering, fonts: CustomPaywallFontProvider(fontName: "Schoolbell-Regular"), displayCloseButton: true, performPurchase: { package in
                guard let product = subscriptions.products.first(where: { $0.id == package.storeProduct.productIdentifier }) else {
                    return (false, AIServiceError(code: "product", message: "This subscription is unavailable. Please try again."))
                }
                let result = await subscriptions.buy(product)
                if result.error == nil && !result.userCancelled && subscriptions.account?.active == true {
                    onAccessGranted(); dismiss()
                }
                return result
            }, performRestore: {
                let result = await subscriptions.restore()
                if result.success { onAccessGranted(); dismiss() }
                return result
            })
        } else {
            ContentUnavailableView { Label { Text("Subscriptions unavailable") } icon: { CaveIcon(.warning, size: 48) } } description: { Text("Please close this screen and try again.") }
        }
    }
}

struct AISubscriptionSection: View {
    let subscriptions: AISubscriptions
    @State private var showPaywall = false
    var body: some View {
        Section("Meal scanning & voice logging") {
            if subscriptions.busy { ProgressView("Checking access…") }
            else if subscriptions.account?.active == true {
                Label { Text("AI logging is available") } icon: { CaveIcon(.check, size: 22) }
            } else {
                Button("Upgrade meal scanning & voice logging") { showPaywall = true }
                    .disabled(subscriptions.offering == nil).accessibilityIdentifier("aiPaywall")
            }
            if let message = subscriptions.message { Text(message).font(.cave(.footnote)).foregroundStyle(.secondary) }
            Button("Restore Purchases") { Task { await subscriptions.restore() } }
                .disabled(subscriptions.busy || subscriptions.account == nil)
            Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            if let base = AIConfiguration.baseURL { Link("Privacy", destination: base.appendingPathComponent("privacy")) }
        }.sheet(isPresented: $showPaywall) { AIUpgradePaywall(subscriptions: subscriptions) }
    }
}
