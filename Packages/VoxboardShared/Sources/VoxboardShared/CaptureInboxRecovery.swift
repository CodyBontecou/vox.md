import Foundation
import VoxboardCaptureCore

/// A failed inbox capture with the details a recovery sheet needs. Built
/// on demand in the foreground; never persisted.
public struct CaptureDeliveryProblem: Identifiable, Equatable, Sendable {
    public var requestID: UUID
    public var createdAt: Date
    public var source: CaptureSource
    public var destinationID: UUID
    public var destinationName: String
    public var routeID: String?
    public var routeName: String?
    /// The captured text (or a short description of attachments) shown so the
    /// user can see the capture is safe.
    public var preview: String
    public var itemCount: Int
    public var failureCategory: CaptureHistoryFailureCategory?
    public var failureReason: CaptureDeliveryFailureReason?

    public var id: UUID { requestID }

    public var displayRouteName: String { routeName ?? destinationName }
}

/// Foreground recovery actions for failed inbox captures and Library
/// re-delivery. Every action keeps the stable request ID so a retry can never
/// duplicate a note entry.
public enum CaptureInboxRecovery {
    public static func problems(
        captureRootURL: URL,
        coordinator: any CaptureFileCoordinating = NSFileCoordinatorCaptureFileCoordinator.shared
    ) async -> [CaptureDeliveryProblem] {
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL, coordinator: coordinator)
        let history = CaptureHistoryStore(
            fileURL: captureRootURL.appendingPathComponent(AppConstants.captureHistoryFilename),
            coordinator: coordinator
        )
        let requests = (try? await inbox.failedRequests()) ?? []
        guard !requests.isEmpty else { return [] }
        let records = Dictionary(
            ((try? await history.list()) ?? []).map { ($0.requestID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let libraryStore = CaptureLibraryStore(
            fileURL: captureRootURL.appendingPathComponent(CaptureLibraryStore.defaultFilename),
            coordinator: coordinator
        )
        let library = try? await libraryStore.load()
        return requests.map { request in
            let record = records[request.id]
            let text = CaptureLibraryContent.plainText(of: request)
            let attachments = request.payloads.filter {
                if case .text = $0 { return false }
                if case .url = $0 { return false }
                return true
            }.count
            let preview = text ?? (attachments == 1
                ? "1 attachment"
                : "\(attachments) attachments")
            let listItems = (text ?? "").components(separatedBy: "\n").filter {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
            }.count
            return CaptureDeliveryProblem(
                requestID: request.id,
                createdAt: request.createdAt,
                source: request.source,
                destinationID: request.destinationID,
                destinationName: library?.destinations.first(where: { $0.id == request.destinationID })?.name
                    ?? record?.destinationName
                    ?? "Unavailable destination",
                routeID: request.voxProfile?.id,
                routeName: request.voxProfile?.name ?? record?.voxName,
                preview: preview,
                itemCount: max(listItems, text == nil ? attachments : 1),
                failureCategory: record?.failureCategory,
                failureReason: record?.failureReason
            )
        }
    }

    // MARK: Headings

    /// Headings present in the target note, outside fenced code blocks.
    public static func headings(
        relativeNotePath: String,
        destinationID: UUID,
        captureRootURL: URL
    ) async -> [CaptureHeadingSelector] {
        guard (try? CapturePathValidation.validateRelativePath(relativeNotePath)) != nil,
              let destination = await destination(id: destinationID, captureRootURL: captureRootURL),
              let resolution = try? CaptureBookmarkResolver.resolve(destination.rootBookmark) else {
            return []
        }
        let rootURL = resolution.url
        let didAccess = rootURL.startAccessingSecurityScopedResource()
        defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
        let noteURL = rootURL.appendingPathComponent(relativeNotePath, isDirectory: false)
        guard let markdown = try? String(contentsOf: noteURL, encoding: .utf8) else { return [] }
        return headings(inMarkdown: markdown)
    }

    public static func headings(inMarkdown markdown: String) -> [CaptureHeadingSelector] {
        var result: [CaptureHeadingSelector] = []
        var inFence = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence, line.hasPrefix("#") else { continue }
            let hashes = line.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes) else { continue }
            let rest = line.dropFirst(hashes)
            guard rest.first == " " else { continue }
            var title = rest.trimmingCharacters(in: .whitespaces)
            while title.hasSuffix("#") { title.removeLast() }
            title = title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            result.append(CaptureHeadingSelector(title: title, level: hashes))
        }
        return result
    }

