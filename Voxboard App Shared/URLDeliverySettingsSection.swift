import SwiftUI
import VoxboardShared

/// The same opt-in editor on iOS and Mac. Only opaque account IDs and presence
/// flags cross the preset binding; token/header values stay in the Keychain.
struct URLDeliverySettingsSection: View {
    @Binding var settings: CapturePresetURLDeliverySettings
    @State private var urlDraft = ""
    @State private var tokenDraft = ""
    @State private var headersDraft = ""
    @State private var savedHeadersDraft = ""
    private enum ErrorArea { case endpoint, credentials, headers }
    @State private var errorArea = ErrorArea.credentials
    @State private var errorMessage: String?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>?
    #if os(macOS)
    @State private var showDeliveries = false
    #endif

    var body: some View {
        Section {
            Toggle("Deliver to URL", isOn: $settings.enabled)
                .accessibilityIdentifier("preset_url_delivery_enabled")
            if settings.enabled {
                Text("Endpoint").font(.subheadline)
                endpointField
                Toggle("Allow insecure local HTTP", isOn: $settings.allowingInsecureLocal)
                    .accessibilityIdentifier("preset_url_delivery_insecure_local")
                Text("HTTP sends your capture and credentials without encryption. Only enable this for a trusted local endpoint.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save URL", action: saveURL)
                    .accessibilityIdentifier("preset_url_delivery_save_url")
                inlineError(.endpoint)

                Text("Bearer Token (Optional)").font(.subheadline)
                tokenField
                Button("Save Token", action: saveToken)
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.requiresCredentialMigration)
                    .accessibilityIdentifier("preset_url_delivery_save_token")
                if settings.hasBearerToken {
                    Label("A bearer token is saved in the Keychain.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Remove Token", role: .destructive, action: removeToken)
                        .disabled(settings.requiresCredentialMigration)
                }
                if settings.credentialID != nil || settings.requiresCredentialMigration {
                    Button("Remove Saved Credentials", role: .destructive, action: removeCredentials)
                }

                inlineError(.credentials)

                Text("Custom Headers").font(.subheadline)
                headersField
                Button("Save Headers", action: saveHeaders)
                    .disabled(settings.requiresCredentialMigration)
                    .accessibilityIdentifier("preset_url_delivery_save_headers")
                Text("One per line: Name: Value. Values are saved only in the Keychain. Content-Type, Idempotency-Key, and bearer authorization are managed by Vox.md.")
                    .font(.caption).foregroundStyle(.secondary)

                inlineError(.headers)
                Button {
                    testTask = Task { await sendTest() }
                } label: {
                    if isTesting { HStack { ProgressView(); Text("Sending test…") } }
                    else { Text("Send Test") }
                }
                .disabled(isTesting || errorMessage != nil || settings.requiresCredentialMigration
                    || headersDraft != savedHeadersDraft || urlDraft != settings.urlString
                    || settings.urlString.isEmpty || !tokenDraft.isEmpty)
                .accessibilityIdentifier("preset_url_delivery_test")
                if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
            }
            #if os(iOS)
            NavigationLink("URL Deliveries") { URLDeliveryRecoveryView(coordinator: URLDeliveryRuntime.coordinator) }
                .accessibilityIdentifier("preset_url_deliveries")
            #else
            Button("URL Deliveries…") { showDeliveries = true }
                .accessibilityIdentifier("preset_url_deliveries")
            #endif
        } header: {
            Text("Deliver to URL")
        } footer: {
            Text("Adds a JSON POST to this preset’s existing destinations; it does not replace note delivery. Off by default. Draft recordings are not sent until you choose Send. Redirects are not followed. Failed deliveries are retained for HTTP-only retry or discard in URL Deliveries.")
        }
        .onAppear(perform: loadCredentials)
        .onDisappear {
            testTask?.cancel()
            tokenDraft = ""
            headersDraft = ""
            savedHeadersDraft = ""
        }
        #if os(macOS)
        .sheet(isPresented: $showDeliveries) {
            NavigationStack {
                URLDeliveryRecoveryView(coordinator: URLDeliveryRuntime.coordinator)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showDeliveries = false } } }
            }
            .frame(minWidth: 500, minHeight: 440)
        }
        #endif
    }

    @ViewBuilder
    private func inlineError(_ area: ErrorArea) -> some View {
        if errorArea == area, let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(.red)
                .accessibilityIdentifier("preset_url_delivery_error")
        }
    }

    private var endpointField: some View {
        TextField("https://example.com/ingest", text: $urlDraft)
            .autocorrectionDisabled()
            .accessibilityLabel("Endpoint")
            .accessibilityIdentifier("preset_url_delivery_url")
            #if os(iOS)
            .textInputAutocapitalization(.never).keyboardType(.URL)
            #endif
    }

    private var tokenField: some View {
        SecureField("Bearer token", text: $tokenDraft)
            .autocorrectionDisabled()
            .accessibilityIdentifier("preset_url_delivery_token")
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    private var headersField: some View {
        TextEditor(text: $headersDraft)
            .font(.system(.body, design: .monospaced)).frame(minHeight: 88)
            .autocorrectionDisabled()
            .accessibilityLabel("Custom Headers")
            .accessibilityIdentifier("preset_url_delivery_headers")
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    private func saveURL() {
        errorArea = .endpoint
        do {
            guard !settings.requiresCredentialMigration else {
                throw URLDeliveryKeychain.StorageError.missingCredentials
            }
            let url = try URLDeliveryValidator.validate(urlDraft, allowingInsecureLocal: settings.allowingInsecureLocal)
            settings.urlString = url.absoluteString
            urlDraft = url.absoluteString
            errorMessage = nil
            if settings.credentialID != nil, settings.credentialURLString != url.absoluteString {
                headersDraft = ""
                errorMessage = URLDeliveryKeychain.StorageError.destinationChanged.localizedDescription
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadCredentials() {
        errorArea = .credentials
        urlDraft = settings.urlString
        guard !settings.requiresCredentialMigration else {
            errorMessage = String(localized: "Remove Saved Credentials, then re-enter your URL delivery credentials. Legacy values are no longer read from presets or host-scoped accounts.")
            return
        }
        guard let id = settings.credentialID else { return }
        do {
            guard let credentials = try URLDeliveryKeychain.credentials(forID: id) else { throw URLDeliveryKeychain.StorageError.missingCredentials }
            guard credentials.urlString == settings.urlString else { throw URLDeliveryKeychain.StorageError.destinationChanged }
            headersDraft = credentials.customHeaders.sorted { $0.key.lowercased() < $1.key.lowercased() }
                .map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            savedHeadersDraft = headersDraft
        } catch {
            // Do not clear presence flags on a locked or missing account.
            errorMessage = error.localizedDescription
        }
    }

    private func updateCredentials(_ update: (inout URLDeliveryKeychain.Credentials) throws -> Void) throws {
        let url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: settings.allowingInsecureLocal)
        let sameDestination = settings.credentialURLString == url.absoluteString
        guard !settings.requiresCredentialMigration else { throw URLDeliveryKeychain.StorageError.missingCredentials }
        guard settings.credentialID == nil || sameDestination else { throw URLDeliveryKeychain.StorageError.destinationChanged }
        let id = sameDestination ? (settings.credentialID ?? UUID().uuidString) : UUID().uuidString
        var credentials = URLDeliveryKeychain.Credentials(urlString: url.absoluteString)
        if sameDestination, let storedID = settings.credentialID {
            guard let stored = try URLDeliveryKeychain.credentials(forID: storedID) else { throw URLDeliveryKeychain.StorageError.missingCredentials }
            guard stored.urlString == url.absoluteString else { throw URLDeliveryKeychain.StorageError.destinationChanged }
            credentials = stored
        }
        try update(&credentials)
        try URLDeliveryKeychain.saveCredentials(credentials, forID: id)
        settings.credentialID = id
        settings.credentialURLString = url.absoluteString
        settings.hasBearerToken = credentials.bearerToken != nil
        settings.hasCustomHeaders = !credentials.customHeaders.isEmpty
        settings.customHeaders = [:]
        settings.requiresCredentialMigration = false
    }

    private func saveToken() {
        errorArea = .credentials
        do {
            try updateCredentials { $0.bearerToken = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
            tokenDraft = ""
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveHeaders() {
        errorArea = .headers
        do {
            var headers: [String: String] = [:]
            for line in headersDraft.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let separator = line.firstIndex(of: ":") else { throw URLDeliveryValidationError.invalidHeaders }
                let name = line[..<separator].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                guard !headers.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { throw URLDeliveryValidationError.invalidHeaders }
                headers[name] = value
            }
            try URLDeliveryValidator.validateHeaders(headers)
            try updateCredentials { $0.customHeaders = headers }
            savedHeadersDraft = headersDraft
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func removeToken() {
        errorArea = .credentials
        do { try updateCredentials { $0.bearerToken = nil }; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func removeCredentials() {
        errorArea = .credentials
        do {
            try URLDeliveryKeychain.deleteCredentials(for: settings)
            settings.credentialID = nil
            settings.credentialURLString = nil
            settings.hasBearerToken = false
            settings.hasCustomHeaders = false
            settings.requiresCredentialMigration = false
            settings.customHeaders = [:]
            tokenDraft = ""
            headersDraft = ""
            savedHeadersDraft = ""
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func sendTest() async {
        guard !isTesting else { return }
        isTesting = true
        defer { isTesting = false }
        var testSettings = settings
        testSettings.maxAttempts = 1
        let event = await TranscriptURLDeliverer.appDefault().sendTest(settings: testSettings)
        switch event.result {
        case .delivered(let code): testResult = String(localized: "Delivered (HTTP \(code)).")
        case .failed(let message, _): testResult = message
        case .disabled: testResult = String(localized: "Enable delivery first.")
        case .queued, .retained: testResult = String(localized: "Saved locally. Open URL Deliveries to review it.")
        }
        await URLDeliveryRuntime.coordinator.refresh()
    }
}
