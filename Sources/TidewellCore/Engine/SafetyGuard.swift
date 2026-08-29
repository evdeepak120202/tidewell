import Foundation

/// Why a candidate was left alone.
///
/// Every skip is nameable, because "it didn't move my file" needs an answer the user
/// can read in the activity log.
public enum SkipReason: String, Codable, Sendable {
    case isDirectory        = "Directory — Tidewell only moves files"
    case isPackage          = "App or bundle — treated as a directory"
    case isSymlink          = "Symlink or alias"
    case isHidden           = "Hidden file"
    case isPartialDownload  = "Still downloading"
    case isUnstable         = "Still being written"
    case isUnreadable       = "Not readable"
    case isNotWritable      = "No permission to move it"
    case isLocked           = "Locked file"
    case alreadyFiled       = "Already in its destination"
    case noDestination      = "No destination for this file"
    case excludedByRule     = "Excluded by a rule"
    case tooYoung           = "Waiting for the delay to pass"
    case duplicate          = "Byte-identical copy already filed"
    case destinationExists  = "A different file is already there"
}

/// The verdict for one candidate file.
public enum MoveDecision: Sendable {
    case move(to: URL)
    case skip(SkipReason)
}

/// Filesystem preconditions that must hold before Tidewell will touch anything.
///
/// This type is the reason the app is safe to leave running. It is pure: it inspects
/// and decides, and has no way to change anything on disk. The engine that *can*
/// change things (`FileMover`) refuses to act without a `.move` verdict from here.
public struct SafetyGuard: Sendable {

    /// Extensions browsers and download managers use for partial files. Moving one of
    /// these mid-flight is how an organiser corrupts a download.
    public static let partialExtensions: Set<String> = [
        "crdownload", "part", "partial", "download", "opdownload",
        "!ut", "!qb", "aria2", "tmp", "temp", "filepart",
    ]

    /// Names that are never candidates regardless of extension.
    public static let reservedNames: Set<String> = [
        ".DS_Store", ".localized", "Icon\r", ".Trashes", ".Spotlight-V100", ".fseventsd",
    ]

    /// Roots too dangerous to organise, whatever the user picks in the panel.
    ///
    /// Reorganising a home directory or a volume root would scatter dotfiles and
    /// application support data; there is no good reason to allow it.
    public static func isForbiddenRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let forbidden = [
            "/", "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
            "/private", "/Volumes", "/opt", "/etc", "/var", home,
        ]
        if forbidden.contains(path) { return true }
        // Any volume root, e.g. /Volumes/Backup
        if path.hasPrefix("/Volumes/"), path.components(separatedBy: "/").count <= 3 { return true }
        return false
    }

    public init() {}

    /// Decide what should happen to `url`.
    ///
    /// `destination` is supplied by the caller (the rule engine picked it); this
    /// method's job is to veto it. Returning `.move` is a statement that every
    /// precondition below held at the moment of the check.
    public func decide(
        for url: URL,
        proposedDestination destination: URL?,
        stability: StabilityGate.Verdict,
        fileManager: FileManager = .default
    ) -> MoveDecision {

        let name = url.lastPathComponent

        // 1. Hidden and system files are never candidates.
        if name.hasPrefix("."), !Self.reservedNames.contains(name) { return .skip(.isHidden) }
        if Self.reservedNames.contains(name) { return .skip(.isHidden) }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isAliasFileKey,
            .isReadableKey, .isWritableKey, .isUserImmutableKey, .isSystemImmutableKey,
            .isHiddenKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return .skip(.isUnreadable)
        }

        // 2. Files only. Directories, app bundles and packages are never touched —
        //    this is the guard that stops the app swallowing its own destinations.
        if values.isDirectory == true { return .skip(.isDirectory) }
        if values.isPackage == true { return .skip(.isPackage) }

        // 3. Links are left where they are; moving one silently rewrites what a
        //    relative target resolves to.
        if values.isSymbolicLink == true || values.isAliasFile == true { return .skip(.isSymlink) }

        if values.isHidden == true { return .skip(.isHidden) }
        if values.isReadable == false { return .skip(.isUnreadable) }
        if values.isWritable == false { return .skip(.isNotWritable) }
        if values.isUserImmutable == true || values.isSystemImmutable == true {
            return .skip(.isLocked)
        }

        // 4. Partial downloads, by extension and by the stability sampler.
        if Self.partialExtensions.contains(url.pathExtension.lowercased()) {
            return .skip(.isPartialDownload)
        }
        switch stability {
        case .settled:  break
        case .changing: return .skip(.isUnstable)
        case .vanished: return .skip(.isUnreadable)
        }

        // 5. A destination the rules could not produce means "leave it".
        guard let destination else { return .skip(.noDestination) }

        // 6. Already where it belongs.
        if destination.standardizedFileURL == url.standardizedFileURL { return .skip(.alreadyFiled) }

        // 7. Never overwrite. The caller is expected to have uniquified the name; if
        //    something is still in the way, refuse rather than replace.
        if fileManager.fileExists(atPath: destination.path) { return .skip(.destinationExists) }

        return .move(to: destination)
    }
}
