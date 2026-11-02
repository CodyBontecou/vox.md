import SwiftUI
import WatchKit

// MARK: - Watch design system

/// The watchOS translation of the iOS "Signal" theme: true-black ground,
/// #1C1C1E cards, indigo accent, recording red, Geist + Geist Mono type.
/// Geist is bundled in the Watch app (UIAppFonts); `Font.custom` falls back
/// to the system face if a font ever fails to register.
enum WatchGeist {
    enum Spacing {
        static let one: CGFloat = 4
        static let two: CGFloat = 8
        static let three: CGFloat = 12
        static let four: CGFloat = 16
    }

    enum Radius {
        static let small: CGFloat = 14
        static let medium: CGFloat = 16
        static let full: CGFloat = 9_999
    }

    static let background = Color.black                                                  // #000000
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)            // #1C1C1E
    static let surfacePressed = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)     // #3A3A3C
    static let border = Color.white.opacity(0.06)
    static let text = Color(red: 244 / 255, green: 244 / 255, blue: 241 / 255)            // #F4F4F1
    static let muted = Color(red: 154 / 255, green: 154 / 255, blue: 149 / 255)           // #9A9A95
    static let faint = Color(red: 110 / 255, green: 110 / 255, blue: 106 / 255)           // #6E6E6A
    static let idleBar = Color(red: 72 / 255, green: 72 / 255, blue: 74 / 255)            // #48484A
    /// Indigo tint for text/glyphs on black (#8A8FFF).
    static let accent = Color(red: 138 / 255, green: 143 / 255, blue: 255 / 255)
    /// Indigo fill for primary controls and route tiles (#2F3BE8).
    static let accentFill = Color(red: 47 / 255, green: 59 / 255, blue: 232 / 255)
    static let red = Color(red: 240 / 255, green: 71 / 255, blue: 74 / 255)               // #F0474A
    static let green = Color(red: 76 / 255, green: 201 / 255, blue: 160 / 255)            // #4CC9A0
    static let greenBackground = Color(red: 15 / 255, green: 59 / 255, blue: 46 / 255)    // #0F3B2E

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func mono(_ size: CGFloat, medium: Bool = true) -> Font {
        .custom(medium ? "GeistMono-Medium" : "GeistMono-Regular", size: size, relativeTo: .title)
    }

    static func tileColors(_ style: WatchRouteTileStyle) -> (fill: Color, letter: Color) {
        switch style {
        case .accent: return (accentFill, .white)
        case .light: return (text, .black)
        case .graphite: return (surfacePressed, text)
        }
    }
}

private struct WatchCapsuleButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, destructive }

    let variant: Variant
    var height: CGFloat = 44
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WatchGeist.sans(15, .semibold))
            .foregroundStyle(variant == .secondary ? WatchGeist.text : .white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(background.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.55)
    }

    private var background: Color {
        switch variant {
        case .primary: WatchGeist.accentFill
        case .secondary: WatchGeist.surface
        case .destructive: WatchGeist.red
        }
    }
}

/// Lettered circle identifying a route, with its per-route Signal color.
struct WatchRouteTile: View {
    let route: WatchCapturePresetSummary
    var size: CGFloat = 28

    var body: some View {
        let colors = WatchGeist.tileColors(route.tileStyle)
        ZStack {
            Circle().fill(colors.fill)
            if route.initial.isEmpty {
                Image(systemName: route.symbolName)
                    .font(.system(size: size * 0.42, weight: .bold))
            } else {
                Text(route.initial)
                    .font(WatchGeist.sans(size * 0.43, .bold))
            }
        }
        .foregroundStyle(colors.letter)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Root

struct WatchRecorderView: View {
    @EnvironmentObject private var bridge: WatchPhoneBridge
    @EnvironmentObject private var localRecorder: WatchLocalRecorder
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            WatchGeist.background.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .task {
            #if DEBUG
            if localRecorder.configureLocalizationScreenshotIfNeeded() { return }
            #endif
            bridge.activate()
            #if DEBUG
            bridge.applyDemoRoutesIfRequested()
            if let url = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("\(WatchRecordingDeepLink.scheme)://") })
                .flatMap(URL.init(string:)) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await localRecorder.handleDeepLink(url, using: bridge)
            }
            #endif
            localRecorder.updateRouteContext(using: bridge)
            try? await Task.sleep(nanoseconds: 750_000_000)
            #if DEBUG
            if localRecorder.runDemoScriptIfNeeded(using: bridge) { return }
            #endif
            // Reconcile terminal iPhone state before scheduling any transfer so
            // a delivered/discarded recording cannot be retransmitted on launch.
            localRecorder.applyRemoteStatuses(bridge.snapshot.recordingStatuses, using: bridge)
            if localRecorder.hasUnuploadedRecordings {
                localRecorder.syncPending(using: bridge)
            }
        }
        .onChange(of: bridge.snapshot) { _, snapshot in
            localRecorder.applyRemoteStatuses(snapshot.recordingStatuses, using: bridge)
            localRecorder.updateRouteContext(using: bridge)
        }
        .onChange(of: bridge.isPhoneReachable) { _, isReachable in
            guard isReachable else { return }
            localRecorder.autoSyncIfNeeded(using: bridge)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            localRecorder.autoSyncIfNeeded(using: bridge)
        }
    }

    @ViewBuilder
    private var content: some View {
        if localRecorder.isRecording {
            WatchRecordingScreen()
        } else if let result = localRecorder.result {
            WatchResultScreen(result: result)
        } else if needsSetup {
            WatchSetupScreen()
        } else {
            WatchRouteListScreen()
        }
    }

    private var needsSetup: Bool {
        guard bridge.snapshot.availablePresets.isEmpty else { return false }
        if bridge.snapshot.hasPresetSelectionAvailabilityPayload { return true }
        // Never synced with iPhone, or iPhone app not installed yet.
        return !bridge.snapshot.hasPresetSummariesPayload || bridge.snapshot.phase == .unavailable
    }
}

