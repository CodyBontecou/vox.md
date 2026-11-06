import StoreKit
import SwiftUI
import VoxboardShared
import WidgetKit

// MARK: - MetaSettingsView

/// App-level customization, preferences, upgrade, about metadata, and debug tools.
struct MetaSettingsView: View {
    let persistentRecorder: PersistentRecorder
    let captureToolbarPreferences: CaptureToolbarPreferences

    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @Environment(ModelManager.self) private var modelManager
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showPaywall = false
    @State private var showDebugLog = false
#if os(iOS)
    @State private var showMailCompose = false
#endif
    @State private var hapticsEnabled: Bool = AppConstants.hapticsEnabled
    @State private var liveActivityMonitorEnabled: Bool = AppConstants.liveActivityMonitorEnabled
    @State private var shortcutRecordingLiveActivityEnabled: Bool = AppConstants.shortcutRecordingLiveActivityEnabled
    @State private var lockScreenQuickRecordEnabled: Bool = AppConstants.lockScreenQuickRecordEnabled
    @State private var vault: VoxVault?
    @State private var isPickingVault = false
    @State private var vaultMessage: String?
    @State private var routeFlows: [CapturePreset] = []
    @State private var surfaceRevision = 0
    @State private var showsWatchSetup = false
    private let watchSetupHandoff = WatchSetupHandoffRouter.shared

    var body: some View {
        ZStack {
            Geist.bg.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsSignalPageHeader(title: "Settings", backLabel: "Back to capture")
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        vaultSection
                        transcriptionSection
                        everywhereSection
                        accountSection
                            .id("settings-about")
                        activitySection
                        recordingQueueSection
                        customizationSection
                        keyboardSection
                            .id("settings-keyboard")
                        lockScreenSection
                        debugSection
                        privacyFooter
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                #if DEBUG
                .task {
                    await Task.yield()
                    switch RootDestination.localizationScreenshotStory {
                    case "06-privacy-local": proxy.scrollTo("settings-about", anchor: .center)
                    case "07-keyboard": proxy.scrollTo("settings-keyboard", anchor: .center)
                    case "09-app-language-row": proxy.scrollTo("settings-app-language", anchor: .center)
                    default: break
                    }
                }
                #endif
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // The Settings board has no bar: the page header carries the circular
        // Back button and the large title.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showsWatchSetup) {
            RouteSurfacePinsView(surface: .watch)
        }
        .onAppear(perform: consumeWatchSetupHandoff)
        .onChange(of: watchSetupHandoff.isPending) { _, _ in consumeWatchSetupHandoff() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .settings)
                .environment(usageTracker)
                .environment(storeManager)
        }
        .sheet(isPresented: $showDebugLog) {
            SettingsDebugLogView()
        }
        // Settings can be opened before StoreKit finishes its launch sync.
        // Refresh here so existing owners always get the Family upgrade offer.
        .task { await storeManager.prepareForPurchases() }
        .task { vault = await VoxVaultStore.current() }
        .onAppear {
            routeFlows = CapturePresetStore.loadFlows().filter(\.isEnabled)
            surfaceRevision &+= 1
        }
#if os(iOS)
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
        }