    // MARK: Actions

    /// Delivers a failed capture beneath `heading`, optionally creating the
    /// heading when the note does not have it.
    @discardableResult
    public static func deliver(
        requestID: UUID,
        beneath heading: CaptureHeadingSelector,
        createIfMissing: Bool,
        captureRootURL: URL
    ) async throws -> Bool {
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        let position = await currentHeadingPosition(requestID: requestID, captureRootURL: captureRootURL)
        return try await inbox.reviseFailedRequest(requestID: requestID) { request in
            request.placementOverride = .beneathHeading(
                heading,
                missingHeadingBehavior: createIfMissing ? .create : .fail,
                headingPosition: position
            )
        }
    }

    /// Reroutes a failed capture to the library's default (Inbox) route.
    @discardableResult
    public static func sendToDefaultRoute(
        requestID: UUID,
        captureRootURL: URL
    ) async throws -> Bool {
        guard let defaultID = await defaultDestinationID(captureRootURL: captureRootURL) else { return false }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        return try await inbox.reviseFailedRequest(requestID: requestID) { request in
            request.destinationID = defaultID
            request.placementOverride = nil
            request.relativeNotePathOverride = nil
            request.entryTemplateIDOverride = nil
            // The default route uses its own placement, not this preset's.
            request.voxProfile?.capturePlacementOverride = nil
        }
    }

    public static func defaultDestination(captureRootURL: URL) async -> CaptureDestination? {
        guard let library = await library(captureRootURL: captureRootURL) else { return nil }
        let id = library.defaultDestinationID.flatMap { id in
            library.destinations.contains(where: { $0.id == id }) ? id : nil
        } ?? library.destinations.first?.id
        return library.destinations.first { $0.id == id }
    }

    @discardableResult
    public static func discard(requestID: UUID, captureRootURL: URL) async throws -> Bool {
        try await CaptureInbox(rootDirectoryURL: captureRootURL).discard(requestID: requestID)
    }

    @discardableResult
    public static func retry(requestID: UUID, captureRootURL: URL) async throws -> Bool {
        try await CaptureInbox(rootDirectoryURL: captureRootURL).retryFailed(requestID: requestID)
    }

    /// Updates the route so later captures land beneath `heading`, creating
    /// it when missing. A preset-level placement override is updated when
    /// the preset owns the placement; otherwise the destination is updated.
    public static func fixRoute(
        destinationID: UUID,
        presetID: String?,
        heading: CaptureHeadingSelector,
        createIfMissing: Bool,
        captureRootURL: URL,
        defaults: UserDefaults? = AppConstants.sharedDefaults
    ) async throws {
        if let presetID {
            var flows = CapturePresetStore.loadFlows(defaults: defaults)
            if let index = flows.firstIndex(where: { $0.id == presetID }),
               case .beneathHeading(_, _, let position)? = flows[index].capturePlacementOverride {
                flows[index].capturePlacementOverride = .beneathHeading(
                    heading,
                    missingHeadingBehavior: createIfMissing ? .create : .fail,
                    headingPosition: position
                )
                CapturePresetStore.saveFlows(flows, defaults: defaults)
                return
            }
        }
        let store = CaptureLibraryStore(
            fileURL: captureRootURL.appendingPathComponent(CaptureLibraryStore.defaultFilename)
        )
        try await store.update { library in
            guard let index = library.destinations.firstIndex(where: { $0.id == destinationID }) else { return }
            var position = CaptureHeadingPosition.top
            if case .beneathHeading(_, _, let current) = library.destinations[index].placement {
                position = current
            }
            library.destinations[index].placement = .beneathHeading(
                heading,
                missingHeadingBehavior: createIfMissing ? .create : .fail,
                headingPosition: position
            )
        }
    }

