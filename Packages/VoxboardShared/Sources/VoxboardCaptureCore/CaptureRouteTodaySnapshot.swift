import Foundation

/// Small, privacy-limited snapshot of what each route delivered today, for the
/// Lock Screen "Route Today" widget.
///
/// It lives beside the capture history in the App Group and holds only the
/// first line of each of today's items (trimmed and length-capped), at most a
/// few items per route and a bounded number of routes. It is rewritten at
/// delivery time, ignored and replaced once the local day changes, and deleted
/// when the Library is cleared.
public struct CaptureRouteTodaySnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumItemsPerRoute = 3
    public static let maximumRoutes = 16
    public static let maximumLineLength = 80
    public static let filenameSuffix = "-route-today.json"

    public struct Item: Codable, Equatable, Sendable {
        public var requestID: UUID
        public var firstLine: String

        public init(requestID: UUID, firstLine: String) {
            self.requestID = requestID
            self.firstLine = firstLine
        }
    }

    public struct Route: Codable, Equatable, Sendable {
        /// Newest first, capped at `maximumItemsPerRoute`.
        public var items: [Item]
        /// Deliveries today, including ones no longer listed in `items`.
        public var count: Int
        public var updatedAt: Date

        public init(items: [Item] = [], count: Int = 0, updatedAt: Date) {
            self.items = items
            self.count = count
            self.updatedAt = updatedAt
        }
    }

    public var schemaVersion: Int
    /// Local calendar day (`yyyy-MM-dd`) the snapshot describes.
    public var day: String
    public var routes: [String: Route]

    public init(day: String, routes: [String: Route] = [:]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.day = day
        self.routes = routes
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Today's entry for a route, or nil when the snapshot is from another day.
    public func route(_ routeID: String, now: Date = Date(), calendar: Calendar = .current) -> Route? {
        guard day == Self.dayKey(for: now, calendar: calendar) else { return nil }
        return routes[routeID]
    }

    /// Records one delivery. A retried request ID replaces its earlier item
    /// instead of counting twice. Starts a fresh snapshot on a new day.
    public mutating func record(
        requestID: UUID,
        routeID: String,
        text: String,
        at date: Date,
        calendar: Calendar = .current
    ) {
        let today = Self.dayKey(for: date, calendar: calendar)
        if day != today {
            day = today
            routes = [:]
        }
        guard let line = Self.firstLine(of: text) else { return }
        var route = routes[routeID] ?? Route(updatedAt: date)
        let isRetry = route.items.contains { $0.requestID == requestID }
        route.items.removeAll { $0.requestID == requestID }
        route.items.insert(Item(requestID: requestID, firstLine: line), at: 0)
        route.items = Array(route.items.prefix(Self.maximumItemsPerRoute))
        if !isRetry { route.count += 1 }
        route.updatedAt = date
        routes[routeID] = route
        if routes.count > Self.maximumRoutes {
            let oldest = routes.sorted { $0.value.updatedAt < $1.value.updatedAt }
                .prefix(routes.count - Self.maximumRoutes)
            for (id, _) in oldest { routes[id] = nil }
        }
    }

    /// The first non-empty line, with leading Markdown list, task, heading,
    /// quote and numbered-item markers removed and capped at `maximumLineLength`.
    public static func firstLine(of text: String) -> String? {
        CaptureTitleText.firstLine(of: text) { rawLine in
            var line = CaptureTitleText.strippingLineMarkers(rawLine)
            guard !line.isEmpty else { return nil }
            if line.count > maximumLineLength {
                line = String(line.prefix(maximumLineLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
            }
            return line
        }
    }

    public static func fileURL(forHistoryFileURL historyURL: URL) -> URL {
        let stem = historyURL.deletingPathExtension().lastPathComponent
        return historyURL.deletingLastPathComponent()
            .appendingPathComponent(stem + filenameSuffix, isDirectory: false)
    }

    /// Reads the snapshot beside `historyURL`. Nil when missing, unreadable or
    /// from an unknown schema.
    public static func load(historyFileURL historyURL: URL) -> CaptureRouteTodaySnapshot? {
        let url = fileURL(forHistoryFileURL: historyURL)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(CaptureRouteTodaySnapshot.self, from: data),
              snapshot.schemaVersion == currentSchemaVersion else { return nil }
        return snapshot
    }
}
