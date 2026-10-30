import SwiftUI
import VoxboardShared

/// Native first-run introduction and StoreKit-backed access gate.
/// The presentation changes; purchase/restore/eligibility remain StoreManager's.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @AppStorage(Thoughtful.introductionKey) private var introductionCompleted = false
    @State private var family = false
    @State private var selectedPlanIndex = 1
    @State private var showsHistory = false
    private let historyViewModel: QuickCaptureViewModel?
    private let includesOnboarding: Bool

    let context: PaywallContext
    let isAccessGate: Bool

    init(context: PaywallContext = .limit, isAccessGate: Bool = false,
         historyViewModel: QuickCaptureViewModel? = nil, initialFamily: Bool = false,
         includesOnboarding: Bool = false) {
        self.context = context
        self.isAccessGate = isAccessGate
        self.historyViewModel = historyViewModel
        self.includesOnboarding = includesOnboarding
        _family = State(initialValue: initialFamily)
    }

    private var offers: [VoxboardPurchaseProduct] {
        if usageTracker.isEligibleForFamilyUpgrade { return [.familyUpgrade] }
        return family ? [.familyWeekly, .familyYearly, .family] : [.individualWeekly, .individualYearly, .individual]
    }

    private var selectedProduct: VoxboardPurchaseProduct {
        offers[min(selectedPlanIndex, offers.count - 1)]
    }

    var body: some View {
        Group {
            if includesOnboarding && isAccessGate && !introductionCompleted && !usageTracker.hasUnlocked {
                ThoughtfulOnboarding(onFinish: { introductionCompleted = true },
                                     onHistory: historyViewModel == nil ? nil : { showsHistory = true })
            } else {
                plans
            }
        }
        .sheet(isPresented: $showsHistory) {
            if let historyViewModel {
                HistoryView(viewModel: historyViewModel, isReadOnly: true)
            }
        }
        .task { await storeManager.prepareForPurchases() }
        .onChange(of: usageTracker.hasUnlocked) { _, unlocked in
            if unlocked {
                introductionCompleted = true
                if !isAccessGate { dismiss() }
            }
        }
    }

    private var plans: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        ThoughtfulNoteIllustration(compact: true)
                            .frame(maxWidth: .infinity)
                        Text(usageTracker.hasUnlocked ? String(localized: "A little more room.") : String(localized: "A home for\nevery thought."))
                            .font(Thoughtful.title)
                            .foregroundStyle(Thoughtful.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Unlimited Capture. Private, on-device transcription. Your words, in your own Markdown files.")
                            .font(Geist.body(.callout))
                            .foregroundStyle(Thoughtful.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if usageTracker.hasFamilyAccess {
                        Label("Family Unlimited Is Unlocked", systemImage: "person.3.fill")
                            .font(Geist.body())
                    } else {
                        if !usageTracker.isEligibleForFamilyUpgrade {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Access", selection: $family) {
                                    Text("Individual").tag(false)
                                    Text("Family").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("paywall.access")
                                .disabled(storeManager.isPurchasing || storeManager.isRestoring)
                                Text(family ? String(localized: "For your Apple Family Sharing group. Each person keeps their own notes.") : String(localized: "For you, across your Apple devices."))
                                    .font(Geist.caption())
                                    .foregroundStyle(Thoughtful.secondary)
                            }
                        }
                        if !storeManager.isEntitlementStateReady {
                            ProgressView("Checking Purchases…")
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(offers.enumerated()), id: \.element.rawValue) { index, product in
                                    planRow(product, index: index)
                                    if index < offers.count - 1 {
                                        Divider().padding(.horizontal, 16)
                                    }
                                }
                            }
                            .background(Thoughtful.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Thoughtful.rule, lineWidth: 1)
                            }
                        }
                    }

                    if let error = storeManager.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.error)
                            Button("Retry Loading Purchases") {
                                Task { await storeManager.prepareForPurchases() }
                            }
                            .disabled(storeManager.isPurchasing || storeManager.isRestoring)
                        }
                    }
                    Text("Subscriptions renew automatically unless canceled at least 24 hours before the period ends. Manage or cancel in Apple Account settings. Lifetime is a one-time purchase with no trial. Deleting the app or buying Lifetime does not cancel an existing subscription.")
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Thoughtful.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Manage Subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        .font(Geist.caption())
                    if isAccessGate && historyViewModel != nil {
                        Button {
                            showsHistory = true
                        } label: {
                            Label("View and export existing history", systemImage: "clock")
                                .font(Geist.caption())
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("paywall.historyLink")
                    }
                }
                .padding(24)
                .frame(maxWidth: 488)
                .frame(maxWidth: .infinity)
            }
            .background(Thoughtful.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !usageTracker.hasFamilyAccess { purchaseFooter }
            }
            .navigationTitle("Vox.md")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isAccessGate && historyViewModel != nil {
                        Button("History", systemImage: "clock") { showsHistory = true }
                            .accessibilityIdentifier("paywall.existingHistory")
                    } else if !isAccessGate {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(storeManager.isRestoring ? "Restoring…" : "Restore") {
                        Task { await storeManager.restorePurchases() }
                    }
                    .disabled(storeManager.isRestoring || storeManager.isPurchasing)
                    .accessibilityLabel("Restore Purchases")
                }
            }
        }
        .tint(Thoughtful.ink)
    }

    private func planRow(_ product: VoxboardPurchaseProduct, index: Int) -> some View {
        let selected = product == selectedProduct
        return Button {
            selectedPlanIndex = index
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Thoughtful.ink : Thoughtful.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: product)).font(Geist.label(.body))
                    Text(product.isSubscription ? product.billingLabel : String(localized: "One-time purchase. No trial."))
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Thoughtful.secondary)
                }
                Spacer(minLength: 8)
                Text(storeManager.displayPrice(for: product) ?? String(localized: "Unavailable"))
                    .font(Geist.label(.body))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Thoughtful.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(storeManager.isPurchasing || storeManager.isRestoring)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("paywall.plan.\(product.rawValue)")
    }

    private var purchaseFooter: some View {
        let product = selectedProduct
        let trial = storeManager.offersFreeTrial(product)
        let price = storeManager.displayPrice(for: product)
        return VStack(spacing: 8) {
            if let price {
                Text(trial ? String(localized: "7 days free, then \(price) \(product.billingLabel). Auto-renews.")
                     : product.isSubscription ? String(localized: "\(price) \(product.billingLabel). Auto-renews until canceled.")
                     : String(localized: "\(price), once. No subscription."))
                    .font(Geist.caption())
                    .foregroundStyle(Thoughtful.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.billingSummary")
            }
            Button {
                Task { await storeManager.purchase(product, context: context) }
            } label: {
                HStack {
                    if storeManager.isPurchasing { ProgressView().tint(Thoughtful.background) }
                    Text(storeManager.isPurchasing ? String(localized: "Purchasing…")
                         : trial ? String(localized: "Start 7-Day Free Trial")
                         : product.isSubscription ? String(localized: "Subscribe") : String(localized: "Buy Lifetime"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GeistButtonStyle(variant: .primary))
            .disabled(storeManager.isPurchasing || storeManager.isRestoring || storeManager.product(for: product) == nil)
            .accessibilityIdentifier("paywall.purchase")
            HStack(spacing: 24) {
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    Text("Terms of Use").frame(minHeight: 44)
                }
                Link(destination: URL(string: "https://vox.isolated.tech/privacy.html")!) {
                    Text("Privacy Policy").frame(minHeight: 44)
                }
            }
            .font(Geist.caption(.caption))
        }
        .frame(maxWidth: 440)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Thoughtful.background)
        .overlay(alignment: .top) { Divider() }
    }

    private func title(for product: VoxboardPurchaseProduct) -> String {
        switch product {
        case .individualWeekly, .familyWeekly: String(localized: "Weekly")
        case .individualYearly, .familyYearly: String(localized: "Yearly")
        case .familyUpgrade: String(localized: "Upgrade to Family Lifetime")
        default: String(localized: "Lifetime")
        }
    }
}
