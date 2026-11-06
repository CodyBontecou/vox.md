import CoreLocation
import Foundation
import Observation
import UIKit
import VoxboardShared

private let log = KeyboardDebugLog.shared

/// Quick actions the keyboard can perform through `textDocumentProxy`.
/// Media, OCR, sketch, undo and formatting actions need the Capture composer,
/// so they never appear in the keyboard row.
enum KeyboardQuickActions {
    static let supported: Set<CaptureQuickAction> = [
        .checklist, .bulletList, .heading, .bold, .italic, .markdownLink,
        .internalLink, .tag, .timestamp, .date, .dueDate, .currentLocation, .paste,
    ]

    /// The Voice keyboard board's own row, used before the user has saved any
    /// pins or when "Same actions on Mac, iPad and keyboard" is off.
    static let keyboardDefault: [CaptureQuickAction] = [
        .checklist, .internalLink, .tag, .timestamp, .currentLocation,
    ]

    /// Ordered pins for a Route, read from the App Group pins shared by the app.
    /// Location is dropped when the keyboard can't get authorization (no Full
    /// Access, or the user denied / restricted location for Vox.md).
    static func pins(
        forRoute routeID: String?,
        defaults: UserDefaults? = AppConstants.sharedDefaults,
        locationAvailable: Bool = KeyboardQuickActions.isLocationAvailable()
    ) -> [CaptureQuickAction] {
        let available = locationAvailable ? supported : supported.subtracting([.currentLocation])
        let fallback = keyboardDefault.filter(available.contains)
        let hasSavedPins = defaults?.object(forKey: CaptureQuickActionPins.routePinsKey) != nil
            || defaults?.object(forKey: CaptureQuickActionPins.defaultPinsKey) != nil
        guard hasSavedPins else { return fallback }
        let shared = CaptureQuickActionPins.load(from: defaults)
        guard let pins = shared.pinsForOtherSurface(route: routeID) else { return fallback }
        let filtered = pins.filter(available.contains)
        return filtered.isEmpty ? fallback : filtered
    }

    /// Keyboards can use Location Services only with Full Access. Recorded by
    /// `KeyboardViewController` in the App Group each time it appears.
    static func isLocationAvailable(defaults: UserDefaults? = AppConstants.sharedDefaults) -> Bool {
        guard CapturePresetSurfacePinStore.keyboardHasFullAccess(defaults: defaults) == true else { return false }
        switch CLLocationManager().authorizationStatus {
        case .denied, .restricted: return false
        default: return true
        }
    }

    // MARK: Glyphs

    static func glyph(for action: CaptureQuickAction, now: Date = Date()) -> String {
        switch action {
        case .timestamp: return shortTime(now)
        case .date: return format(now, pattern: "MM-dd")
        default: return action.glyph
        }
    }

    // MARK: Insertion

    struct Snippet {
        var text: String
        /// Characters to move the cursor after inserting (negative = left).
        var cursorOffset: Int = 0
    }

    /// The text an action inserts, or nil for actions resolved asynchronously
    /// (location) or that need the pasteboard.
    static func snippet(for action: CaptureQuickAction, now: Date = Date()) -> Snippet? {
        let formatter = CaptureInsertionFormatter()
        switch action {
        case .checklist: return Snippet(text: "- [ ] ")
        case .bulletList: return Snippet(text: "- ")
        case .heading: return Snippet(text: "## ")
        case .bold: return Snippet(text: "****", cursorOffset: -2)
        case .italic: return Snippet(text: "__", cursorOffset: -1)
        case .markdownLink: return Snippet(text: "[]()", cursorOffset: -3)
        case .internalLink: return Snippet(text: "[[]]", cursorOffset: -2)
        case .tag: return Snippet(text: "#")
        case .timestamp:
            let format: CaptureTimestampFormat = usesTwentyFourHourClock ? .twentyFourHour : .twelveHour
            return Snippet(text: formatter.currentTimestamp(at: now, format: format) + " ")
        case .date: return Snippet(text: format(now, pattern: "yyyy-MM-dd") + " ")
        case .dueDate:
            let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: now) ?? now
            return Snippet(text: formatter.dueDateToken(for: tomorrow) + " ")
        case .paste:
            guard let text = UIPasteboard.general.string, !text.isEmpty else { return nil }
            return Snippet(text: text)
        default:
            return nil
        }
    }

    // MARK: Location

    @MainActor
    @Observable
    final class LocationRequester {
        private var service: CaptureLocationService?
        private var task: Task<Void, Never>?
        private(set) var isRequesting = false

        func requestMarkdown(completion: @escaping @MainActor (Result<String, Error>) -> Void) {
            guard task == nil else { return }
            let service = CaptureLocationService()
            self.service = service
            isRequesting = true
            task = Task { @MainActor [weak self] in
                defer {
                    self?.task = nil
                    self?.service = nil
                    self?.isRequesting = false
                }
                do {
                    let location = try await service.requestCurrentLocation()
                    let markdown = try CaptureInsertionFormatter().googleMapsLink(
                        latitude: location.latitude,
                        longitude: location.longitude,
                        label: location.label
                    )
                    completion(.success(markdown + " "))
                } catch is CancellationError {
                    // Keyboard dismissed.
                } catch {
                    log.log("◎ Location quick action failed: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }

        func cancel() {
            task?.cancel()
        }
    }

    // MARK: Helpers

    /// Follows the app's Insert Timestamp setting (mirrored to the App
    /// Group); falls back to the device's hour cycle before the app wrote it.
    private static var usesTwentyFourHourClock: Bool {
        if let format = CaptureQuickActionPins.sharedTimestampFormat() {
            return format == .twentyFourHour
        }
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return !pattern.contains("a")
    }

    private static func shortTime(_ date: Date) -> String {
        format(date, pattern: usesTwentyFourHourClock ? "HH:mm" : "h:mm")
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
