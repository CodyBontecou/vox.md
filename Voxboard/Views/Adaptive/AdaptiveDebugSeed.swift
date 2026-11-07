import Foundation
import VoxboardShared

#if DEBUG
/// DEBUG only. `-VoxAdaptiveSeedDemo` installs the four starter routes into a
/// local "Vox Notes" folder in the app's Documents (once) and fills the draft
/// with sample text, so simulator screenshots show real route steps and a
/// "WILL WRITE" preview without the folder picker.
@MainActor
enum AdaptiveDebugSeed {
    private static let argument = "-VoxAdaptiveSeedDemo"
    private static let seededKey = "vox.debug.adaptiveSeedDemo.v1"

    static let suppressesAutofocus = ProcessInfo.processInfo.arguments.contains("-VoxAdaptiveNoAutofocus")

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static func applyIfRequested(to viewModel: QuickCaptureViewModel) async {
        guard isRequested else { return }
        await apply(to: viewModel)
    }

    /// The seed itself, also used directly by hosted snapshot tests.
    static func apply(to viewModel: QuickCaptureViewModel, settleDelay: Duration = .seconds(2)) async {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: seededKey) {
            do {
                let documents = try FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
                )
                let folder = documents.appendingPathComponent("Vox Notes", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let tasks = folder.appendingPathComponent("Tasks.md")
                if !FileManager.default.fileExists(atPath: tasks.path) {
                    try "## Today\n".write(to: tasks, atomically: true, encoding: .utf8)
                }
                let vault = try VoxVaultStore.make(from: folder)
                VoxVaultStore.save(vault)
                try await StarterRouteInstaller.install(StarterRoute.allCases, in: vault)
                defaults.set(true, forKey: seededKey)
            } catch {
                print("[AdaptiveDebugSeed] \(error)")
            }
        }
        // Let the composer finish restoring its saved draft first.
        try? await Task.sleep(for: settleDelay)
        viewModel.refreshVoxProfiles()
        await viewModel.refreshLibrary()
        // Starter route names are localized, so look them up through StarterRoute.
        let preferred = ProcessInfo.processInfo.arguments.contains("-VoxAdaptiveSeedInbox")
            ? StarterRoute.inbox.name : StarterRoute.meetingNotes.name
        if let route = viewModel.voxProfiles.first(where: { $0.name == preferred }) {
            _ = viewModel.selectVox(route.id)
        }
        if ProcessInfo.processInfo.arguments.contains("-VoxAdaptiveSeedLibrary") {
            await seedLibrary(viewModel: viewModel)
        }
        if ProcessInfo.processInfo.arguments.contains("-VoxDebugSeedHeadingMissing") {
            await seedHeadingNotFound(viewModel: viewModel)
        }
        if viewModel.draft.text.isEmpty {
            viewModel.draft.text = SeedSamples.current.draft
        }
    }

    private static let seededLibraryKey = "vox.debug.adaptiveSeedLibrary.v1"

    /// DEBUG only. `-VoxAdaptiveSeedLibrary` (or a hosted snapshot test):
    /// delivers the five DuoInnerLibrary captures through the real inbox and
    /// pipeline into the seeded routes, once per install.
    static func seedLibrary(viewModel: QuickCaptureViewModel) async {
        guard !UserDefaults.standard.bool(forKey: seededLibraryKey),
              let root = AppConstants.captureDirectoryURL,
              let libraryURL = AppConstants.captureLibraryURL else { return }
        do {
            let library = try await CaptureLibraryStore(fileURL: libraryURL).load()
            func route(_ name: String) -> UUID? {
                library.destinations.first(where: { $0.name == name })?.id
            }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            func at(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
                let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            }
            let text = SeedSamples.current
            let samples: [(String, Date, String)] = [
                (StarterRoute.meetingNotes.name, at(16, 10, daysAgo: 1), text.designCrit),
                (StarterRoute.tasks.name, at(18, 30, daysAgo: 1), text.tasks),
                (StarterRoute.journal.name, at(7, 55), text.morningPages),
                (StarterRoute.inbox.name, at(9, 18), text.bookRecs),
                (StarterRoute.meetingNotes.name, at(10, 42), text.draft),
            ]
            let inbox = CaptureInbox(rootDirectoryURL: root)
            for (name, date, text) in samples {
                guard let destinationID = route(name) else { continue }
                try await inbox.enqueue(CaptureRequest(
                    createdAt: date,
                    source: .app,
                    destinationID: destinationID,
                    payloads: [.text(text)]
                ))
            }
            await viewModel.processPendingInbox()
            await viewModel.refreshLibrary()
            viewModel.errorMessage = nil
            UserDefaults.standard.set(true, forKey: seededLibraryKey)
        } catch {
            print("[AdaptiveDebugSeed] library: \(error)")
        }
    }

    /// DEBUG only. `-VoxDebugSeedHeadingMissing`: the Tasks route stops
    /// creating its "## Today" heading, Tasks.md loses that heading, and a
    /// shared three-task capture for Tasks is queued and drained — so
    /// Activity shows the "Heading not found" delivery failure (DeliveryFailed
    /// board). Runs once per launch; relaunch without the flag to stop.
    private static func seedHeadingNotFound(viewModel: QuickCaptureViewModel) async {
        guard let root = AppConstants.captureDirectoryURL,
              let libraryURL = AppConstants.captureLibraryURL else { return }
        do {
            let store = CaptureLibraryStore(fileURL: libraryURL)
            var tasksID: UUID?
            _ = try await store.update { library in
                guard let index = library.destinations.firstIndex(where: { $0.name == StarterRoute.tasks.name }) else { return }
                library.destinations[index].placement = .beneathHeading(
                    CaptureHeadingSelector(title: "Today", level: 2),
                    missingHeadingBehavior: .fail,
                    headingPosition: .top
                )
                tasksID = library.destinations[index].id
            }
            guard let tasksID else { return }
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            try "# Tasks\n\n- [x] Old item\n".write(
                to: documents.appendingPathComponent("Vox Notes/Tasks.md"),
                atomically: true,
                encoding: .utf8
            )
            let request = CaptureRequest(
                source: .shareExtension,
                destinationID: tasksID,
                payloads: [.text("- [ ] Renew passport\n- [ ] Call the dentist\n- [ ] Order printer ink")]
            )
            try await CaptureInbox(rootDirectoryURL: root).enqueue(request)
            await viewModel.processPendingInbox()
            viewModel.errorMessage = nil
        } catch {
            print("[AdaptiveDebugSeed] heading-missing: \(error)")
        }
    }
}
/// DEBUG only. Sample note text for the seed. English by default; App Store
/// screenshot runs pass translated text as JSON through `-VoxSeedSamples`
/// (keys: draft, designCrit, tasks, morningPages, bookRecs,
/// liveFinalized, liveVolatile), so every
/// language shows the same notes as the localized store frames.
struct SeedSamples: Decodable {
    var draft = "# Project sync\n- [ ] Review final designs\n- [ ] Loop in design before Friday\n\nDecision: ship routing first and keep the composer calm."
    var designCrit = "# Design crit\nKeyboard picker needs bigger targets"
    var tasks = "- [ ] Renew passport\n- [ ] Call the dentist\n- [ ] Order printer ink"
    var morningPages = "Morning pages\nSlept well. Want to keep the walk before work."
    var bookRecs = "Book recs from Sam\nThe Overstory, then anything by Le Guin"
    var liveFinalized: String?
    var liveVolatile: String?

