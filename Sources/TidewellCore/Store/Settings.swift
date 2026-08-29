import Foundation
import Observation

/// Everything the user has configured, and the run journal.
///
/// Persistence is a single JSON file written synchronously. That choice is load
/// bearing: quitting must not hold termination open for an async flush — see the
/// note in `applicationWillTerminate`. A few kilobytes of JSON is microseconds.
@MainActor
@Observable
public final class Settings {

    // MARK: Stored

    public var folders: [WatchedFolder] = [] { didSet { scheduleSave() } }

    /// Master switch. Auto-filing needs this *and* the folder's own toggle.
    public var isAutoEnabled: Bool = true { didSet { scheduleSave() } }

    public var showsMenuBarIcon: Bool = true { didSet { scheduleSave() } }
    public var playsSoundOnFile: Bool = false { didSet { scheduleSave() } }
    public var notifiesOnFile: Bool = true { didSet { scheduleSave() } }

    /// Whether first-run has been completed. Drives whether the wizard is shown.
    public var hasCompletedSetup: Bool = false { didSet { scheduleSave() } }

    /// The style picked during setup, kept so Settings can show it and offer to reapply.
    public var chosenStyle: OrganizingStyle = .tidy { didSet { scheduleSave() } }

    /// Master switch for on-device document classification. **Off unless the user turns
    /// it on.** A folder's own `usesIntelligence` also has to be on; both are required,
    /// so the feature can never arrive enabled by an update.
    public var intelligenceEnabled: Bool = false { didSet { scheduleSave() } }

    /// Cached classifications, keyed by content hash, so the same bytes are never read
    /// twice. Purged when the feature is switched off.
    public var classificationCache: [String: ContentClassification] = [:] {
        didSet { scheduleSave() }
    }

    /// Journal, newest first, capped so the file cannot grow without bound.
    public var runs: [OrganizeRun] = [] { didSet { scheduleSave() } }
    public static let journalLimit = 200

    // MARK: Storage location

    /// `~/Library/Application Support/Tidewell/settings.json`
    public static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tidewell", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }

    private struct Payload: Codable {
        var folders: [WatchedFolder]
        var isAutoEnabled: Bool
        var showsMenuBarIcon: Bool
        var playsSoundOnFile: Bool
        var notifiesOnFile: Bool
        var runs: [OrganizeRun]
        var hasCompletedSetup: Bool?
        var chosenStyle: OrganizingStyle?
        var intelligenceEnabled: Bool?
        var classificationCache: [String: ContentClassification]?
    }

    private var isLoading = false
    private var saveTask: Task<Void, Never>?

    public init() { load() }

    // MARK: Load / save

    /// Set when the settings file existed but could not be read. While true the
    /// store refuses to save, so a decode bug cannot overwrite a good file with an
    /// empty one — which is exactly how a schema change loses every watched folder.
    public private(set) var didFailToLoad = false
    public private(set) var loadFailure: String?

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard let data = try? Data(contentsOf: Self.storeURL) else { return }   // first run

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            apply(payload)
        } catch {
            // Keep the unreadable file next to the original rather than losing it,
            // and refuse to write over it.
            didFailToLoad = true
            loadFailure = String(describing: error)
            let backup = Self.storeURL.deletingPathExtension()
                .appendingPathExtension("unreadable.json")
            try? data.write(to: backup, options: .atomic)
        }
    }

    private func apply(_ payload: Payload) {
        folders = payload.folders
        isAutoEnabled = payload.isAutoEnabled
        showsMenuBarIcon = payload.showsMenuBarIcon
        playsSoundOnFile = payload.playsSoundOnFile
        notifiesOnFile = payload.notifiesOnFile
        runs = payload.runs
        // Optional in the payload so a settings file written before the wizard existed
        // still loads. An existing install with folders has plainly completed setup.
        hasCompletedSetup = payload.hasCompletedSetup ?? !payload.folders.isEmpty
        chosenStyle = payload.chosenStyle ?? .tidy
        // Absent means off. A feature that reads documents must never switch itself on.
        intelligenceEnabled = payload.intelligenceEnabled ?? false
        classificationCache = payload.classificationCache ?? [:]
    }

    /// Coalesce the writes that a slider or a burst of edits would otherwise cause.
    private func scheduleSave() {
        guard !isLoading else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Write now, on the calling thread. Called on quit.
    public func save() {
        // Never clobber a file we could not understand.
        guard !didFailToLoad else { return }
        saveTask?.cancel()
        saveTask = nil
        let payload = Payload(
            folders: folders,
            isAutoEnabled: isAutoEnabled,
            showsMenuBarIcon: showsMenuBarIcon,
            playsSoundOnFile: playsSoundOnFile,
            notifiesOnFile: notifiesOnFile,
            runs: Array(runs.prefix(Self.journalLimit)),
            hasCompletedSetup: hasCompletedSetup,
            chosenStyle: chosenStyle,
            intelligenceEnabled: intelligenceEnabled,
            classificationCache: classificationCache
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        // Atomic so a crash mid-write cannot leave a truncated settings file.
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    // MARK: Journal

    public func record(_ run: OrganizeRun) {
        // An automatic pass that found nothing is not worth a journal entry; it would
        // push real history out of the list every time a folder is touched.
        guard !(run.isEmpty && run.trigger == .automatic) else { return }
        runs.insert(run, at: 0)
        if runs.count > Self.journalLimit { runs.removeLast(runs.count - Self.journalLimit) }
    }

    public func markUndone(_ id: UUID) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].isUndone = true
    }

    public var mostRecentUndoable: OrganizeRun? {
        runs.first { !$0.isUndone && !$0.moved.isEmpty && $0.trigger != .undo }
    }
}
