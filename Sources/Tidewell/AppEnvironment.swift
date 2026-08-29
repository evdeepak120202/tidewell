import AppKit
import Observation
import SwiftUI
import TidewellCore
import UserNotifications

/// Owns the settings, the watcher and the organiser, and is the only place they meet.
///
/// Nothing here touches `NSApp`. The object is constructed from `TidewellApp.init`,
/// and `NSApp` does not exist yet at that point — reading it there traps at launch,
/// which is why the watcher is started from `applicationDidFinishLaunching` instead.
@MainActor
@Observable
public final class AppEnvironment {

    /// The one instance. The app delegate and the SwiftUI scenes must reach the
    /// same object, and the delegate cannot be handed it from a view: the main
    /// window is `.suppressed` at launch, so any wiring that waits for `onAppear`
    /// never runs and the watcher never starts.
    ///
    /// Safe as a static because nothing in `init` touches `NSApp` — which does not
    /// exist yet when this is first read.
    public static let shared = AppEnvironment()

    public let settings = Settings()
    // Not observed: these are engines, not view state, and `@Observable` cannot track
    // (or lazily initialise) them anyway.
    @ObservationIgnored private let intelligence = IntelligenceEngine()
    @ObservationIgnored private let organizer: Organizer
    @ObservationIgnored private let sweeper = ArchiveSweeper()

    /// Holds security-scoped access open for the app's lifetime.
    @ObservationIgnored private let access = FolderAccess()
    private let watcher = FolderWatcher()

    /// Folders with a pass in flight, so the UI can show progress and the watcher can
    /// avoid stacking runs on the same folder.
    public private(set) var busyFolders: Set<UUID> = []

    public private(set) var lastRunSummary: String?

    /// One pending re-check per folder, for files held back by the arrival delay.
    private var retryTasks: [UUID: Task<Void, Never>] = [:]

    public init() {
        // The organiser holds the intelligence engine so the classification cache is
        // shared across every folder and every run.
        organizer = Organizer(intelligence: intelligence)
    }

    // MARK: Lifecycle

    /// Called from `applicationDidFinishLaunching`, never from `init`.
    public func start() {
        // Reopen every watched folder before the watcher is built. In the sandbox a stored
        // URL alone grants nothing — the bookmark is the permission, and it has to be
        // resolved and opened first or FSEvents silently watches nothing.
        Task { await restoreFolderAccess() }

        watcher.onChange = { [weak self] changed in
            guard let self else { return }
            for url in changed { self.handleChange(at: url) }
        }
        refreshWatchSet()
        Task { await requestNotificationAuthorizationIfNeeded() }
        Task { await intelligence.primeCache(settings.classificationCache) }
    }

    /// Resolve stored bookmarks and hold access open.
    ///
    /// A stale bookmark is re-minted and written straight back: one that resolves but is
    /// not refreshed keeps working for this launch and then stops, which looks like the
    /// app breaking itself overnight.
    private func restoreFolderAccess() async {
        for index in settings.folders.indices {
            let folder = settings.folders[index]
            guard let bookmark = folder.bookmark else {
                // Added before sandboxing, or created while running unsandboxed. Nothing
                // to resolve; the plain URL is all there is.
                continue
            }
            do {
                let (url, refreshed) = try FolderAccess.resolve(bookmark)
                await access.begin(url)
                settings.folders[index].url = url
                if let refreshed { settings.folders[index].bookmark = refreshed }
            } catch {
                // Leave the folder in the list rather than dropping it: the user should
                // see it and be able to re-grant, not find it silently gone.
                settings.folders[index].isAutoEnabled = false
            }
        }
        refreshWatchSet()
    }

    /// Bring the watch set in line with the current settings.
    public func refreshWatchSet() {
        guard settings.isAutoEnabled else { watcher.stop(); return }
        let active = settings.folders.filter(\.isAutoEnabled).map(\.url)
        watcher.watch(active)
    }

