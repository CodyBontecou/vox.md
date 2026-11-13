import StoreKit
import SwiftUI
import VoxboardShared

/// Native first-run introduction and StoreKit-backed access gate.
/// The presentation changes; purchase/restore/eligibility remain StoreManager's.
///
/// The plans presentation is a three-page carousel (core benefit → how the
/// trial works → plans) over one pinned checkout footer, so the selected-plan
/// purchase is reachable from every page.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @AppStorage(Thoughtful.introductionKey) private var introductionCompleted = false
    @State private var family = false
    @State private var selectedPlanIndex = 0
    @State private var page = 0
    @State private var showsHistory = false
    /// Apple's in-app subscription management sheet. Unlike the web link, it shows the
    /// App Store Connect retention messages and retention offers when someone cancels.
    @State private var showsManageSubscriptions = false
    private let historyViewModel: QuickCaptureViewModel?
    private let includesOnboarding: Bool

    let context: PaywallContext
    let isAccessGate: Bool

    private static let pageCount = 3
    private static let plansPage = 2

    init(context: PaywallContext = .limit, isAccessGate: Bool = false,
         historyViewModel: QuickCaptureViewModel? = nil, initialFamily: Bool = false,
         includesOnboarding: Bool = false, initialPage: Int = 0) {
        self.context = context
        self.isAccessGate = isAccessGate
        self.historyViewModel = historyViewModel
        self.includesOnboarding = includesOnboarding
        _family = State(initialValue: initialFamily)
        _page = State(initialValue: min(max(initialPage, 0), Self.pageCount - 1))
    }

    private var offers: [VoxboardPurchaseProduct] {
        if usageTracker.isEligibleForFamilyUpgrade { return [.familyUpgrade] }
        // Yearly leads as the best-value plan, then Weekly, then Lifetime.
        return family ? [.familyYearly, .familyWeekly, .family] : [.individualYearly, .individualWeekly, .individual]
    }

    private var selectedProduct: VoxboardPurchaseProduct {
        offers[min(selectedPlanIndex, offers.count - 1)]
    }

    private var showsCheckout: Bool { !usageTracker.hasFamilyAccess }

    var body: some View {
        Group {
            if includesOnboarding && isAccessGate && !introductionCompleted && !usageTracker.hasUnlocked {
                ThoughtfulOnboarding(onFinish: { introductionCompleted = true },
                                     onHistory: historyViewModel == nil ? nil : { showsHistory = true })
            } else {
                plans
            }
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .onChange(of: showsManageSubscriptions) { _, isPresented in
            if !isPresented { Task { await storeManager.syncCurrentEntitlements() } }
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
            TabView(selection: $page) {
                carouselPage { benefitPage }.tag(0)
                carouselPage { trialPage }.tag(1)
                carouselPage { plansPage }.tag(Self.plansPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Geist.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
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
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Geist.muted)
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

    /// One scrollable carousel page. At accessibility sizes a huge fixed
    /// footer would obscure the content, so the full checkout moves into
    /// each page's readable, scrollable document instead.
    private func carouselPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
                if dynamicTypeSize.isAccessibilitySize && showsCheckout {
                    purchaseControls.padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 488)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Page 1: core benefit

    private var benefitPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(usageTracker.hasUnlocked ? String(localized: "A little more room.") : String(localized: "Speak it.\nIt lands in your vault."))
                .font(.custom("Geist-SemiBold", size: 32, relativeTo: .largeTitle))
                .tracking(-0.8)
                .foregroundStyle(Geist.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.title")
            if !dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the mono example wraps into a wall
                // of text; the benefit rows carry the same message.
                PaywallCaptureIllustration()
            }
            VStack(alignment: .leading, spacing: 10) {
                benefitRow(1, "Unlimited on-device transcription")
                benefitRow(2, "Keyboard, Watch, Mac and widgets")
                benefitRow(3, "Plain Markdown files you own")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unlimited on-device transcription. Keyboard, Watch, Mac and widgets. Plain Markdown files you own.")
        }
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

    // MARK: - Page 2: how the trial works

    /// The plan the trial timeline describes: the selected plan when it has
    /// an eligible free trial, else the audience's yearly plan.
    private var trialProduct: VoxboardPurchaseProduct? {
        if storeManager.offersFreeTrial(selectedProduct) { return selectedProduct }
        let yearly: VoxboardPurchaseProduct = family ? .familyYearly : .individualYearly
        return offers.contains(yearly) && storeManager.offersFreeTrial(yearly) ? yearly : nil
    }

    @ViewBuilder
    private var trialPage: some View {
        if let product = trialProduct, let price = storeManager.displayPrice(for: product) {
            trialTimeline(price: "\(price)\(priceSuffix(for: product))")
        } else {
            // Trial already used, or Lifetime-only offers: no timeline to tell.
            ownershipPage
        }
    }

    private func trialTimeline(price: String) -> some View {
        let now = Date()
        let calendar = Calendar.current
        let reminder = calendar.date(byAdding: .day, value: StoreManager.trialReminderDay, to: now) ?? now
        let trialEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                pageTitle(String(localized: "How your free\ntrial works"))
                Text("Use everything for 7 days. Cancel before \(trialEnd.formatted(day)) and you pay nothing.")
                    .font(Geist.body())
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                timelineStep(icon: "checkmark", isDone: true, showsRail: true,
                             eyebrow: String(localized: "Today"),
                             title: String(localized: "Everything unlocks"),
                             detail: String(localized: "Unlimited transcription and every route: keyboard, Watch, Mac, widgets."))
                timelineStep(icon: "bell", isDone: false, showsRail: true,
                             eyebrow: String(localized: "\(reminder.formatted(day)) · Day 5"),
                             title: String(localized: "We remind you"),
                             detail: String(localized: "A notification two days before your trial ends. No surprises."))
                timelineStep(icon: "calendar", isDone: false, showsRail: false,
                             eyebrow: String(localized: "\(trialEnd.formatted(day)) · Day 7"),
                             title: String(localized: "Trial ends"),
                             detail: String(localized: "Your plan starts at \(price). Cancel anytime in Settings."))
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 4)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            }
            privacyNote(String(localized: "No account to create. Audio never leaves your phone, and your notes stay plain Markdown even if you cancel."))
        }
    }

    private func timelineStep(icon: String, isDone: Bool, showsRail: Bool,
                              eyebrow: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isDone ? Geist.onAccent : Geist.text)
                    .frame(width: 32, height: 32)
                    .background {
                        if isDone {
                            Circle().fill(Geist.accent)
                        } else {
                            Circle().fill(Geist.card)
                            Circle().strokeBorder(Geist.borderHi, lineWidth: 1.5)
                        }
                    }
                if showsRail {
                    Rectangle()
                        .fill(isDone ? Geist.accent : Geist.border)
                        .frame(width: 2)
                        .frame(minHeight: 28, maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .textCase(.uppercase)
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .tracking(0.4)
                    .foregroundStyle(isDone ? Geist.accentText : Geist.muted)
                Text(title)
                    .font(.custom("Geist-SemiBold", size: 16, relativeTo: .body))
                    .foregroundStyle(Geist.text)
                Text(detail)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            .padding(.bottom, showsRail ? 22 : 16)
            .accessibilityElement(children: .combine)
        }
    }

    private var ownershipPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageTitle(String(localized: "Your words.\nYour own space."))
            VStack(alignment: .leading, spacing: 16) {
                ownershipRow("waveform", String(localized: "Transcribed on your device"),
                             String(localized: "Audio is never uploaded to Vox.md."))
                ownershipRow("folder", String(localized: "Markdown in folders you choose"),
                             String(localized: "Plain files that work with any editor."))
                ownershipRow("clock", String(localized: "Your history stays yours"),
                             String(localized: "Read, search and export existing notes without a purchase."))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            }
        }
    }

    private func ownershipRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Geist.accentText)
                .frame(width: 32, height: 32)
                .background(Geist.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Geist-SemiBold", size: 16, relativeTo: .body))
                    .foregroundStyle(Geist.text)
                Text(detail)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func privacyNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Geist.success)
                .accessibilityHidden(true)
            Text(text)
                .font(Geist.caption())
                .foregroundStyle(Geist.Palette.green1000)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Geist.Palette.green100, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
    }

    private func pageTitle(_ text: String) -> some View {
        Text(text)
            .font(.custom("Geist-SemiBold", size: 32, relativeTo: .largeTitle))
            .tracking(-0.8)
            .foregroundStyle(Geist.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Page 3: plans

    private var plansPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(usageTracker.isEligibleForFamilyUpgrade ? String(localized: "Upgrade to Family") : String(localized: "Unlock Vox.md"))
                .font(.custom("Geist-SemiBold", size: 28, relativeTo: .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(Geist.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

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
                VStack(alignment: .leading, spacing: 12) {
                    if !usageTracker.isEligibleForFamilyUpgrade {
                        accessSegments
                            .accessibilityHint(family ? String(localized: "For your Apple Family Sharing group. Each person keeps their own notes.") : String(localized: "For you, across your Apple devices."))
                    }
                    if !storeManager.isEntitlementStateReady {
                        if storeManager.errorMessage == nil {
                            ProgressView("Checking Purchases…")
                                .frame(maxWidth: .infinity, minHeight: 180)
                        }
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
            if usageTracker.hasFamilyAccess {
                // No purchase footer: keep Manage and the Library link reachable.
                Button("Manage Subscriptions") { showsManageSubscriptions = true }
                    .font(Geist.caption())
                    .foregroundStyle(Geist.accentText)
                historyLink
            }
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
                            if let savings = yearlySavingsPercent(for: product) {
                                SignalBadge(text: "Save \(savings)%")
                            } else {
                                SignalBadge(text: "Best value")
                            }
                        }
                    }
                    Text(planNote(for: product))
                        .font(Geist.caption(.caption))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Checkout footer

    private var footer: some View {
        VStack(spacing: 8) {
            PaywallPageIndicator(page: $page, count: Self.pageCount)
            if showsCheckout && !dynamicTypeSize.isAccessibilitySize {
                purchaseControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Geist.bg)
        .overlay(alignment: .top) { GeistDivider() }
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
                    if storeManager.isPurchasing { ProgressView().tint(Geist.onAccent) }
                    Text(storeManager.isPurchasing ? String(localized: "Purchasing…")
                         : trial ? String(localized: "Start 7-day free trial")
                         : product.isSubscription ? String(localized: "Subscribe")
                         : price.map { String(localized: "Unlock for \($0)") } ?? String(localized: "Buy Lifetime"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GeistButtonStyle(variant: .accent))
            .disabled(!storeManager.isEntitlementStateReady || storeManager.isPurchasing || storeManager.isRestoring || storeManager.product(for: product) == nil)
            .accessibilityIdentifier("paywall.purchase")
            Text(finePrint(for: product, trial: trial))
                .font(Geist.caption(.caption))
                .foregroundStyle(Geist.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.finePrint")
            HStack(spacing: 8) {
                if page == Self.plansPage {
                    // Plans page (pw_Slide3): "Manage · Terms · Privacy".
                    Button {
                        showsManageSubscriptions = true
                    } label: {
                        Text("Manage").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(Text("Manage Subscriptions"))
                    .accessibilityIdentifier("paywall.manage")
                    Text(verbatim: "·").accessibilityHidden(true)
                } else {
                    Button {
                        withAnimation { page = Self.plansPage }
                    } label: {
                        Text("See all plans")
                            .font(Geist.label(.caption))
                            .foregroundStyle(Geist.accentText)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("paywall.seeAllPlans")
                    Text(verbatim: "·").accessibilityHidden(true)
                }
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
            if historyViewModel != nil && isAccessGate && dynamicTypeSize.isAccessibilitySize {
                // The pinned footer leaves history to the toolbar's Library
                // button; in the scrolling checkout there is room for it.
                historyLink
            }
        }
        .frame(maxWidth: 440)
    }

    /// Short renewal note under the purchase button, per the Paywall board.
    /// The full renewal terms stay on the plans page.
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

    // MARK: - Pricing copy

    private func priceSuffix(for product: VoxboardPurchaseProduct) -> String {
        switch product {
        case .individualWeekly, .familyWeekly: String(localized: "/wk")
        case .individualYearly, .familyYearly: String(localized: "/yr")
        default: ""
        }
    }

    private func weeklyCounterpart(of yearly: VoxboardPurchaseProduct) -> VoxboardPurchaseProduct {
        yearly == .familyYearly ? .familyWeekly : .individualWeekly
    }

    /// Whole-percent saving of Yearly over 52 weeks of Weekly, from the
    /// storefront's own prices. Nil when either price is missing.
    private func yearlySavingsPercent(for yearly: VoxboardPurchaseProduct) -> Int? {
        guard let yearlyPrice = storeManager.product(for: yearly)?.price,
              let weeklyPrice = storeManager.product(for: weeklyCounterpart(of: yearly))?.price else { return nil }
        return PaywallPricing.savingsPercent(yearly: yearlyPrice, weekly: weeklyPrice)
    }

    /// "7 days free · $0.58/wk billed yearly" for Yearly; "7 days free, then
    /// $0.99/wk" for Weekly; renewal or one-time copy otherwise.
    private func planNote(for product: VoxboardPurchaseProduct) -> String {
        guard product.isSubscription else { return String(localized: "One purchase, no renewals") }
        guard let storeProduct = storeManager.product(for: product) else { return product.billingLabel }
        let price = storeProduct.displayPrice
        let trial = storeManager.offersFreeTrial(product)
        if product == .individualYearly || product == .familyYearly {
            let perWeek = (storeProduct.price / 52).formatted(storeProduct.priceFormatStyle)
            return trial
                ? String(localized: "7 days free · \(perWeek)/wk billed yearly")
                : String(localized: "\(perWeek)/wk billed yearly")
        }
        let suffix = priceSuffix(for: product)
        return trial
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

enum PaywallPricing {
    /// Whole-percent saving of a yearly price over 52 weekly payments,
    /// rounded down so the badge never overstates. Nil when there is no saving.
    static func savingsPercent(yearly: Decimal, weekly: Decimal) -> Int? {
        let annualWeekly = weekly * 52
        guard annualWeekly > 0, yearly > 0, yearly < annualWeekly else { return nil }
        var fraction = (1 - yearly / annualWeekly) * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &fraction, 0, .down)
        let percent = NSDecimalNumber(decimal: rounded).intValue
        return percent > 0 ? percent : nil
    }
}

/// Carousel page dots: tappable, and one adjustable element for VoiceOver.
private struct PaywallPageIndicator: View {
    @Binding var page: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    withAnimation { page = index }
                } label: {
                    Capsule()
                        .fill(index == page ? Geist.accent : Geist.borderHi)
                        .frame(width: index == page ? 18 : 6, height: 6)
                        .frame(height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page")
        .accessibilityValue(Text("\(page + 1) of \(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, count - 1)
            case .decrement: page = max(page - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("paywall.pageIndicator")
    }
}

/// Labeled example: a short voice capture becoming a Markdown note.
private struct PaywallCaptureIllustration: View {
    /// `[[Weekly review]]` on the soft indigo wash, as in the board.
    private static var wikiLink: AttributedString {
        var link = AttributedString("[[Weekly review]]")
        link.foregroundColor = Geist.accentText
        link.backgroundColor = Geist.accentSoft
        return link
    }

    private static let bars: [CGFloat] = [6, 10, 16, 9, 20, 24, 14, 8, 18, 22, 12, 6, 10, 19, 24, 15, 9, 13, 21, 17, 8, 11, 16, 7, 12, 9, 5, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(Geist.recording).frame(width: 10, height: 10)
                Text(verbatim: "0:12")
                    .font(Geist.mono(size: 13, relativeTo: .footnote))
                    .foregroundStyle(Geist.text)
                HStack(spacing: 3) {
                    ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, height in
                        Capsule()
                            .fill(index < 18 ? Geist.accent : Geist.borderHi)
                            .frame(width: 3, height: height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 24, alignment: .leading)
                .clipped()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("Transcribed on-device")
                    .textCase(.uppercase)
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .tracking(0.4)
            }
            .foregroundStyle(Geist.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Geist.Palette.gray100)
            .overlay(alignment: .top) { Rectangle().fill(Geist.border).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Geist.border).frame(height: 1) }
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Vault / Inbox / \(Date().formatted(.iso8601.year().month().day())).md")
                    .font(Geist.mono(size: 12, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "- [ ] Call Sam about the venue")
                    Text("- Draft for \(Text(Self.wikiLink))")
                }
                .font(Geist.mono(size: 13, relativeTo: .footnote))
                .foregroundStyle(Geist.text)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: a 12-second voice note, transcribed on your device into a Markdown file in your vault.")
    }
}
