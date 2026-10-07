import SwiftUI
import VoxboardShared

/// One native choice, shared by the iOS and Mac preset editors.
struct CapturePresetTargetSection: View {
    @Binding var flow: CapturePreset

    var body: some View {
        Section {
            Picker("Target", selection: $flow.deliveryTarget) {
                ForEach(CapturePresetDeliveryTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("preset_delivery_target")
        } header: {
            Text("Destination")
        } footer: {
            if flow.deliveryTarget == .http {
                Text("Send text as a JSON POST to an HTTP endpoint. No note or attachment files are exported to a directory.")
            } else {
                Text("Save captures as notes and attachments in your chosen directory. Nothing is sent to an HTTP endpoint.")
            }
        }
    }
}

/// The credential edit boundary used by both native editors. Keychain access is
/// injected so account and preset changes can be verified without real secrets.
struct URLDeliveryCredentialEditor {
    var load: (String) throws -> URLDeliveryKeychain.Credentials?
    var save: (URLDeliveryKeychain.Credentials, String) throws -> Void
    var delete: (String) throws -> Void

    static let live = URLDeliveryCredentialEditor(
        load: { try URLDeliveryKeychain.credentials(forID: $0) },
        save: { try URLDeliveryKeychain.saveCredentials($0, forID: $1) },
        delete: { try URLDeliveryKeychain.deleteCredentials(forID: $0) }
    )

    func loadCredentials(settings: inout CapturePresetURLDeliverySettings) throws -> URLDeliveryKeychain.Credentials? {
        guard let credentials = try loadBoundCredentials(settings: &settings) else { return nil }
        guard credentials.urlString == settings.urlString else { throw URLDeliveryKeychain.StorageError.destinationChanged }
        return credentials
    }

    func loadBoundCredentials(settings: inout CapturePresetURLDeliverySettings) throws -> URLDeliveryKeychain.Credentials? {
        guard !settings.requiresCredentialMigration else { throw URLDeliveryKeychain.StorageError.missingCredentials }
        guard let id = settings.credentialID else { return nil }
        guard let credentials = try load(id) else { throw URLDeliveryKeychain.StorageError.missingCredentials }
        guard credentials.urlString == settings.credentialURLString else {
            throw URLDeliveryKeychain.StorageError.destinationChanged
        }
        if credentials.bearerToken == nil, credentials.customHeaders.isEmpty {
            try persist(credentials, id: id, settings: &settings)
            return nil
        }
        return credentials
    }

    func updateCredentials(
        settings: inout CapturePresetURLDeliverySettings,
        _ update: (inout URLDeliveryKeychain.Credentials) throws -> Void
    ) throws {
        let url = try URLDeliveryValidator.validate(settings.urlString, allowingInsecureLocal: settings.allowingInsecureLocal)
        let sameDestination = settings.credentialURLString == url.absoluteString
        guard !settings.requiresCredentialMigration else { throw URLDeliveryKeychain.StorageError.missingCredentials }
        guard settings.credentialID == nil || sameDestination else { throw URLDeliveryKeychain.StorageError.destinationChanged }
        let id = sameDestination ? (settings.credentialID ?? UUID().uuidString) : UUID().uuidString
        var credentials = URLDeliveryKeychain.Credentials(urlString: url.absoluteString)
        if sameDestination, let storedID = settings.credentialID {
            guard let stored = try load(storedID) else { throw URLDeliveryKeychain.StorageError.missingCredentials }
            guard stored.urlString == url.absoluteString else { throw URLDeliveryKeychain.StorageError.destinationChanged }
            credentials = stored
        }
        try update(&credentials)
        try persist(credentials, id: id, settings: &settings)
    }

    func removeToken(settings: inout CapturePresetURLDeliverySettings) throws {
        guard !settings.requiresCredentialMigration else { throw URLDeliveryKeychain.StorageError.missingCredentials }
        if let id = settings.credentialID {
            guard var credentials = try load(id) else { throw URLDeliveryKeychain.StorageError.missingCredentials }
            guard credentials.urlString == settings.credentialURLString else {
                throw URLDeliveryKeychain.StorageError.destinationChanged
            }
            credentials.bearerToken = nil
            try persist(credentials, id: id, settings: &settings)
        }
        settings.hasBearerToken = false
    }

    private func persist(
        _ credentials: URLDeliveryKeychain.Credentials,
        id: String,
        settings: inout CapturePresetURLDeliverySettings
    ) throws {
        if credentials.bearerToken == nil, credentials.customHeaders.isEmpty {
            if settings.credentialID != nil { try delete(id) }
            settings.credentialID = nil
            settings.credentialURLString = nil
        } else {
            try save(credentials, id)
            settings.credentialID = id
            settings.credentialURLString = credentials.urlString
        }
        settings.hasBearerToken = credentials.bearerToken != nil
        settings.hasCustomHeaders = !credentials.customHeaders.isEmpty
        settings.customHeaders = [:]
        settings.requiresCredentialMigration = false
    }
}

/// The same endpoint editor on iOS and Mac. Only opaque account IDs and presence
/// flags cross the preset binding; token/header values stay in the Keychain.
struct URLDeliverySettingsSection: View {
    @Binding var settings: CapturePresetURLDeliverySettings
    var focusEndpointOnAppear = false
    @FocusState private var endpointIsFocused: Bool
    @FocusState private var tokenIsFocused: Bool
    @State private var urlDraft = ""
    @State private var tokenDraft = ""
    @State private var savedTokenDraft = ""
    @State private var tokenSaveFailed = false
    @State private var credentialsLoaded = false
    @State private var headersDraft = URLDeliveryHeadersDraft()
    @State private var savedHeadersDraft: [String: String] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum HeaderField: Hashable { case name(UUID), value(UUID) }
    @FocusState private var focusedHeader: HeaderField?
    private enum ErrorArea { case endpoint, credentials, headers }
    @State private var errorArea = ErrorArea.credentials
    @State private var errorMessage: String?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>?
    private let credentialEditor = URLDeliveryCredentialEditor.live
    private struct AutosaveInput: Equatable {
        var url: String
        var token: String
        var allowingInsecureLocal: Bool
    }

    private var autosaveInput: AutosaveInput {
        AutosaveInput(url: urlDraft, token: tokenDraft, allowingInsecureLocal: settings.allowingInsecureLocal)
    }

    private var normalizedTokenDraft: String {
        tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedToken: Bool { normalizedTokenDraft != savedTokenDraft }

    private var hasUnsavedURL: Bool {
        (try? URLDeliveryValidator.validate(urlDraft, allowingInsecureLocal: settings.allowingInsecureLocal).absoluteString)
            != settings.urlString
    }
    #if os(macOS)
    @State private var showDeliveries = false
    #endif

    var body: some View {
        Section {
            if settings.enabled {
                Text("Endpoint").font(.subheadline)
                endpointField
                Toggle("Allow insecure local HTTP", isOn: $settings.allowingInsecureLocal)
                    .accessibilityIdentifier("preset_url_delivery_insecure_local")
                Text("HTTP sends your capture and credentials without encryption. Only enable this for a trusted local endpoint.")
                    .font(.caption).foregroundStyle(.secondary)
                inlineError(.endpoint)

                Text("Bearer Token (Optional)").font(.subheadline)
                tokenField
                Text("URL and token changes save automatically.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Button {
                    focusedHeader = .name(headersDraft.addRow())
                } label: {
                    Label("Add Header", systemImage: "plus")
                }
                .disabled(headersDraft.rows.count >= 32 || settings.requiresCredentialMigration)
                .accessibilityIdentifier("preset_url_delivery_add_header")
                Button("Save Headers", action: saveHeaders)
                    .disabled(settings.requiresCredentialMigration)
                    .accessibilityIdentifier("preset_url_delivery_save_headers")
                Text("Add a header and its value in each row, then save your changes. Values are saved only in the Keychain. Content-Type, Idempotency-Key, and bearer authorization are managed by Vox.md.")
                    .font(.caption).foregroundStyle(.secondary)

                inlineError(.headers)
                Button {
                    testTask = Task { await sendTest() }
                } label: {
                    if isTesting { HStack { ProgressView(); Text("Sending test…") } }
                    else { Text("Send Test") }
                }
                .disabled(isTesting || errorMessage != nil || settings.requiresCredentialMigration
                    || headersDraft.hasUnsavedChanges(comparedTo: savedHeadersDraft) || hasUnsavedURL
                    || settings.urlString.isEmpty || hasUnsavedToken)
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
            Text("HTTP Endpoint")
        } footer: {
            Text("Sends text and transcript metadata as JSON, not the exported note or attachment files. Draft recordings are not sent until you choose Send. Redirects are not followed. Failed deliveries are retained for retry or discard in URL Deliveries.")
        }
        .onAppear(perform: loadCredentials)
        .task {
            if focusEndpointOnAppear { endpointIsFocused = true }
        }
        .task(id: autosaveInput) {
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            guard !Task.isCancelled else { return }
            saveInputs()
        }
        .onChange(of: endpointIsFocused) { _, isFocused in
            if !isFocused { saveInputs() }
        }
        .onChange(of: tokenIsFocused) { _, isFocused in
            if !isFocused { saveInputs() }
        }
        .onDisappear {
            saveInputs()
            credentialsLoaded = false
            testTask?.cancel()
            endpointIsFocused = false
            tokenIsFocused = false
            tokenDraft = ""
            savedTokenDraft = ""
            focusedHeader = nil
            headersDraft = URLDeliveryHeadersDraft()
            savedHeadersDraft = [:]
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
            .focused($endpointIsFocused)
            .submitLabel(.done)
            .onSubmit { saveInputs(); endpointIsFocused = false }
            .accessibilityLabel("Endpoint")
            .accessibilityIdentifier("preset_url_delivery_url")
            #if os(iOS)
            .textInputAutocapitalization(.never).keyboardType(.URL)
            #endif
    }

    private var tokenField: some View {
        SecureField("Bearer token", text: $tokenDraft)
            .autocorrectionDisabled()
            .focused($tokenIsFocused)
            .submitLabel(.done)
            .onSubmit { saveInputs(); tokenIsFocused = false }
            .disabled(settings.requiresCredentialMigration)
            .accessibilityIdentifier("preset_url_delivery_token")
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    private var headersField: some View {
        ForEach($headersDraft.rows) { row in
            headerRow(row)
        }
    }

    private func headerRow(_ row: Binding<URLDeliveryHeadersDraft.Row>) -> some View {
        let index = headersDraft.rows.firstIndex { $0.id == row.wrappedValue.id } ?? 0
        return HStack(alignment: .bottom, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    headerNameField(row, index: index)
                    headerValueField(row, index: index)
                }
            } else {
                headerNameField(row, index: index)
                headerValueField(row, index: index)
            }
            Button(role: .destructive) {
                let id = row.wrappedValue.id
                if focusedHeader == .name(id) || focusedHeader == .value(id) { focusedHeader = nil }
                headersDraft.removeRow(id: id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(headersDraft.rows.count == 1 && row.wrappedValue.isBlank)
            .accessibilityLabel("Remove header \(index + 1)")
            .accessibilityIdentifier("preset_url_delivery_remove_header_\(index)")
        }
        .disabled(settings.requiresCredentialMigration)
    }

    private func headerNameField(_ row: Binding<URLDeliveryHeadersDraft.Row>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Header").font(.caption).foregroundStyle(.secondary)
            TextField("X-Api-Key", text: row.name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($focusedHeader, equals: .name(row.wrappedValue.id))
                .submitLabel(.next)
                .onSubmit { focusedHeader = .value(row.wrappedValue.id) }
                .accessibilityLabel("Header \(index + 1)")
                .accessibilityIdentifier("preset_url_delivery_header_name_\(index)")
                #if os(iOS)
                .textInputAutocapitalization(.never).keyboardType(.asciiCapable)
                #endif
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerValueField(_ row: Binding<URLDeliveryHeadersDraft.Row>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Value").font(.caption).foregroundStyle(.secondary)
            TextField("Enter value", text: row.value)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($focusedHeader, equals: .value(row.wrappedValue.id))
                .submitLabel(.done)
                .onSubmit { focusedHeader = nil }
                .accessibilityLabel("Value \(index + 1)")
                .accessibilityIdentifier("preset_url_delivery_header_value_\(index)")
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveInputs() {
        guard credentialsLoaded else { return }
        let endpointIsValid = saveURL()
        if hasUnsavedToken, normalizedTokenDraft.isEmpty {
            removeToken()
        } else if hasUnsavedToken, endpointIsValid {
            saveToken()
        } else if tokenSaveFailed {
            clearError(.credentials)
            tokenSaveFailed = false
        }
    }

    private func clearError(_ area: ErrorArea) {
        if errorArea == area { errorMessage = nil }
    }

    @discardableResult
    private func saveURL() -> Bool {
        if urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !settings.urlString.isEmpty { settings.urlString = "" }
            clearError(.endpoint)
            return false
        }
        do {
            let url = try URLDeliveryValidator.validate(urlDraft, allowingInsecureLocal: settings.allowingInsecureLocal)
            let endpointChanged = settings.urlString != url.absoluteString
            if endpointChanged { settings.urlString = url.absoluteString }
            clearError(.endpoint)
            if settings.credentialID != nil, settings.credentialURLString != url.absoluteString {
                if endpointChanged {
                    focusedHeader = nil
                }
                errorArea = .endpoint
                errorMessage = URLDeliveryKeychain.StorageError.destinationChanged.localizedDescription
                return false
            }
            return true
        } catch {
            errorArea = .endpoint
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadCredentials() {
        credentialsLoaded = false
        defer { credentialsLoaded = true }
        errorArea = .credentials
        urlDraft = settings.urlString
        tokenDraft = ""
        savedTokenDraft = ""
        tokenSaveFailed = false
        headersDraft = URLDeliveryHeadersDraft()
        savedHeadersDraft = [:]
        errorMessage = nil
        guard !settings.requiresCredentialMigration else {
            errorMessage = String(localized: "Remove Saved Credentials, then re-enter your URL delivery credentials. Legacy values are no longer read from presets or host-scoped accounts.")
            return
        }
        do {
            guard let credentials = try credentialEditor.loadBoundCredentials(settings: &settings) else { return }
            tokenDraft = credentials.bearerToken ?? ""
            savedTokenDraft = normalizedTokenDraft
            headersDraft = URLDeliveryHeadersDraft(headers: credentials.customHeaders)
            savedHeadersDraft = credentials.customHeaders
            if credentials.urlString != settings.urlString {
                errorArea = .endpoint
                errorMessage = URLDeliveryKeychain.StorageError.destinationChanged.localizedDescription
            }
        } catch {
            // Do not clear presence flags on a locked or missing account.
            errorMessage = error.localizedDescription
        }
    }

    private func updateCredentials(_ update: (inout URLDeliveryKeychain.Credentials) throws -> Void) throws {
        try credentialEditor.updateCredentials(settings: &settings, update)
    }

    private func saveToken() {
        do {
            let token = normalizedTokenDraft
            try updateCredentials { $0.bearerToken = token.isEmpty ? nil : token }
            savedTokenDraft = token
            tokenSaveFailed = false
            clearError(.credentials)
        } catch {
            tokenSaveFailed = true
            errorArea = .credentials
            errorMessage = error.localizedDescription
        }
    }

    private func saveHeaders() {
        saveInputs()
        guard !hasUnsavedURL, !hasUnsavedToken else { return }
        errorArea = .headers
        do {
            let headers = try headersDraft.validatedHeaders()
            try updateCredentials { $0.customHeaders = headers }
            savedHeadersDraft = headers
            focusedHeader = nil
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func removeToken() {
        do {
            try credentialEditor.removeToken(settings: &settings)
            tokenDraft = ""
            savedTokenDraft = ""
            tokenSaveFailed = false
            clearError(.credentials)
            if settings.credentialID == nil { _ = saveURL() }
        } catch {
            tokenSaveFailed = true
            errorArea = .credentials
            errorMessage = error.localizedDescription
        }
    }

    private func removeCredentials() {
        errorArea = .credentials
        do {
            if let id = settings.credentialID { try URLDeliveryKeychain.deleteCredentials(forID: id) }
            settings.credentialID = nil
            settings.credentialURLString = nil
            settings.hasBearerToken = false
            settings.hasCustomHeaders = false
            settings.requiresCredentialMigration = false
            settings.customHeaders = [:]
            tokenDraft = ""
            savedTokenDraft = ""
            focusedHeader = nil
            headersDraft = URLDeliveryHeadersDraft()
            savedHeadersDraft = [:]
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