    /// Persist synchronously. Called from `applicationWillTerminate`.
    ///
    /// Deliberately not async: holding termination open with `.terminateLater` and
    /// awaiting a flush deadlocks AppKit, because the main actor never gets scheduled
    /// again once the run loop enters its restricted termination mode.
    /// Availability is read live rather than cached: the user can enable Apple
    /// Intelligence in System Settings while Tidewell is running.
    public var intelligenceAvailability: IntelligenceAvailability { .current }

    /// Turning the feature off purges everything it produced. No residue, no half state.
    public func setIntelligenceEnabled(_ enabled: Bool) {
        settings.intelligenceEnabled = enabled
        guard !enabled else { return }
        settings.classificationCache = [:]
        for index in settings.folders.indices { settings.folders[index].usesIntelligence = false }
        Task { await intelligence.purgeCache() }
    }

    public func purgeClassificationCache() {
        settings.classificationCache = [:]
        Task { await intelligence.purgeCache() }
    }

    public func flushForTermination() {
        cancelRetries()
        watcher.stop()
        settings.save()
        // Balance every startAccessingSecurityScopedResource. Unbalanced access leaks
        // kernel resources for the life of the process.
        Task { await access.releaseAll() }
    }

    /// Add a folder the user just chose in a panel, minting its bookmark.
    ///
    /// The bookmark has to be created **now**, while the picker's grant is still live —
    /// minting it later, from a stored path, fails inside the sandbox.
    public func addPickedFolder(_ url: URL) -> String? {
        let standardized = url.standardizedFileURL
        if SafetyGuard.isForbiddenRoot(standardized) {
            return "\(standardized.lastPathComponent) is a system or home root — Tidewell will not organise it."
        }
        guard !settings.folders.contains(where: {
            $0.url.standardizedFileURL == standardized
        }) else { return "\(standardized.lastPathComponent) is already being watched." }

        let bookmark = try? FolderAccess.makeBookmark(for: standardized)
        if bookmark == nil, FolderAccess.isSandboxed {
            return "Couldn't keep access to \(standardized.lastPathComponent). Try choosing it again."
        }

        var folder = WatchedFolder(url: standardized, bookmark: bookmark)
        folder.usesIntelligence = false
        settings.folders.append(folder)
        Task { await access.begin(standardized) }
        refreshWatchSet()
        return nil
    }

    // MARK: Running

    private func handleChange(at folderURL: URL) {
        guard settings.isAutoEnabled,
              let folder = settings.folders.first(where: {
                  $0.url.standardizedFileURL == folderURL.standardizedFileURL
              }),
              folder.isAutoEnabled
        else { return }
        Task { await organize(folder, trigger: .automatic) }
    }

    /// File one folder.
    @discardableResult
    public func organize(_ folder: WatchedFolder, trigger: OrganizeRun.Trigger) async -> OrganizeRun? {
        guard !busyFolders.contains(folder.id) else { return nil }
        busyFolders.insert(folder.id)
        defer { busyFolders.remove(folder.id) }

        let (run, retryAfter) = await organizer.run(folder, trigger: trigger)
        settings.record(run)
        // Persist whatever the run learned, so a restart does not re-read documents.
        if settings.intelligenceEnabled {
            settings.classificationCache = await intelligence.exportCache()
        }

        // Files skipped only because their delay had not elapsed would otherwise sit
        // there forever: the arrival already fired its filesystem event, and nothing
        // else is coming. Book the follow-up pass now.
        scheduleRetry(for: folder, after: retryAfter)

        // The archive is time-based, so it has no filesystem event of its own to
        // hang off. Riding along with a normal pass — at most once a day — avoids
        // both a timer and a sweep on every burst.
        await archiveIfDue(folder)

        if !run.moved.isEmpty {
            lastRunSummary = "\(run.summary) in \(folder.displayName)"
            if settings.playsSoundOnFile { NSSound(named: "Pop")?.play() }
            if settings.notifiesOnFile { notify(run, folder: folder) }
        } else if trigger == .manual {
            lastRunSummary = "Nothing to file in \(folder.displayName)"
        }
        return run
    }

    /// File every enabled folder. Backs the menu bar's Organize button.
    public func organizeAll(trigger: OrganizeRun.Trigger = .manual) async {
        for folder in settings.folders {
            await organize(folder, trigger: trigger)
        }
    }