    static let current: SeedSamples = {
        var samples = SeedSamples()
        // Read the raw launch argument: UserDefaults parses a value starting with "{"
        // as a property list, so JSON never arrives through it.
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VoxSeedSamples"),
              arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return samples }
        samples.draft = decoded["draft"] ?? samples.draft
        samples.designCrit = decoded["designCrit"] ?? samples.designCrit
        samples.tasks = decoded["tasks"] ?? samples.tasks
        samples.morningPages = decoded["morningPages"] ?? samples.morningPages
        samples.bookRecs = decoded["bookRecs"] ?? samples.bookRecs
        samples.liveFinalized = decoded["liveFinalized"]
        samples.liveVolatile = decoded["liveVolatile"]
        return samples
    }()
}
/// DEBUG only. `-VoxScreenshotReset` wipes the app-group data (drafts, library,
/// routes, shared defaults), the local "Vox Notes" folder and the seed markers before
/// anything loads. Reinstalling does not clear the app group, so without this a
/// screenshot run in one language restores the previous language's notes.
enum ScreenshotReset {
    static func applyIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-VoxScreenshotReset") else { return }
        let fileManager = FileManager.default
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier),
           let items = try? fileManager.contentsOfDirectory(at: group, includingPropertiesForKeys: nil) {
            // Library/Preferences holds the shared defaults, cleared below. Hidden files
            // include the container manager's metadata: removing it drops the container.
            for item in items where item.lastPathComponent != "Library" && !item.lastPathComponent.hasPrefix(".") {
                try? fileManager.removeItem(at: item)
            }
        }
        UserDefaults(suiteName: AppConstants.appGroupIdentifier)?
            .removePersistentDomain(forName: AppConstants.appGroupIdentifier)
        if let documents = try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            try? fileManager.removeItem(at: documents.appendingPathComponent("Vox Notes", isDirectory: true))
        }
        for key in ["vox.debug.adaptiveSeedDemo.v1", "vox.debug.adaptiveSeedLibrary.v1"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
#endif
