import Foundation
import VoxboardCaptureCore

public enum CaptureDeliveryUsageStoreError: Error, Equatable, LocalizedError, Sendable {
    case storageUnavailable
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Shared Capture usage storage is unavailable."
        case .unsupportedSchemaVersion(let version):
            return "Capture usage schema version \(version) is not supported."
        }
    }
}

public struct CaptureDeliveryUsageSnapshot: Equatable, Sendable {
    public let successfulCapturesUsed: Int
    public let reservedCaptureSlots: Int
    public let freeCaptureLimit: Int

    public var capturesRemaining: Int {
        max(0, freeCaptureLimit - successfulCapturesUsed)
    }

    public var isAtLimit: Bool {
        successfulCapturesUsed >= freeCaptureLimit
    }
}

private struct CaptureUsageLedger: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var unattributedSuccessfulCount = 0
    var committedRequestIDs: Set<UUID> = []
    var reservationTokensByRequestID: [UUID: Set<UUID>] = [:]

    var successfulCaptureCount: Int {
        unattributedSuccessfulCount + committedRequestIDs.count
    }

    var reservedCaptureSlots: Int {
        reservationTokensByRequestID.keys.reduce(into: 0) { count, requestID in
            if !committedRequestIDs.contains(requestID) { count += 1 }
        }
    }
}

