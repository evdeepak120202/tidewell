import Foundation

/// A named starting point for how a folder gets organised.
///
/// Not a mode: applying a style writes ordinary settings into the folder, which the user
/// can then change freely. The point is to skip the blank page — the reason most people
/// abandon rule-based organisers is that they are asked to design a taxonomy before they
/// get any value.
public enum OrganizingStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case tidy
    case minimal
    case librarian
    case maker
    case creative
    case caretaker

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tidy:      "Tidy"
        case .minimal:   "Minimal"
        case .librarian: "Librarian"
        case .maker:     "Maker"
        case .creative:  "Creative"
        case .caretaker: "Caretaker"
        }
    }

    public var tagline: String {
        switch self {
        case .tidy:      "A folder per kind of file"
        case .minimal:   "Three folders, nothing more"
        case .librarian: "Everything filed by kind and month"
        case .maker:     "Built for code, builds and installers"
        case .creative:  "Photos and video first, by month"
        case .caretaker: "Changes nothing — just duplicates and old files"
        }
    }

    public var detail: String {
        switch self {
        case .tidy:
            "Images, Documents, Archives and the rest. The safe default, and what most "
            + "people mean when they say they want a tidy Downloads folder."
        case .minimal:
            "Everything lands in Media, Documents or Other. For people who find eight "
            + "folders worse than one pile."
        case .librarian:
            "Adds a month folder inside each category, so Documents/2026-08. Worth it "
            + "when a lot arrives and you look things up by roughly when they came in."
        case .maker:
            "Keeps Code, Archives and Installers prominent, files design assets "
            + "separately, and leaves documents alone."
        case .creative:
            "Photos and Video by month, RAW kept apart from JPEG, everything else in a "
            + "short list."
        case .caretaker:
            "Files nothing and moves nothing into categories. Only sets aside identical "
            + "copies and archives what has gone stale. The right choice if your folders "
            + "already work the way you want."
        }
    }

    public var symbolName: String {
        switch self {
        case .tidy:      "square.grid.2x2"
        case .minimal:   "rectangle.3.group"
        case .librarian: "calendar"
        case .maker:     "hammer"
        case .creative:  "camera"
        case .caretaker: "hand.raised"
        }
    }

    /// The folder tree this style produces, for the preview cards in the wizard.
    public var exampleTree: [String] {
        switch self {
        case .tidy:      ["Images", "Documents", "Archives", "Video", "Code", "…"]
        case .minimal:   ["Media", "Documents", "Other"]
        case .librarian: ["Documents/2026-08", "Images/2026-08", "Archives/2026-08"]
        case .maker:     ["Code", "Archives", "Installers", "Design", "Documents"]
        case .creative:  ["Photos/2026-08", "RAW/2026-08", "Video/2026-08", "Documents"]
        case .caretaker: ["Duplicates", "Archive/2026-05"]
        }
    }

    /// Apply the style to a folder, preserving anything the user has already set that the
    /// style has no opinion about.
    ///
    /// Deliberately does not touch `url`, `id`, `isAutoEnabled` or existing name rules:
    /// picking a different style should never silently discard work.
    public func apply(to folder: WatchedFolder) -> WatchedFolder {
        var f = folder
        f.folderNames = [:]
        f.ignoredCategories = []

        switch self {
        case .tidy:
            f.scheme = .category

        case .minimal:
            // Everything collapses onto three names. Two categories sharing a folder
            // name is all "merging" needs to mean.
            f.scheme = .category
            f.folderNames = [
                .images: "Media", .video: "Media", .audio: "Media", .design: "Media",
                .documents: "Documents", .data: "Documents",
                .archives: "Other", .code: "Other", .installers: "Other", .other: "Other",
            ]

        case .librarian:
            f.scheme = .categoryByMonth

        case .maker:
            f.scheme = .category
            f.folderNames = [.data: "Data", .design: "Design"]
            // Documents are usually already where the user wants them on a dev machine.
            f.ignoredCategories = [.documents]

        case .creative:
            f.scheme = .categoryByMonth
            f.folderNames = [.images: "Photos", .design: "Design"]

        case .caretaker:
            // No categorisation at all: every category is ignored, so the only things
            // that move are duplicates and archived files.
            f.scheme = .category
            f.ignoredCategories = Set(FileCategory.allCases)
            f.quarantinesDuplicates = true
            if f.archiveAfterDays == 0 { f.archiveAfterDays = 180 }
        }
        return f
    }

    /// Name rules the style suggests, offered separately so they can be reviewed.
    public var suggestedRules: [NameRule] {
        switch self {
        case .creative:
            // RAW formats are images by type, but photographers almost never want them
            // mixed in with JPEGs.
            [NameRule(pattern: "*.raw", folderName: "RAW"),
             NameRule(pattern: "*.dng", folderName: "RAW"),
             NameRule(pattern: "*.cr2", folderName: "RAW"),
             NameRule(pattern: "*.nef", folderName: "RAW"),
             NameRule(pattern: "*.arw", folderName: "RAW")]
        case .maker:
            [NameRule(pattern: "*.dmg", folderName: "Installers"),
             NameRule(pattern: "*.pkg", folderName: "Installers")]
        default:
            []
        }
    }

    /// Best guess at which style suits what is actually in a folder.
    ///
    /// Used to pre-select a card in the wizard so the common case is one click. A guess,
    /// never a decision — the user always sees which one is selected and why.
    public static func suggestion(forCounts counts: [FileCategory: Int]) -> OrganizingStyle {
        let total = counts.values.reduce(0, +)
        guard total >= 5 else { return .tidy }

        let share = { (c: FileCategory) in Double(counts[c] ?? 0) / Double(total) }
        let media = share(.images) + share(.video) + share(.design)
        let dev = share(.code) + share(.archives) + share(.installers)

        if media > 0.6 { return .creative }
        if dev > 0.5 { return .maker }
        if total > 200 { return .librarian }
        return .tidy
    }
}