    /// Run the archive sweep if a day has passed since the last one.
    private func archiveIfDue(_ folder: WatchedFolder) async {
        guard folder.archiveAfterDays > 0 else { return }
        if let last = folder.lastArchiveSweep,
           Date().timeIntervalSince(last) < 86_400 { return }
        await archiveNow(folder)
    }

    /// Sweep stale filed files into the archive. Also the manual button.
    @discardableResult
    public func archiveNow(_ folder: WatchedFolder) async -> OrganizeRun {
        let run = sweeper.run(folder)
        settings.record(run)

        var updated = folder
        updated.lastArchiveSweep = Date()
        update(updated)

        if !run.moved.isEmpty { lastRunSummary = "\(run.summary) in \(folder.displayName)" }
        return run
    }

    /// What the sweep would move, without moving it.
    public func archivePreview(_ folder: WatchedFolder) -> [MovedFile] {
        sweeper.plan(for: folder)
    }

    /// Preview a folder without moving anything.
    public func preview(_ folder: WatchedFolder) async -> OrganizePlan {
        await organizer.plan(for: folder)
    }

    /// Re-run a folder once its youngest deferred file becomes eligible.
    private func scheduleRetry(for folder: WatchedFolder, after delay: Duration?) {
        retryTasks[folder.id]?.cancel()
        retryTasks[folder.id] = nil

        guard let delay, settings.isAutoEnabled, folder.isAutoEnabled else { return }

        retryTasks[folder.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Re-read the folder: it may have been edited or removed while waiting.
            guard let current = self.settings.folders.first(where: { $0.id == folder.id }),
                  current.isAutoEnabled, self.settings.isAutoEnabled
            else { return }
            await self.organize(current, trigger: .automatic)
        }
    }

    /// Reverse a previous run.
    /// Cancel every pending re-check. Called on quit.
    private func cancelRetries() {
        for task in retryTasks.values { task.cancel() }
        retryTasks.removeAll()
    }

    public func undo(_ run: OrganizeRun) async {
        let result = await organizer.undo(run)
        settings.markUndone(run.id)
        settings.record(result)
        lastRunSummary = result.moved.isEmpty
            ? "Nothing to put back"
            : "Put \(result.moved.count) back"
    }

    // MARK: Folders

    /// Add a folder, refusing roots that must never be reorganised.
    public func addFolder(_ url: URL) -> String? {
        let standardized = url.standardizedFileURL

        if SafetyGuard.isForbiddenRoot(standardized) {
            return "\(standardized.lastPathComponent) is a system or home root — Tidewell will not organise it."
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return "That is not a folder." }

        guard !settings.folders.contains(where: { $0.url.standardizedFileURL == standardized }) else {
            return "\(standardized.lastPathComponent) is already being watched."
        }

        settings.folders.append(WatchedFolder(url: standardized))
        refreshWatchSet()
        return nil
    }

    /// Add a folder that already carries its settings, as the wizard produces.
    ///
    /// Separate from `addFolder(_:)` because that one builds a default configuration;
    /// here the caller has already decided the scheme, rules and housekeeping.
    public func addConfiguredFolder(_ folder: WatchedFolder) {
        guard !SafetyGuard.isForbiddenRoot(folder.url) else { return }
        guard !settings.folders.contains(where: {
            $0.url.standardizedFileURL == folder.url.standardizedFileURL
        }) else { return }
        settings.folders.append(folder)
    }

    public func removeFolder(_ id: UUID) {
        settings.folders.removeAll { $0.id == id }
        refreshWatchSet()
    }

    public func update(_ folder: WatchedFolder) {
        guard let index = settings.folders.firstIndex(where: { $0.id == folder.id }) else { return }
        settings.folders[index] = folder
        refreshWatchSet()
    }

    // MARK: Notifications

    private func requestNotificationAuthorizationIfNeeded() async {
        guard settings.notifiesOnFile else { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert])
    }

    private func notify(_ run: OrganizeRun, folder: WatchedFolder) {
        let content = UNMutableNotificationContent()
        content.title = folder.displayName
        content.body = run.summary
        let request = UNNotificationRequest(
            identifier: run.id.uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
