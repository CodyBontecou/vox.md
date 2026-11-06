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
        let preferred = ProcessInfo.processInfo.arguments.contains("-VoxAdaptiveSeedInbox") ? "Inbox" : "Meeting Notes"
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
            viewModel.draft.text = "# Project sync\n- [ ] Review final designs\n- [ ] Loop in design before Friday\n\nDecision: ship routing first and keep the composer calm."
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
            let samples: [(String, Date, String)] = [
                ("Meeting Notes", at(16, 10, daysAgo: 1), "# Design crit\nKeyboard picker needs bigger targets"),
                ("Tasks", at(18, 30, daysAgo: 1), "- [ ] Renew passport\n- [ ] Call the dentist\n- [ ] Order printer ink"),
                ("Journal", at(7, 55), "Morning pages\nSlept well. Want to keep the walk before work."),
                ("Inbox", at(9, 18), "Book recs from Sam\nThe Overstory, then anything by Le Guin"),
                ("Meeting Notes", at(10, 42), "# Project sync\n- [ ] Review final designs\n- [ ] Loop in design before Friday\n\nDecision: ship routing first and keep the composer calm."),
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
                guard let index = library.destinations.firstIndex(where: { $0.name == "Tasks" }) else { return }
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
#endif
