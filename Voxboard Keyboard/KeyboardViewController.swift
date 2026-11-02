import UIKit
import KeyboardKit
import SwiftUI
import VoxboardShared

private let log = KeyboardDebugLog.shared

/// The keyboard extension's root controller.
/// Voice-first Signal pad by default; "ABC" switches to the KeyboardKit letter
/// keyboard (with the same quick actions above it) and back.
class KeyboardViewController: KeyboardInputViewController {

    private let voiceState = VoiceKeyboardState()

    override func viewDidLoad() {
        KeyboardSignal.registerFonts()
        super.viewDidLoad()
        log.log("viewDidLoad — keyboard extension loaded")

        // Give the voice state a way to open URLs via our responder chain.
        // Only used for the one-time "Open Vox.md to start listening" prompt.
        voiceState.urlOpener = { [weak self] url in
            self?.openAppURL(url)
        }

        // Give the voice state a way to insert text directly via textDocumentProxy
        voiceState.textInserter = { [weak self] text in
            guard let self else {
                log.log("❌ textInserter — self is nil")
                return
            }
            log.log("textInserter — inserting \(text.count) chars into textDocumentProxy")
            self.textDocumentProxy.insertText(text)
        }

        voiceState.textDeleter = { [weak self] count in
            guard let self, count > 0 else { return }
            for _ in 0..<count { self.textDocumentProxy.deleteBackward() }
        }

        voiceState.cursorMover = { [weak self] offset in
            self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        }

        voiceState.contextBeforeInput = { [weak self] in
            self?.textDocumentProxy.documentContextBeforeInput
        }
    }

    override func viewWillSetupKeyboardView() {
        super.viewWillSetupKeyboardView()
        log.log("viewWillSetupKeyboardView — hasFullAccess=\(hasFullAccess)")
        // Lets Settings show "Full access on" (the App Group is only writable with full access).
        CapturePresetSurfacePinStore.recordKeyboardFullAccess(hasFullAccess, defaults: AppConstants.sharedDefaults)

        applyHapticsSetting()

        let state = voiceState

        setupKeyboardView { controller in
            VoxboardKeyboardView(
                voiceState: state,
                controller: controller
            )
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        log.log("viewDidAppear")

        // Re-check listening state immediately — catches cases where the user
        // opened the app, started listening, and came back to the keyboard.
        voiceState.refreshListeningStatePublic()

        // Refresh model cache in case models were downloaded while keyboard was hidden
        voiceState.refreshModelCache()
        // Routes and their pinned quick actions may have changed in the app.
        voiceState.refreshFlowCache()

        // Try to insert any pending text recovered from a previous session
        voiceState.tryInsertPendingText()

        // If we were transcribing when the extension was suspended, the poll timer
        // is dead and any Darwin notification may have been missed. Check now.
        voiceState.resumeAfterSuspension()

        // Re-read in case the user toggled it in the main app while the keyboard was hidden.
        applyHapticsSetting()
    }

    private func applyHapticsSetting() {
        state.feedbackContext.settings.isHapticFeedbackEnabled = AppConstants.hapticsEnabled
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        log.log("viewDidDisappear")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        log.log("⚠️⚠️⚠️ didReceiveMemoryWarning")
        voiceState.handleMemoryWarning()
    }

    // MARK: - Open URL via Responder Chain

    /// Open the containing Vox.md app.
    /// Used only for the one-time "open app to start listening" prompt.
    private func openAppURL(_ url: URL) {
        log.log("openAppURL — opening: \(url.absoluteString)")

        if let extensionContext {
            extensionContext.open(url) { [weak self] success in
                DispatchQueue.main.async {
                    log.log("openAppURL — extensionContext completion: success=\(success)")
                    if !success {
                        self?.openAppURLViaResponderChain(url)
                    }
                }
            }
            return
        }

        openAppURLViaResponderChain(url)
    }

    /// Fallback for iOS builds/keyboard contexts where NSExtensionContext refuses
    /// to open custom URLs. This keeps the existing responder-chain behavior, but
    /// only after the supported API has had the first chance.
    private func openAppURLViaResponderChain(_ url: URL) {
        log.log("openAppURL — walking responder chain for: \(url.absoluteString)")

        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self

        while let current = responder {
            if current.responds(to: selector) {
                log.log("openAppURL — found responder: \(type(of: current))")

                let imp = current.method(for: selector)
                typealias OpenURLFunc = @convention(c) (
                    AnyObject, Selector, URL, Any?, ((Bool) -> Void)?
                ) -> Void
                let openURL = unsafeBitCast(imp, to: OpenURLFunc.self)
                openURL(current, selector, url, nil) { success in
                    DispatchQueue.main.async {
                        log.log("openAppURL — responder completion: success=\(success)")
                    }
                }
                return
            }
            responder = current.next
        }

        log.log("openAppURL — modern selector not found, trying legacy openURL:")

        // Fallback: legacy openURL: (works on some iOS versions where the modern
        // openURL:options:completionHandler: isn't reachable via the responder chain)
        let legacySelector = NSSelectorFromString("openURL:")
        responder = self
        while let current = responder {
            if current.responds(to: legacySelector) {
                log.log("openAppURL — found legacy responder: \(type(of: current))")
                current.perform(legacySelector, with: url)
                return
            }
            responder = current.next
        }

        log.log("❌ openAppURL — no responder found in chain (tried both selectors)")
    }
}

/// Voice pad (default) or the KeyboardKit letter keyboard, on the Signal
/// #121212 ground in every host appearance.
private struct VoxboardKeyboardView: View {
    @State var voiceState: VoiceKeyboardState
    let controller: KeyboardInputViewController

    @State private var showsLetters = false

    var body: some View {
        Group {
            if showsLetters {
                VStack(spacing: 0) {
                    LetterModeBar(voiceState: voiceState) { showsLetters = false }

                    KeyboardView(
                        services: controller.services,
                        buttonContent: { $0.view },
                        buttonView: { $0.view },
                        collapsedView: { $0.view },
                        emojiKeyboard: { $0.view },
                        toolbar: { _ in EmptyView() }
                    )
                    .keyboardCalloutActions { params in
                        let lang = AppConstants.sharedDefaults?
                            .string(forKey: AppConstants.selectedLanguageKey) ?? "auto"
                        return CalloutActionsProvider.actions(
                            for: params.action,
                            languageCode: lang
                        ) ?? params.standardActions()
                    }
                }
            } else {
                VoicePadView(
                    voiceState: voiceState,
                    hasFullAccess: controller.hasFullAccess,
                    text: KeyboardTextActions(insert: { [weak controller] text in
                        controller?.textDocumentProxy.insertText(text)
                    }),
                    showLetters: { showsLetters = true }
                )
            }
        }
        // KeyboardKit's standard background is translucent; the Signal
        // keyboard is an opaque dark ground regardless of the host.
        .background(KeyboardSignal.ground)
        .keyboardViewStyle(
            KeyboardViewStyle(background: .color(KeyboardSignal.ground))
        )
        .environment(\.colorScheme, .dark)
    }
}