/// Exact-once accounting for successful, non-voice Capture deliveries.
///
/// The coordinated App Group ledger prevents app/macOS delivery races within
/// an installation. Capture usage is deliberately not stored in Keychain, so
/// removing the app's local data starts a fresh free allowance.
public actor CaptureDeliveryUsageStore: CaptureDeliveryAccounting {
    public static let shared = CaptureDeliveryUsageStore()

    private let ledgerURL: URL?
    private let freeCaptureLimit: Int
    private let coordinator: any CaptureFileCoordinating
    private let fileManager: FileManager
    private let isUnlocked: @Sendable () -> Bool
    private let mirrorSuccessfulCount: @Sendable (Int) -> Void
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    package init(
        ledgerURL: URL? = AppConstants.captureUsageURL,
        freeCaptureLimit: Int = UsageTracker.freeCaptureLimit,
        coordinator: any CaptureFileCoordinating = NSFileCoordinatorCaptureFileCoordinator.shared,
        fileManager: FileManager = .default,
        isUnlocked: @escaping @Sendable () -> Bool = {
            AppConstants.sharedDefaults?.bool(forKey: UsageTracker.hasUnlockedKey) ?? false
        },
        mirrorSuccessfulCount: @escaping @Sendable (Int) -> Void = { count in
            AppConstants.sharedDefaults?.set(count, forKey: AppConstants.captureUsageMirrorKey)
        }
    ) {
        self.ledgerURL = ledgerURL
        self.freeCaptureLimit = max(0, freeCaptureLimit)
        self.coordinator = coordinator
        self.fileManager = fileManager
        self.isUnlocked = isUnlocked
        self.mirrorSuccessfulCount = mirrorSuccessfulCount
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func reserve(for request: CaptureRequest) async throws -> CaptureDeliveryReservation {
        // Voice transcripts already consume the independent transcription
        // allowance. The lifetime purchase bypasses both free-tier meters.
        guard request.deliveryKind != .meteredVoiceTranscript, !isUnlocked() else {
            return .bypassed(requestID: request.id)
        }
        guard let ledgerURL else {
            throw CaptureDeliveryUsageStoreError.storageUnavailable
        }
        try ensureParentDirectory(for: ledgerURL)

        let token = UUID()
        let result = try coordinator.coordinateWriting(at: ledgerURL) { coordinatedURL in
            var ledger = try loadReconciledLedger(from: coordinatedURL)
            if ledger.committedRequestIDs.contains(request.id) {
                try persist(ledger, to: coordinatedURL)
                return (CaptureDeliveryReservation.alreadyCounted(requestID: request.id), ledger)
            }

            let requestAlreadyReserved = ledger.reservationTokensByRequestID[request.id]?.isEmpty == false
            if !requestAlreadyReserved,
               ledger.successfulCaptureCount + ledger.reservedCaptureSlots >= freeCaptureLimit {
                throw CaptureDeliveryQuotaError.limitReached(limit: freeCaptureLimit)
            }

            ledger.reservationTokensByRequestID[request.id, default: []].insert(token)
            try persist(ledger, to: coordinatedURL)
            return (
                CaptureDeliveryReservation.reserved(requestID: request.id, token: token),
                ledger
            )
        }
        mirrorSuccessfulCount(result.1.successfulCaptureCount)
        return result.0
    }

    public func commit(_ reservation: CaptureDeliveryReservation) async throws {
        guard case .reserved(let requestID, _) = reservation else { return }
        guard let ledgerURL else {
            throw CaptureDeliveryUsageStoreError.storageUnavailable
        }
        try ensureParentDirectory(for: ledgerURL)

        let successfulCount = try coordinator.coordinateWriting(at: ledgerURL) { coordinatedURL in
            var ledger = try loadReconciledLedger(from: coordinatedURL)
            if !ledger.committedRequestIDs.contains(requestID) {
                ledger.committedRequestIDs.insert(requestID)
            }
            ledger.reservationTokensByRequestID.removeValue(forKey: requestID)
            try persist(ledger, to: coordinatedURL)
            return ledger.successfulCaptureCount
        }
        mirrorSuccessfulCount(successfulCount)
    }

    public func release(_ reservation: CaptureDeliveryReservation) async {
        guard case .reserved(let requestID, let token) = reservation,
              let ledgerURL else { return }
        do {
            try ensureParentDirectory(for: ledgerURL)
            let successfulCount = try coordinator.coordinateWriting(at: ledgerURL) { coordinatedURL in
                var ledger = try loadReconciledLedger(from: coordinatedURL)
                ledger.reservationTokensByRequestID[requestID]?.remove(token)
                if ledger.reservationTokensByRequestID[requestID]?.isEmpty == true {
                    ledger.reservationTokensByRequestID.removeValue(forKey: requestID)
                }
                try persist(ledger, to: coordinatedURL)
                return ledger.successfulCaptureCount
            }
            mirrorSuccessfulCount(successfulCount)
        } catch {
            // A conservative leaked reservation is safer than opening a slot
            // after an uncertain cross-process write. The same request ID can
            // still reserve again and commit all of its tokens after retry.
        }
    }

    public func snapshot() throws -> CaptureDeliveryUsageSnapshot {
        guard let ledgerURL else {
            return CaptureDeliveryUsageSnapshot(
                successfulCapturesUsed: 0,
                reservedCaptureSlots: 0,
                freeCaptureLimit: freeCaptureLimit
            )
        }
        try ensureParentDirectory(for: ledgerURL)
        let ledger = try coordinator.coordinateWriting(at: ledgerURL) { coordinatedURL in
            let ledger = try loadReconciledLedger(from: coordinatedURL)
            try persist(ledger, to: coordinatedURL)
            return ledger
        }
        mirrorSuccessfulCount(ledger.successfulCaptureCount)
        return CaptureDeliveryUsageSnapshot(
            successfulCapturesUsed: ledger.successfulCaptureCount,
            reservedCaptureSlots: ledger.reservedCaptureSlots,
            freeCaptureLimit: freeCaptureLimit
        )
    }

    private func loadReconciledLedger(from url: URL) throws -> CaptureUsageLedger {
        guard fileManager.fileExists(atPath: url.path) else {
            return CaptureUsageLedger()
        }
        do {
            let ledger = try decoder.decode(CaptureUsageLedger.self, from: Data(contentsOf: url))
            guard ledger.schemaVersion == CaptureUsageLedger.currentSchemaVersion else {
                throw CaptureDeliveryUsageStoreError.unsupportedSchemaVersion(ledger.schemaVersion)
            }
            return ledger
        } catch let error as CaptureDeliveryUsageStoreError {
            throw error
        } catch {
            try quarantineCorruptLedger(at: url)
            return CaptureUsageLedger()
        }
    }

    private func persist(_ ledger: CaptureUsageLedger, to url: URL) throws {
        try encoder.encode(ledger).write(to: url, options: .atomic)
    }

    private func ensureParentDirectory(for url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func quarantineCorruptLedger(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let quarantineURL = url.deletingLastPathComponent().appendingPathComponent(
            "capture-usage-corrupt-\(UUID().uuidString.lowercased()).json"
        )
        try fileManager.moveItem(at: url, to: quarantineURL)
    }
}

/// The only production Capture pipeline. Core's `.shared` pipeline remains
/// deliberately unmetered for isolated framework clients and tests.
public enum AppCapturePipeline {
    public static let shared = CapturePipeline(
        deliveryAccounting: CaptureDeliveryUsageStore.shared
    )
}