    /// Replaces a destination's folder access after the user re-picks the
    /// vault folder, then returns its failed captures to the queue.
    public static func replaceFolderAccess(
        destinationID: UUID,
        bookmark: Data,
        rootName: String,
        captureRootURL: URL
    ) async throws {
        let store = CaptureLibraryStore(
            fileURL: captureRootURL.appendingPathComponent(CaptureLibraryStore.defaultFilename)
        )
        try await store.update { library in
            guard let index = library.destinations.firstIndex(where: { $0.id == destinationID }) else { return }
            library.destinations[index].rootBookmark = bookmark
            library.destinations[index].rootName = rootName
        }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        for id in try await inbox.requestIDs(referencingDestination: destinationID, states: [.failed]) {
            _ = try await inbox.retryFailed(requestID: id)
        }
    }

    /// Queues `text` as a new capture for another route. The caller drains
    /// the inbox afterwards to deliver it.
    @discardableResult
    public static func redeliver(
        text: String,
        createdAt: Date = Date(),
        to profile: CapturePresetProfile,
        captureRootURL: URL
    ) async throws -> UUID {
        let destinationID: UUID
        if let owned = profile.captureDestinationID {
            destinationID = owned
        } else if let fallback = await defaultDestinationID(captureRootURL: captureRootURL) {
            destinationID = fallback
        } else {
            throw ConfiguredTranscriptCaptureError.destinationMissing(UUID())
        }
        let request = CaptureRequest(
            createdAt: createdAt,
            source: .app,
            destinationID: destinationID,
            payloads: [.text(text)],
            frontmatter: profile.staticFrontmatter,
            voxProfile: profile,
            voxProcessingState: .notRequested
        )
        try await CaptureInbox(rootDirectoryURL: captureRootURL).enqueue(request)
        return request.id
    }

    // MARK: Obsidian

    /// `obsidian://open?vault=…&file=…` for a vault-relative note path. The
    /// vault name is the destination folder's name.
    public static func obsidianOpenURL(vaultName: String, relativePath: String) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        var file = relativePath
        if file.lowercased().hasSuffix(".md") { file = String(file.dropLast(3)) }
        components.queryItems = [
            URLQueryItem(name: "vault", value: vaultName),
            URLQueryItem(name: "file", value: file),
        ]
        return components.url
    }

    public static func obsidianSearchURL(query: String, vaultName: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "search"
        var items: [URLQueryItem] = []
        if let vaultName { items.append(URLQueryItem(name: "vault", value: vaultName)) }
        items.append(URLQueryItem(name: "query", value: query))
        components.queryItems = items
        return components.url
    }

    // MARK: Private

    private static func library(captureRootURL: URL) async -> CaptureLibraryEnvelope? {
        let store = CaptureLibraryStore(
            fileURL: captureRootURL.appendingPathComponent(CaptureLibraryStore.defaultFilename)
        )
        return try? await store.load()
    }

    public static func destination(id: UUID, captureRootURL: URL) async -> CaptureDestination? {
        await library(captureRootURL: captureRootURL)?.destinations.first { $0.id == id }
    }

    private static func defaultDestinationID(captureRootURL: URL) async -> UUID? {
        await defaultDestination(captureRootURL: captureRootURL)?.id
    }

    private static func currentHeadingPosition(requestID: UUID, captureRootURL: URL) async -> CaptureHeadingPosition {
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        guard let request = try? await inbox.request(requestID: requestID, states: [.failed]) else { return .top }
        let stored = await destination(id: request.destinationID, captureRootURL: captureRootURL)
        let placement = request.placementOverride
            ?? request.voxProfile?.capturePlacementOverride
            ?? stored?.placement
        if case .beneathHeading(_, _, let position)? = placement { return position }
        return .top
    }
}
