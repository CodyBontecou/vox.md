import Foundation
@testable import VoxboardShared

/// Points the preset write lock at a temporary directory so preset tests
/// never depend on (or write into) the real App Group container, which isn't
/// writable for `swift test` in sandboxed environments.
enum CapturePresetTestLock {
    static let directory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxboardSharedTests-preset-lock", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func install() {
        CapturePresetStore.writeLockDirectoryOverride = directory
    }
}
