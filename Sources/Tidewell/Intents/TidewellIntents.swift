import AppIntents
import Foundation
import TidewellCore

// Shortcuts support, and the deliberate alternative to Hazel's "run a shell script on
// arrival". A folder-watching background agent that can execute arbitrary shell is a
// permanent remote-code-execution surface; exposing safe, named verbs instead lets the
// user compose automation in Shortcuts without Tidewell ever running their code.
//
// Every intent goes through the same engine and the same `SafetyGuard` as the UI. There is
// no privileged path here.

/// A folder Tidewell already watches. Users pick from these rather than typing a path, so
/// an intent can never be pointed at somewhere the app was not configured for.
struct WatchedFolderEntity: AppEntity {
    let id: UUID
    let name: String
    let path: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Watched Folder" }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(path)")
    }
    static let defaultQuery = WatchedFolderQuery()
}

struct WatchedFolderQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [WatchedFolderEntity] {
        AppEnvironment.shared.settings.folders
            .filter { identifiers.contains($0.id) }
            .map { WatchedFolderEntity(id: $0.id, name: $0.displayName, path: $0.url.path) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WatchedFolderEntity] {
        AppEnvironment.shared.settings.folders
            .map { WatchedFolderEntity(id: $0.id, name: $0.displayName, path: $0.url.path) }
    }
}

/// File a folder now.
struct OrganizeFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Organize Folder"
    static let description = IntentDescription(
        "Files the loose files in a watched folder. Never deletes anything, and the run can be undone afterwards."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Folder")
    var folder: WatchedFolderEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let env = AppEnvironment.shared
        guard let watched = env.settings.folders.first(where: { $0.id == folder.id }) else {
            throw IntentError.folderNoLongerWatched
        }
        let run = await env.organize(watched, trigger: .manual)
        return .result(value: run?.summary ?? "Nothing to file")
    }
}

/// Say what a run would do, without doing it.
struct PreviewFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Preview Folder"
    static let description = IntentDescription("Reports what Tidewell would file in a folder. Moves nothing.")
    static let openAppWhenRun = false

    @Parameter(title: "Folder")
    var folder: WatchedFolderEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let env = AppEnvironment.shared
        guard let watched = env.settings.folders.first(where: { $0.id == folder.id }) else {
            throw IntentError.folderNoLongerWatched
        }
        let plan = await env.preview(watched)
        let text = plan.moves.isEmpty
            ? "Nothing to file"
            : "\(plan.moves.count) file\(plan.moves.count == 1 ? "" : "s") would move"
        return .result(value: text)
    }
}

/// Reverse the most recent run.
struct UndoLastRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Last Organize"
    static let description = IntentDescription("Puts back everything the most recent run moved.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let env = AppEnvironment.shared
        guard let run = env.settings.mostRecentUndoable else {
            return .result(value: "Nothing to undo")
        }
        await env.undo(run)
        return .result(value: "Put back \(run.moved.count) file\(run.moved.count == 1 ? "" : "s")")
    }
}

/// Sweep stale files into the archive.
struct ArchiveOldFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Archive Old Files"
    static let description = IntentDescription(
        "Moves filed files past their age limit into an Archive folder. A move, never a delete."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Folder")
    var folder: WatchedFolderEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let env = AppEnvironment.shared
        guard let watched = env.settings.folders.first(where: { $0.id == folder.id }) else {
            throw IntentError.folderNoLongerWatched
        }
        guard watched.archiveAfterDays > 0 else {
            return .result(value: "Archiving is off for this folder")
        }
        let run = await env.archiveNow(watched)
        return .result(value: run.summary)
    }
}

/// Turn automatic filing on or off.
struct SetAutomaticFilingIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Automatic Filing"
    static let description = IntentDescription("Turns Tidewell's automatic filing on or off.")
    static let openAppWhenRun = false

    @Parameter(title: "Enabled")
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let env = AppEnvironment.shared
        env.settings.isAutoEnabled = enabled
        env.refreshWatchSet()
        return .result(value: enabled ? "Automatic filing on" : "Automatic filing off")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case folderNoLongerWatched

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .folderNoLongerWatched:
            "That folder is no longer watched by Tidewell."
        }
    }
}

/// Ready-made shortcuts, so the verbs are discoverable without building one first.
struct TidewellShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UndoLastRunIntent(),
            phrases: ["Undo the last \(.applicationName) organize"],
            shortTitle: "Undo Last Organize",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: SetAutomaticFilingIntent(),
            phrases: ["Set \(.applicationName) automatic filing"],
            shortTitle: "Automatic Filing",
            systemImageName: "switch.2"
        )
    }
}
