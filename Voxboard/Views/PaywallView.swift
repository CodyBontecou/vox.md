import SwiftUI
import VoxboardShared

/// Native first-run introduction and StoreKit-backed access gate.
/// The presentation changes; purchase/restore/eligibility remain StoreManager's.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @AppStorage(Thoughtful.introductionKey) private var introductionCompleted = false
    @State private var family = false
    @State private var selectedPlanIndex = 0
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
        // Yearly leads as the best-value plan, then Weekly, then Lifetime.
        return family ? [.familyYearly, .familyWeekly, .family] : [.individualYearly, .individualWeekly, .individual]
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
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(usageTracker.hasUnlocked ? String(localized: "A little more room.") : String(localized: "Every capture,\nrouted into your vault."))
                            .font(.custom("Geist-SemiBold", size: 32, relativeTo: .largeTitle))
                            .tracking(-0.8)
                            .foregroundStyle(Geist.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("paywall.title")
                        VStack(alignment: .leading, spacing: 8) {
                            benefitRow(1, "Unlimited on-device transcription")
                            benefitRow(2, "Routes on keyboard, Watch, Mac and widgets")
                            benefitRow(3, "Plain Markdown files you own")
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Unlimited on-device transcription. Routes on keyboard, Watch, Mac and widgets. Plain Markdown files you own.")
                    }

                    if usageTracker.hasFamilyAccess {
                        Label("Family Unlimited Is Unlocked", systemImage: "person.3.fill")
                            .font(Geist.label(.body))
                            .foregroundStyle(Geist.text)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Geist.border, lineWidth: 1)
                            }
                    } else {
                        // Paywall board: segments sit 12pt above the plan
                        // rows, so all three plans clear the purchase footer.
                        VStack(alignment: .leading, spacing: 12) {
                            if !usageTracker.isEligibleForFamilyUpgrade {
                                accessSegments
                                    .accessibilityHint(family ? String(localized: "For your Apple Family Sharing group. Each person keeps their own notes.") : String(localized: "For you, across your Apple devices."))
                            }
                            if !storeManager.isEntitlementStateReady {
                                ProgressView("Checking Purchases…")
                                    .frame(maxWidth: .infinity, minHeight: 180)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(offers.enumerated()), id: \.element.rawValue) { index, product in
                                        planRow(product, index: index)
                                    }
                                }
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
                            .font(Geist.label())
                            .foregroundStyle(Geist.accentText)
                            .disabled(storeManager.isPurchasing || storeManager.isRestoring)
                        }
                    }
                    Text("Subscriptions renew automatically unless canceled at least 24 hours before the period ends. Manage or cancel in Apple Account settings. Lifetime is a one-time purchase with no trial. Deleting the app or buying Lifetime does not cancel an existing subscription.")
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Manage Subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        .font(Geist.caption())
                        .foregroundStyle(Geist.accentText)
                    if usageTracker.hasFamilyAccess {
                        // No purchase footer: keep the Library link reachable.
                        historyLink
                    }
                    if dynamicTypeSize.isAccessibilitySize && !usageTracker.hasFamilyAccess {
                        // A huge fixed footer would obscure the plan choices.
                        // At accessibility sizes, keep the full checkout in
                        // the same readable, scrollable document instead.
                        purchaseControls.padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 488)
                .frame(maxWidth: .infinity)
            }
            .background(Geist.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !usageTracker.hasFamilyAccess && !dynamicTypeSize.isAccessibilitySize { purchaseFooter }
            }
            .navigationTitle("Vox.md")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "VOX.MD")
                        .font(Geist.mono(size: 11, relativeTo: .caption, medium: true))
                        .tracking(0.88)
                        .foregroundStyle(Geist.muted)
                        .accessibilityLabel("Vox.md")
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if isAccessGate && historyViewModel != nil {
                        Button("Library", systemImage: "clock") { showsHistory = true }
                            .accessibilityIdentifier("paywall.existingHistory")
                    } else if !isAccessGate {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(storeManager.isRestoring ? "Restoring…" : "Restore") {
                        Task { await storeManager.restorePurchases() }
                    }
                    .font(Geist.label())
                    .disabled(storeManager.isRestoring || storeManager.isPurchasing)
                    .accessibilityLabel("Restore Purchases")
                    .accessibilityIdentifier("paywall.restore")
                }
            }
            .toolbarBackground(Geist.bg, for: .navigationBar)
        }
        .tint(Geist.text)
    }

    private func benefitRow(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(number)")
                .font(Geist.mono(size: 11, relativeTo: .caption))
                .foregroundStyle(Geist.accentText)
                .frame(width: 22, height: 22)
                .background(Geist.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(text)
                .font(.custom("Geist-Regular", size: 15, relativeTo: .body))
                .foregroundStyle(Geist.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Signal segmented control: a well track with a raised card thumb.
    private var accessSegments: some View {
        HStack(spacing: 4) {
            accessSegment(String(localized: "Just me"), isFamily: false)
            accessSegment(String(localized: "Family · up to 6"), isFamily: true)
        }
        .padding(4)
        .background(Geist.well, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Access")
        .accessibilityIdentifier("paywall.access")
        .disabled(storeManager.isPurchasing || storeManager.isRestoring)
    }

    private func accessSegment(_ title: String, isFamily: Bool) -> some View {
        let selected = family == isFamily
        return Button {
            family = isFamily
        } label: {
            Text(title)
                .font(Geist.label())
                .foregroundStyle(selected ? Geist.text : Geist.muted)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if selected {
                        Capsule()
                            .fill(Geist.card)
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func planRow(_ product: VoxboardPurchaseProduct, index: Int) -> some View {
        let selected = product == selectedProduct
        return Button {
            selectedPlanIndex = index
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(selected ? Geist.accent : Geist.Palette.gray600, lineWidth: selected ? 6 : 1.5)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title(for: product))
                            .font(.custom("Geist-SemiBold", size: 16, relativeTo: .body))
                            .foregroundStyle(Geist.text)
                        if product == .individualYearly || product == .familyYearly {
                            SignalBadge(text: "Best value")
                        }
                    }
                    Text(planNote(for: product))
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Geist.muted)
                }
                Spacer(minLength: 8)
                Text(storeManager.displayPrice(for: product) ?? String(localized: "Unavailable"))
                    .font(Geist.mono(size: 15, relativeTo: .body, medium: true))
                    .foregroundStyle(Geist.text)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Geist.accent : Geist.border, lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(storeManager.isPurchasing || storeManager.isRestoring)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("paywall.plan.\(product.rawValue)")
    }

    private var purchaseControls: some View {
        let product = selectedProduct
        let trial = storeManager.offersFreeTrial(product)
        let price = storeManager.displayPrice(for: product)
        return VStack(spacing: 8) {
            if let price {
                Text(trial ? String(localized: "7 days free, then \(price) \(product.billingLabel). Auto-renews.")
                     : product.isSubscription ? String(localized: "\(price) \(product.billingLabel). Auto-renews until canceled.")
                     : String(localized: "\(price), once. No subscription."))
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.billingSummary")
            }
            Button {
                Task { await storeManager.purchase(product, context: context) }
            } label: {
                HStack {
                    if storeManager.isPurchasing { ProgressView().tint(Geist.bg) }
                    Text(storeManager.isPurchasing ? String(localized: "Purchasing…")
                         : trial ? String(localized: "Start 7-day free trial")
                         : product.isSubscription ? String(localized: "Subscribe")
                         : price.map { String(localized: "Unlock for \($0)") } ?? String(localized: "Buy Lifetime"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GeistButtonStyle(variant: .primary))
            .disabled(storeManager.isPurchasing || storeManager.isRestoring || storeManager.product(for: product) == nil)
            .accessibilityIdentifier("paywall.purchase")
            Text(finePrint(for: product, trial: trial))
                .font(Geist.caption(.caption))
                .foregroundStyle(Geist.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.finePrint")
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    Text("Terms").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Terms of Use"))
                Text(verbatim: "·").accessibilityHidden(true)
                Link(destination: URL(string: "https://vox.isolated.tech/privacy.html")!) {
                    Text("Privacy").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Privacy Policy"))
            }
            .font(Geist.caption(.caption))
            .foregroundStyle(Geist.muted)
            historyLink
        }
        .frame(maxWidth: 440)
    }

    /// Short renewal note under the purchase button, per the Paywall board.
    /// The full renewal terms stay in the scrolling content above.
    private func finePrint(for product: VoxboardPurchaseProduct, trial: Bool) -> String {
        guard product.isSubscription else {
            return String(localized: "One-time purchase. Doesn’t cancel an existing subscription. Prices shown from the App Store.")
        }
        return trial
            ? String(localized: "Renews automatically unless cancelled 24 h before the trial ends. Manage in Settings. Prices shown from the App Store.")
            : String(localized: "Renews automatically unless cancelled 24 h before the period ends. Manage in Settings. Prices shown from the App Store.")
    }

    @ViewBuilder
    private var historyLink: some View {
        if isAccessGate && historyViewModel != nil {
            Button {
                showsHistory = true
            } label: {
                Text("Browse your existing notes")
                    .font(Geist.label(.callout))
                    .foregroundStyle(Geist.accentText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywall.historyLink")
        }
    }

    private var purchaseFooter: some View {
        purchaseControls
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Geist.bg)
        .overlay(alignment: .top) { GeistDivider() }
    }

    /// "7 days free, then $29.99/yr" for trial subscriptions; renewal or
    /// one-time copy otherwise.
    private func planNote(for product: VoxboardPurchaseProduct) -> String {
        guard product.isSubscription else { return String(localized: "One purchase, no renewals") }
        guard let price = storeManager.displayPrice(for: product) else { return product.billingLabel }
        let suffix: String = switch product {
        case .individualWeekly, .familyWeekly: String(localized: "/wk")
        default: String(localized: "/yr")
        }
        return storeManager.offersFreeTrial(product)
            ? String(localized: "7 days free, then \(price)\(suffix)")
            : String(localized: "\(price)\(suffix), renews automatically")
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