// MARK: - WatchRoutes: "Speak to…"

private struct WatchRouteListScreen: View {
    @EnvironmentObject private var bridge: WatchPhoneBridge
    @EnvironmentObject private var localRecorder: WatchLocalRecorder
    @State private var startingRouteID: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Speak to…")
                    .font(WatchGeist.sans(13, .semibold))
                    .foregroundStyle(WatchGeist.accent)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)

                ForEach(bridge.snapshot.availablePresets) { route in
                    routeRow(route)
                }

                if bridge.snapshot.presetSummariesAreTruncated {
                    Text("More routes are in Vox.md on iPhone.")
                        .font(WatchGeist.sans(12))
                        .foregroundStyle(WatchGeist.muted)
                        .padding(.horizontal, 6)
                }

                WatchQueueStatusCard()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, WatchGeist.Spacing.three)
        }
        .scrollIndicators(.hidden)
    }

    private func routeRow(_ route: WatchCapturePresetSummary) -> some View {
        Button {
            guard startingRouteID == nil else { return }
            startingRouteID = route.id
            Task {
                await localRecorder.start(using: bridge, route: route)
                startingRouteID = nil
            }
        } label: {
            HStack(spacing: 10) {
                WatchRouteTile(route: route)
                if let name = route.visibleName {
                    Text(name)
                        .font(WatchGeist.sans(15, .semibold))
                        .foregroundStyle(WatchGeist.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                if startingRouteID == route.id {
                    ProgressView().controlSize(.small).tint(WatchGeist.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(WatchGeist.surface)
            .clipShape(RoundedRectangle(cornerRadius: WatchGeist.Radius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: WatchGeist.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(startingRouteID != nil)
        .accessibilityLabel(String(localized: "Speak to \(route.displayName)"))
        .accessibilityHint(String(localized: "Starts recording to this route."))
    }
}

/// Compact queue / pipeline status under the route list. Hidden when idle.
private struct WatchQueueStatusCard: View {
    @EnvironmentObject private var bridge: WatchPhoneBridge
    @EnvironmentObject private var localRecorder: WatchLocalRecorder

    var body: some View {
        if let status {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(WatchGeist.sans(14, .semibold))
                    .foregroundStyle(status.isError ? WatchGeist.red : WatchGeist.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let detail = status.detail {
                    Text(detail)
                        .font(WatchGeist.sans(12))
                        .foregroundStyle(WatchGeist.muted)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WatchGeist.surface)
            .clipShape(RoundedRectangle(cornerRadius: WatchGeist.Radius.small, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private struct Status {
        let title: String
        let detail: String?
        var isError = false
    }

    private var status: Status? {
        if case .error(let error) = localRecorder.phase {
            let detail = localRecorder.message.flatMap { $0 == error ? nil : $0 }
            return Status(title: error, detail: detail, isError: true)
        }
        let waiting = localRecorder.queuedRecordings.filter { $0.transportState != .uploaded }
        if !waiting.isEmpty {
            let title = waiting.count == 1
                ? String(localized: "1 waiting for iPhone")
                : String(localized: "\(waiting.count) waiting for iPhone")
            let names = routeNames(for: waiting)
            let detail = names.isEmpty
                ? String(localized: "Saved on Watch")
                : names.joined(separator: " · ") + " · " + String(localized: "saved on Watch")
            return Status(title: title, detail: detail)
        }
        switch localRecorder.phase {
        case .locating:
            return Status(title: String(localized: "Adding Watch location"), detail: localRecorder.message)
        case .transcribing:
            return Status(title: String(localized: "Transcribing on iPhone"), detail: localRecorder.message)
        case .delivering:
            return Status(title: String(localized: "Saving on iPhone"), detail: localRecorder.message)
        case .waitingForPhone where localRecorder.queuedCount > 0:
            return Status(title: String(localized: "On iPhone"), detail: localRecorder.message)
        case .transferred:
            return Status(title: String(localized: "Delivered"), detail: nil)
        default:
            return nil
        }
    }

    private func routeNames(for items: [WatchLocalQueuedRecording]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            let name = bridge.snapshot.route(id: item.presetID)?.shownName ?? item.presetName
            guard let name, !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }
}

// MARK: - WatchRecord

private struct WatchRecordingScreen: View {
    @EnvironmentObject private var bridge: WatchPhoneBridge
    @EnvironmentObject private var localRecorder: WatchLocalRecorder
    @State private var isStopping = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: WatchGeist.Spacing.two) {
                primary
                    .containerRelativeFrame(.vertical) { length, _ in max(0, length - 6) }
                secondaryControls
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var primary: some View {
        VStack(spacing: WatchGeist.Spacing.two) {
            routeChip
            Text(formattedDuration(localRecorder.duration))
                .font(WatchGeist.mono(30))
                .monospacedDigit()
                .foregroundStyle(WatchGeist.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(String(localized: "Recording time \(formattedDuration(localRecorder.duration))"))
            WatchLevelWaveform(levels: localRecorder.levels, isPaused: localRecorder.isPaused)
                .frame(height: 26)
            Spacer(minLength: 0)
            Button {
                guard !isStopping else { return }
                isStopping = true
                Task {
                    await localRecorder.stopAndQueue(using: bridge)
                    isStopping = false
                }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white)
                        .frame(width: 12, height: 12)
                    Text("Stop")
                }
            }
            .buttonStyle(WatchCapsuleButtonStyle(variant: .destructive, height: 50))
            .disabled(isStopping)
            .accessibilityLabel(String(localized: "Stop and send to iPhone"))
        }
    }

    private var routeChip: some View {
        HStack(spacing: 6) {
            if let route = localRecorder.recordingRoute {
                WatchRouteTile(route: route, size: 16)
                Text(route.shownName)
            } else {
                Text(localRecorder.isPaused ? String(localized: "Paused") : String(localized: "Recording"))
            }
            if localRecorder.isPaused, localRecorder.recordingRoute != nil {
                Text("· Paused").foregroundStyle(WatchGeist.muted)
            }
        }
        .font(WatchGeist.sans(13, .semibold))
        .foregroundStyle(WatchGeist.text)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .combine)
    }

    /// Pause and Cancel stay reachable below the fold; Stop is the one
    /// prominent action, matching the Signal recording screen.
    private var secondaryControls: some View {
        VStack(spacing: WatchGeist.Spacing.two) {
            Button {
                localRecorder.togglePause()
            } label: {
                Label(
                    localRecorder.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                    systemImage: localRecorder.isPaused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(WatchCapsuleButtonStyle(variant: .secondary))
            .disabled(isStopping)

            Button(role: .destructive) {
                localRecorder.cancelRecording()
            } label: {
                Label(String(localized: "Cancel"), systemImage: "xmark")
            }
            .buttonStyle(WatchCapsuleButtonStyle(variant: .secondary))
            .disabled(isStopping)
            .accessibilityLabel(String(localized: "Cancel and delete Watch recording"))
        }
        .padding(.bottom, WatchGeist.Spacing.three)
    }
}

/// 26-bar level history; the most recent bars are recording red.
private struct WatchLevelWaveform: View {
    let levels: [Float]
    let isPaused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color(for: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4 + CGFloat(level) * 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.linear(duration: 0.1), value: levels)
        .accessibilityHidden(true)
    }

    private func color(for index: Int) -> Color {
        guard !isPaused else { return WatchGeist.idleBar }
        return index >= levels.count - 5 ? WatchGeist.red : WatchGeist.idleBar
    }
}

// MARK: - WatchStates

private struct WatchResultScreen: View {
    @EnvironmentObject private var bridge: WatchPhoneBridge
    @EnvironmentObject private var localRecorder: WatchLocalRecorder
    let result: WatchRecordingResult

    var body: some View {
        ScrollView(.vertical) {
            switch result.kind {
            case .handedOff: handedOff
            case .savedOnWatch: savedOnWatch
            }
        }
        .scrollIndicators(.hidden)
    }

    private var routeName: String {
        result.routeName ?? String(localized: "iPhone")
    }

    private var handedOff: some View {
        VStack(spacing: WatchGeist.Spacing.two) {
            ZStack {
                Circle().fill(WatchGeist.greenBackground)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(WatchGeist.green)
            }
            .frame(width: 52, height: 52)
            .padding(.top, 6)
            .accessibilityHidden(true)

            Text("Sent to \(routeName)")
                .font(WatchGeist.sans(17, .semibold))
                .foregroundStyle(WatchGeist.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text("\(formattedDuration(result.duration)) · iPhone is on it")
                .font(WatchGeist.sans(12.5))
                .foregroundStyle(WatchGeist.muted)
                .multilineTextAlignment(.center)

            Button {
                Task { await speakAgain() }
            } label: {
                Text("Speak again")
            }
            .buttonStyle(WatchCapsuleButtonStyle(variant: .primary))
            .padding(.top, 6)

            Button("Done") { localRecorder.dismissResult() }
                .buttonStyle(WatchCapsuleButtonStyle(variant: .secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .padding(.bottom, WatchGeist.Spacing.three)
    }

    private var savedOnWatch: some View {
        VStack(alignment: .leading, spacing: WatchGeist.Spacing.two) {
            Text(routeName)
                .font(WatchGeist.sans(13, .semibold))
                .foregroundStyle(WatchGeist.accent)
            Text("Saved on Watch")
                .font(WatchGeist.sans(18, .semibold))
                .foregroundStyle(WatchGeist.text)
            Text("iPhone isn’t nearby. It’ll transcribe and deliver when they reconnect.")
                .font(WatchGeist.sans(13))
                .foregroundStyle(WatchGeist.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button("Done") { localRecorder.dismissResult() }
                .buttonStyle(WatchCapsuleButtonStyle(variant: .secondary))
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, WatchGeist.Spacing.three)
    }

    private func speakAgain() async {
        let route = bridge.snapshot.route(id: result.routeID)
        localRecorder.dismissResult()
        await localRecorder.start(using: bridge, route: route)
    }
}

/// "Needs iPhone": no vault/routes have reached this Watch yet.
private struct WatchSetupScreen: View {
    @EnvironmentObject private var bridge: WatchPhoneBridge
    @EnvironmentObject private var localRecorder: WatchLocalRecorder
    @State private var didAskPhone = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: WatchGeist.Spacing.two) {
                Text("Finish setup on iPhone")
                    .font(WatchGeist.sans(18, .semibold))
                    .foregroundStyle(WatchGeist.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(WatchGeist.sans(13))
                    .foregroundStyle(WatchGeist.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    bridge.requestPhoneSetup()
                    didAskPhone = true
                    WKInterfaceDeviceHaptics.click()
                } label: {
                    Text(didAskPhone ? String(localized: "Check your iPhone") : String(localized: "Open on iPhone"))
                }
                .buttonStyle(WatchCapsuleButtonStyle(variant: .secondary))
                .padding(.top, 6)
                .accessibilityHint(String(localized: "Shows Vox.md setup on your iPhone."))

                if canRecordWithoutRoutes {
                    Button {
                        Task { await localRecorder.start(using: bridge) }
                    } label: {
                        Text("Record anyway")
                            .font(WatchGeist.sans(13, .medium))
                            .foregroundStyle(WatchGeist.accent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Records now and delivers to your iPhone default when it connects."))
                }

                if case .error(let error) = localRecorder.phase {
                    Text(error)
                        .font(WatchGeist.sans(12))
                        .foregroundStyle(WatchGeist.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, WatchGeist.Spacing.three)
        }
        .scrollIndicators(.hidden)
        .userActivity(WatchSetupHandoff.activityType) { activity in
            activity.title = String(localized: "Finish Vox.md setup")
            activity.isEligibleForHandoff = true
        }
        .task {
            // Ask once for fresh routes in case the iPhone was set up meanwhile.
            _ = await bridge.requestStatus()
        }
    }

    private var detail: String {
        if bridge.snapshot.message == "Install Vox.md on iPhone" {
            return String(localized: "Install Vox.md on your iPhone, pick a vault and routes, then they appear here.")
        }
        return String(localized: "Pick a vault and routes in Vox.md on your iPhone, then they appear here.")
    }

    /// Before the iPhone has ever reported routes, recording still works and
    /// delivers to the iPhone default once it connects.
    private var canRecordWithoutRoutes: Bool {
        !bridge.snapshot.hasPresetSelectionAvailabilityPayload
    }
}

private enum WKInterfaceDeviceHaptics {
    static func click() {
        WKInterfaceDevice.current().play(.click)
    }
}

private func formattedDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

#Preview {
    WatchRecorderView()
        .environmentObject(WatchPhoneBridge.shared)
        .environmentObject(WatchLocalRecorder())
}