#endif
    }

    // MARK: - Group scaffolding

    /// Mono uppercase label above a white, bordered Signal card.
    private func settingsGroup<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeistSectionLabel(number: "", title: title)
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content()
            }
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var rowDivider: some View {
        GeistDivider().padding(.horizontal, 14)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Geist.faint)
            .accessibilityHidden(true)
    }

    private var privacyFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Geist.muted)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text("Audio and transcripts stay on your devices and in your vault. No custom analytics.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Vault

    private var vaultSection: some View {
        settingsGroup("Vault") {
            VaultPickerCard(vault: vault, isPicking: $isPickingVault, embedded: true) { picked in
                Task { @MainActor in
                    do {
                        let moved = try await VoxVaultStore.change(to: picked)
                        vault = picked
                        vaultMessage = moved > 0
                            ? String(localized: "\(moved) routes now write to \(picked.name).")
                            : nil
                    } catch {
                        vaultMessage = error.localizedDescription
                    }
                }
            }
            if let vaultMessage {
                Text(vaultMessage)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            rowDivider
            summaryRow(
                String(localized: "Routes"),
                subtitle: routesSummary,
                value: "\(routeFlows.count)",
                identifier: "settings_routes"
            ) {
                CapturePresetSettingsView()
            }
        }
    }

    private var routesSummary: String {
        let defaultID = CapturePresetProfileStore.selectedProfileID(defaults: AppConstants.sharedDefaults)
        let ordered = routeFlows.filter { $0.id == defaultID } + routeFlows.filter { $0.id != defaultID }
        let names = ordered.map { flow in
            flow.id == defaultID
                ? String(localized: "\(flow.displayName) (default)")
                : flow.displayName
        }
        return names.isEmpty ? String(localized: "No routes yet") : names.joined(separator: " · ")
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        settingsGroup("Transcription") {
            summaryRow(String(localized: "Model"), subtitle: modelSummary, identifier: "settings_model") {
                ModelTabView()
            }
            rowDivider
            summaryRow(String(localized: "Language"), subtitle: languageSummary, identifier: "settings_language") {
                TranscriptionLanguageSettingsView()
            }
        }
    }

    private var modelSummary: String {
        if modelManager.isAutomaticSelection {
            if let id = modelManager.preferredFallbackModelID,
               let fallback = modelManager.downloadedModels.first(where: { $0.id == id }) {
                return String(localized: "Automatic · Apple Speech, falls back to \(fallback.name)")
            }
            return String(localized: "Automatic · Apple Speech")
        }
        return modelManager.selectedModel?.name ?? String(localized: "Automatic")
    }

    /// "English (US) · detect others": the language transcription uses, and
    /// whether other languages are detected.
    private var languageSummary: String {
        if modelManager.selectedModel?.engine.isParakeet == true {
            return String(localized: "Detected automatically")
        }
        let code = modelManager.selectedLanguage
        guard code == "auto" else { return languageName(code: code) }
        guard modelManager.isAutomaticSelection else {
            // Whisper's Auto Detect.
            return String(localized: "Detected automatically")
        }
        // Automatic follows the device language with Apple Speech; a
        // downloaded multilingual fallback (Whisper, Parakeet v3) detects the
        // language for recordings Apple Speech cannot handle.
        let device = deviceLanguageName
        return automaticFallbackDetectsLanguage
            ? String(localized: "\(device) · detect others")
            : device
    }

    private var automaticFallbackDetectsLanguage: Bool {
        guard let id = modelManager.preferredFallbackModelID,
              let fallback = modelManager.downloadedModels.first(where: { $0.id == id }) else { return false }
        return fallback.engine != .parakeetV2
    }

    /// "English (US)" from the device locale.
    private var deviceLanguageName: String {
        let locale = Locale.current
        guard let languageCode = locale.language.languageCode?.identifier else {
            return String(localized: "System Language")
        }
        let name = locale.localizedString(forLanguageCode: languageCode)?.localizedCapitalized ?? languageCode
        guard let region = locale.region?.identifier else { return name }
        return "\(name) (\(region))"
    }

    private func languageName(code: String) -> String {
        if let name = Locale.current.localizedString(forLanguageCode: code), !name.isEmpty {
            return name.localizedCapitalized
        }
        return modelManager.availableLanguages.first { $0.code == code }?.name ?? code
    }

    /// Watch "Open on iPhone" Handoff (see `WatchSetupHandoffRouter`).
    private func consumeWatchSetupHandoff() {
        guard watchSetupHandoff.isPending else { return }
        watchSetupHandoff.isPending = false
        showsWatchSetup = true
    }

    // MARK: - Everywhere

    private var everywhereSection: some View {
        let _ = surfaceRevision
        return settingsGroup("Everywhere") {
            summaryRow(String(localized: "Keyboard"), subtitle: keyboardSummary, identifier: "settings_keyboard_routes") {
                RouteSurfacePinsView(surface: .keyboard)
            }
            rowDivider
            summaryRow(String(localized: "Apple Watch"), subtitle: surfaceNames(.watch), identifier: "settings_watch_routes") {
                RouteSurfacePinsView(surface: .watch)
            }
            rowDivider
            summaryRow(String(localized: "Shortcuts & Control Center"), subtitle: actionButtonSummary, identifier: "settings_shortcuts") {
                ShortcutsControlCenterSettingsView()
            }
        }
    }

    private var keyboardSummary: String {
        let count = RouteSurfacePins.pinnedFlows(.keyboard).count
        let pinned = String(localized: "\(count) routes pinned")
        switch CapturePresetSurfacePinStore.keyboardHasFullAccess(defaults: AppConstants.sharedDefaults) {
        case true?: return String(localized: "Full access on · \(pinned)")
        case false?: return String(localized: "Full access off · \(pinned)")
        case nil: return pinned
        }
    }

    private func surfaceNames(_ surface: CapturePresetPinSurface) -> String {
        let names = RouteSurfacePins.pinnedFlows(surface).map(\.displayName)
        return names.isEmpty ? String(localized: "No routes pinned") : names.joined(separator: " · ")
    }

    private var actionButtonSummary: String {
        let id = CapturePresetSurfacePinStore.actionButtonRouteID(defaults: AppConstants.sharedDefaults)
        let name = id.flatMap { id in routeFlows.first { $0.id == id }?.displayName }
            ?? String(localized: "Default route")
        return String(localized: "Action button → \(name)")
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        if usageTracker.hasUnlocked {
            settingsGroup("Account") {
                if isSubscriptionPlan {
                    // "Vox.md Yearly · Renews … — Manage ›": the whole row
                    // opens the App Store subscription sheet.
                    Button { manageSubscription() } label: {
                        planRowLabel(value: String(localized: "Manage"), showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.manageSubscription")
                } else if usageTracker.isEligibleForFamilyUpgrade {
                    Button { showPaywall = true } label: {
                        planRowLabel(value: String(localized: "Upgrade"), showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.familyUpgradeButton")
                } else {
                    planRowLabel(value: nil, showsChevron: false)
                        .accessibilityElement(children: .combine)
                }
                rowDivider
                helpRow
            }
        } else {
            upgradeSection
            settingsGroup("Account") {
                helpRow
            }
        }
    }

    private func planRowLabel(value: String?, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(planTitle)
                    .font(Geist.label(.body))
                    .foregroundColor(Geist.text)
                Text(planDetail)
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .foregroundColor(Geist.muted)
                    .lineLimit(subtitleLineLimit)
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(Geist.body(.callout))
                    .foregroundColor(Geist.muted)
            }
            if showsChevron { chevron }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    /// Board subtitles stay on one line; accessibility sizes wrap instead.
    private var subtitleLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 1
    }

    /// "Help & feedback · Version 2.14 (58)": Discord, feedback and the
    /// About details, on one page.
    private var helpRow: some View {
        summaryRow(
            String(localized: "Help & feedback"),
            subtitle: String(localized: "Version \(appVersionString)"),
            identifier: "settings_help"
        ) {
            helpPage
        }
    }

    private var helpPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SettingsSignalPageHeader(title: "Help & feedback")
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                feedbackSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Geist.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Geist.bg, for: .navigationBar)
    }

    private var entitlementProducts: [VoxboardPurchaseProduct] { storeManager.currentEntitlementProducts }

    private var isSubscriptionPlan: Bool {
        entitlementProducts.contains(where: \.isSubscription) || usageTracker.subscriptionExpirationDate != nil
    }

    private var planTitle: String {
        if entitlementProducts.contains(where: { $0 == .individualYearly || $0 == .familyYearly }) {
            return String(localized: "Vox.md Yearly")
        }
        if entitlementProducts.contains(where: { $0 == .individualWeekly || $0 == .familyWeekly }) {
            return String(localized: "Vox.md Weekly")
        }
        if isSubscriptionPlan { return String(localized: "Vox.md Subscription") }
        return String(localized: "Vox.md Lifetime")
    }

    private var planDetail: String {
        let family = usageTracker.hasFamilyAccess
            ? String(localized: "Family Sharing on")
            : String(localized: "Family Sharing off")
        if let renewal = usageTracker.subscriptionExpirationDate, isSubscriptionPlan {
            let date = renewal.formatted(.iso8601.year().month().day())
            return String(localized: "Renews \(date) · \(family)")
        }
        return String(localized: "One-time purchase · \(family)")
    }

    private func manageSubscription() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        Task { @MainActor in
            if let scene {
                do {
                    try await AppStore.showManageSubscriptions(in: scene)
                    await storeManager.syncCurrentEntitlements()
                    return
                } catch {}
            }
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
        }
    }

    /// Title + muted mono subtitle row with an optional trailing value.
    private func summaryRow<Destination: View>(
        _ title: String,
        subtitle: String,
        value: String? = nil,
        identifier: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Geist.label(.body))
                        .foregroundColor(Geist.text)
                    Text(subtitle)
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundColor(Geist.muted)
                        .lineLimit(subtitleLineLimit)
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(Geist.body(.callout))
                        .foregroundColor(Geist.muted)
                }
                chevron
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Upgrade Section

    private var upgradeSection: some View {
        settingsGroup("Vox.md Unlimited") {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accessTitle)
                            .font(Geist.label(.body))
                            .foregroundColor(Geist.text)
                        Text(accessDetail)
                            .font(Geist.mono(size: 11, relativeTo: .caption))
                            .foregroundColor(Geist.muted)
                    }
                    Spacer()
                    if usageTracker.hasUnlocked {
                        SignalBadge(text: usageTracker.hasFamilyAccess ? "Family" : "Purchased")
                    } else if let price = storeManager.displayPrice {
                        Text("Lifetime \(price)")
                            .font(Geist.body(.callout))
                            .foregroundColor(Geist.muted)
                    } else {
                        Text("Checking price…")
                            .font(Geist.caption())
                            .foregroundColor(Geist.muted)
                    }
                }

                if !usageTracker.hasFamilyAccess {
                    Button(action: { showPaywall = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: usageTracker.hasUnlocked ? "person.3.fill" : "lock.open.fill")
                                .font(.system(.subheadline))
                            if usageTracker.isEligibleForFamilyUpgrade,
                               let price = storeManager.familyUpgradeDisplayPrice {
                                Text("Upgrade to Family — \(price)")
                            } else if usageTracker.isEligibleForFamilyUpgrade {
                                Text("Upgrade to Family")
                            } else {
                                Text("View Plans")
                            }
                        }
                    }
                    .accessibilityIdentifier(
                        usageTracker.accessLevel == .individual
                            ? "settings.familyUpgradeButton"
                            : "settings.lifetimeOptionsButton"
                    )
                    .buttonStyle(GeistButtonStyle(variant: .primary, size: .medium))
                }
            }
            .padding(14)
        }
    }

    private var accessTitle: LocalizedStringKey {
        switch usageTracker.accessLevel {
        case .free: "Unlock Unlimited"
        case .individual: "Individual Unlimited"
        case .family: "Family Unlimited"
        }
    }

    private var accessDetail: String {
        switch usageTracker.accessLevel {
        case .free:
            String(localized: "Choose a plan to begin capturing and recording")
        case .individual:
            String(localized: "Unlimited individual access")
        case .family:
            String(localized: "Unlimited access with Apple Family Sharing")
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        settingsGroup("Activity") {
            settingsNavigationRow(
                "Stats",
                description: "Recordings, recording time, and Capture activity",
                systemImage: "chart.bar.xaxis"
            ) {
                StatsView()
            }
        }
    }

    // MARK: - Recording Queue Section

    private var recordingQueueSection: some View {
        settingsGroup("Queues & Recovery") {
            settingsNavigationRow(
                "Open Activity",
                description: "Manage queued audio and choose processing and retention defaults",
                systemImage: "waveform"
            ) {
                RecordingQueueView(
                    queue: persistentRecorder.recordingQueue,
                    recoveryPresets: CapturePresetStore.loadFlows()
                ) { job, delivery in
                    await persistentRecorder.recordingQueue.retry(
                        job,
                        modelID: modelManager.selectedModelId,
                        fallbackModelID: modelManager.preferredFallbackModelID,
                        replaceFallbackModelID: true,
                        language: modelManager.selectedLanguage,
                        delivery: delivery
                    )
                }
            }
            rowDivider
            settingsNavigationRow(
                "URL Deliveries",
                description: "Review saved HTTP payloads, retry with corrected credentials, or discard",
                systemImage: "paperplane"
            ) {
                URLDeliveryRecoveryView(coordinator: URLDeliveryRuntime.coordinator)
            }
            .accessibilityIdentifier("settings_url_deliveries")
        }
    }

    // MARK: - Customization Section

    private var customizationSection: some View {
        settingsGroup("Customization") {
            settingsNavigationRow(
                "Capture Bar",
                description: "Choose, reorder, and hide quick actions",
                systemImage: "rectangle.3.group"
            ) {
                CaptureToolbarSettingsView(preferences: captureToolbarPreferences)
            }

            rowDivider

            appLanguageRow
                .id("settings-app-language")
        }
    }

    // MARK: - App Language Row

    private var appLanguageRow: some View {
        NavigationLink {
            AppLanguageSettingsView()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Language")
                        .font(Geist.label(.body))
                        .foregroundColor(Geist.text)
                    Text("Choose which language Vox.md uses")
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundColor(Geist.muted)
                }

                Spacer(minLength: 8)

                Text(currentLanguageLabel)
                    .font(Geist.body(.callout))
                    .foregroundColor(Geist.muted)

                chevron
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Trailing value on the App Language row: the override's native name,
    /// or the device language when following the system.
    private var currentLanguageLabel: String {
        let selection = AppLanguagePreference.current()
        guard selection == .system else { return selection.nativeDisplayName }
        if let preferred = Locale.preferredLanguages.first,
           let deviceLanguage = AppLanguage.matching(languageIdentifier: preferred) {
            return deviceLanguage.nativeDisplayName
        }
        return String(localized: "Use System Language")
    }

    private func settingsNavigationRow<Destination: View>(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Geist.label(.body))
                        .foregroundColor(Geist.text)
                    Text(description)
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundColor(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                chevron
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Geist.label(.body))
                    .foregroundColor(Geist.text)
                Text(description)
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Geist.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
    }

    private func actionRow(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Geist.label(.body))
                    .foregroundColor(Geist.text)
                Spacer()
                chevron
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Keyboard Section

    private var keyboardSection: some View {
        settingsGroup("Keyboard") {
            toggleRow(
                "Haptic Feedback",
                description: "Vibrate on key press. Requires Allow Full Access.",
                isOn: $hapticsEnabled
            )
            .onChange(of: hapticsEnabled) { _, val in
                AppConstants.sharedDefaults?.set(val, forKey: AppConstants.hapticsEnabledKey)
            }
        }
    }

    // MARK: - Lock Screen Section

    private var lockScreenSection: some View {
        settingsGroup("Lock Screen") {
            toggleRow(
                "Live Activity Monitor",
                description: "Show Vox.md status and Record/Stop controls on the Lock Screen and Dynamic Island while listening.",
                isOn: $liveActivityMonitorEnabled
            )
            .onChange(of: liveActivityMonitorEnabled) { _, val in
                AppConstants.sharedDefaults?.set(val, forKey: AppConstants.liveActivityMonitorEnabledKey)
                if val {
                    if persistentRecorder.isListening {
                        LiveActivityController.shared.startIfNeeded()
                    }
                } else {
                    LiveActivityController.shared.end()
                }
            }

            rowDivider

            toggleRow(
                "Shortcut Recording Live Activity",
                description: "Show a Live Activity for background shortcut and control recordings, including Apple Pencil squeeze and Action Button recordings. Required for background recording on iOS 26+ — when unavailable, starting a recording opens the app instead.",
                isOn: $shortcutRecordingLiveActivityEnabled
            )
            .onChange(of: shortcutRecordingLiveActivityEnabled) { _, val in
                AppConstants.sharedDefaults?.set(val, forKey: AppConstants.shortcutRecordingLiveActivityEnabledKey)
                if !val {
                    LiveActivityController.shared.endShortcutRecordingActivityIfNeeded()
                }
            }

            rowDivider

            toggleRow(
                "Lock Screen Record Button",
                description: "Allow recording from widgets, controls, and Shortcuts. Choose a Route and Action. Shortcuts uses Open When Run; the Vox.md Record control uses Open App. Background recording requires iOS 26+ and completed setup.",
                isOn: $lockScreenQuickRecordEnabled
            )
            .onChange(of: lockScreenQuickRecordEnabled) { _, val in
                AppConstants.sharedDefaults?.set(val, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
                WidgetCenter.shared.reloadTimelines(ofKind: "VoxboardRecordWidget")
                if #available(iOS 18.0, *) {
                    ControlCenter.shared.reloadControls(ofKind: "VoxboardRecordControl")
                }
                if #available(iOS 26.0, *) {
                    ControlCenter.shared.reloadControls(ofKind: VoxboardToggleRecordingControl.kind)
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutRows: [(String, String)] {
        var rows: [(String, String)] = [
            (String(localized: "Default transcription"), String(localized: "Apple Speech when available")),
            (String(localized: "Optional Whisper engine"), "whisper.cpp"),
            (String(localized: "Optional Parakeet engine"), "FluidAudio (CoreML)"),
            (String(localized: "Processing"), String(localized: "On-device")),
            (String(localized: "Privacy"), String(localized: "Voice/text stay local")),
            (String(localized: "Version"), appVersionString),
        ]
        if #available(iOS 26, *) {
            let status = FoundationModelsBackend.isAvailable
                ? String(localized: "Available")
                : String(localized: "Unavailable")
            rows.append((String(localized: "Apple Intelligence"), status))
        }
        return rows
    }

    private var aboutSection: some View {
        settingsGroup("About") {
            let rows = aboutRows
            ForEach(Array(rows.enumerated()), id: \.element.0) { index, row in
                if index > 0 { rowDivider }
                HStack(spacing: 12) {
                    Text(row.0)
                        .font(Geist.body(.callout))
                        .foregroundColor(Geist.text)
                    Spacer(minLength: 8)
                    Text(row.1)
                        .font(Geist.mono(size: 12, relativeTo: .caption))
                        .foregroundColor(Geist.muted)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 46)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        settingsGroup("Help & Feedback") {
            actionRow("Join Our Discord", action: openDiscord)
                .accessibilityLabel("Join our Discord")
                .accessibilityHint("Opens the Vox.md Discord community in your browser")

            rowDivider

            actionRow("Send Feedback", action: sendFeedback)
                .accessibilityLabel("Send Feedback")
                .accessibilityHint("Opens an email draft to contact support with app diagnostics")
        }
    }

    private func openDiscord() {
        guard let url = URL(string: "https://discord.gg/RaQYS4t6gn") else { return }
        openURL(url)
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        settingsGroup("Debug") {
            actionRow("View Debug Log") {
                showDebugLog = true
            }
        }
    }

    // MARK: - Helpers

    private func sendFeedback() {
        let payload = FeedbackHelper.makePayload()

#if os(iOS)
        if FeedbackHelper.canSendMail {
            showMailCompose = true
            return
        }
#endif

        guard let url = FeedbackHelper.mailtoURL(payload: payload) else { return }
        openURL(url)
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

// MARK: - Signal page header

/// Large 34pt Signal title with an optional muted subtitle. On a pushed page
/// (Settings over Capture, Models over Settings) it leads with the boards'
/// 44pt circular Back button, standing in for the hidden navigation bar.
struct SettingsSignalPageHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var backLabel: LocalizedStringKey? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let backLabel, isPresented {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(SignalCircleButtonStyle())
                    .accessibilityLabel(Text(backLabel))
                    .accessibilityIdentifier("signal.back")
                    .padding(.bottom, 14)
            }
            Text(title)
                .font(.custom("Geist-SemiBold", size: 34, relativeTo: .largeTitle))
                .tracking(-0.8)
                .foregroundStyle(Geist.text)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Geist.body(.callout))
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Debug Log Viewer

struct SettingsDebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Geist.Palette.background100.ignoresSafeArea()
                ScrollView {
                    Text(logText.isEmpty ? String(localized: "(empty)") : logText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(Geist.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Debug Log")
                        .font(Geist.heading(.headline))
                        .foregroundColor(Geist.text)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear Log") {
                        KeyboardDebugLog.shared.clear()
                        logText = String(localized: "(cleared)")
                    }
                    .font(Geist.label())
                    .foregroundColor(Geist.error)
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            logText = KeyboardDebugLog.shared.read()
                        } label: {
                            Text("↺")
                                .font(Geist.label(.title3))
                                .foregroundColor(Geist.muted)
                        }
                        .buttonStyle(.plain)
                        Button {
                            UIPasteboard.general.string = logText
                        } label: {
                            Text("Copy Log")
                                .font(Geist.label())
                                .foregroundColor(Geist.muted)
                        }
                        .buttonStyle(.plain)
                        Button("Done") { dismiss() }
                            .font(Geist.label())
                            .foregroundColor(Geist.muted)
                            .buttonStyle(.plain)
                    }
                }
            }
            .toolbarBackground(Geist.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { logText = KeyboardDebugLog.shared.read() }
    }
}
