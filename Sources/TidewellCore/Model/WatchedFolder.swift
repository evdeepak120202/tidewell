import Foundation

/// A folder Tidewell is responsible for, and how it should be filed.
///
/// Settings are per folder rather than global. Downloads wants category folders and
/// a screenshot dump wants month folders, and an app that forces one scheme on both
/// is an app you turn off.
public struct WatchedFolder: Codable, Sendable, Identifiable, Hashable {

    // Decoded with defaults so a settings file written before these existed still
    // loads — losing every watched folder on upgrade would be a poor trade for four
    // new options.
    private enum CodingKeys: String, CodingKey {
        case id, url, bookmark, isAutoEnabled, scheme, folderNames, ignoredCategories
        case ignoredExtensions, overrides, minimumAgeSeconds
        case nameRules, rules, quarantinesDuplicates, duplicatesFolderName
        case archiveAfterDays, archiveFolderName, lastArchiveSweep, usesIntelligence
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(URL.self, forKey: .url)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        isAutoEnabled = try c.decodeIfPresent(Bool.self, forKey: .isAutoEnabled) ?? true
        scheme = try c.decodeIfPresent(SortScheme.self, forKey: .scheme) ?? .category
        folderNames = try c.decodeIfPresent([FileCategory: String].self, forKey: .folderNames) ?? [:]
        ignoredCategories = try c.decodeIfPresent(Set<FileCategory>.self, forKey: .ignoredCategories) ?? []
        ignoredExtensions = try c.decodeIfPresent(Set<String>.self, forKey: .ignoredExtensions) ?? []
        overrides = try c.decodeIfPresent([String: FileCategory].self, forKey: .overrides) ?? [:]
        minimumAgeSeconds = try c.decodeIfPresent(Int.self, forKey: .minimumAgeSeconds) ?? 0
        nameRules = try c.decodeIfPresent([NameRule].self, forKey: .nameRules) ?? []
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        quarantinesDuplicates = try c.decodeIfPresent(Bool.self, forKey: .quarantinesDuplicates) ?? true
        duplicatesFolderName = try c.decodeIfPresent(String.self, forKey: .duplicatesFolderName) ?? "Duplicates"
        archiveAfterDays = try c.decodeIfPresent(Int.self, forKey: .archiveAfterDays) ?? 0
        archiveFolderName = try c.decodeIfPresent(String.self, forKey: .archiveFolderName) ?? "Archive"
        lastArchiveSweep = try c.decodeIfPresent(Date.self, forKey: .lastArchiveSweep)
        // Absent in older files, and absent means off. A feature that reads documents
        // must never arrive switched on because of an upgrade.
        usesIntelligence = try c.decodeIfPresent(Bool.self, forKey: .usesIntelligence) ?? false
    }
    public let id: UUID
    public var url: URL

    /// Security-scoped bookmark, so access survives a quit.
    ///
    /// Absent on folders added before sandboxing, and absent when the app is running
    /// unsandboxed — in both cases the plain URL still works, so this is additive rather
    /// than a hard requirement.
    public var bookmark: Data?

    /// Auto-filing for this folder specifically. The app-wide switch is separate, and
    /// both must be on for the watcher to act.
    public var isAutoEnabled: Bool

    public var scheme: SortScheme

    /// Category → folder name, when the user has renamed one.
    public var folderNames: [FileCategory: String]

    /// Categories that should be left where they are.
    public var ignoredCategories: Set<FileCategory>

    /// Lowercased extensions never filed from this folder.
    public var ignoredExtensions: Set<String>

    /// Extension → category, overriding the classifier.
    public var overrides: [String: FileCategory]

    /// Leave a file alone until it has sat here this long. Zero files immediately.
    public var minimumAgeSeconds: Int

    /// Filename patterns, checked before the type tables. First match wins, so order
    /// in this array is the user's priority order.
    ///
    /// Superseded by `rules` for anything new — kept because existing settings files
    /// contain them and silently dropping a user's rules on upgrade is not acceptable.
    public var nameRules: [NameRule]

    /// Condition/action rules, evaluated before name rules and before the type tables.
    public var rules: [Rule]

    /// Set aside a file that is byte-identical to one already in its destination,
    /// instead of filing a second copy beside it.
    public var quarantinesDuplicates: Bool

    /// Folder duplicates are set aside in. They are moved, never deleted — the whole
    /// point is that you get to decide.
    public var duplicatesFolderName: String

    /// Where `markForReview` puts things. Its own folder so "I could not decide" never
    /// looks like "I filed this".
    public var reviewFolderName: String { "Needs Review" }

    /// Sweep filed files untouched for this long into the archive. Zero is off.
    public var archiveAfterDays: Int

    public var archiveFolderName: String

    /// When the archive sweep last ran, so it runs about daily rather than on every
    /// filesystem event.
    public var lastArchiveSweep: Date?

    /// Read documents on-device to work out what they are, for files whose name says
    /// nothing. Off unless the user turns it on, per folder — never globally implied.
    public var usesIntelligence: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        bookmark: Data? = nil,
        isAutoEnabled: Bool = true,
        scheme: SortScheme = .category,
        folderNames: [FileCategory: String] = [:],
        ignoredCategories: Set<FileCategory> = [],
        ignoredExtensions: Set<String> = [],
        overrides: [String: FileCategory] = [:],
        minimumAgeSeconds: Int = 0,
        nameRules: [NameRule] = [],
        rules: [Rule] = [],
        quarantinesDuplicates: Bool = true,
        duplicatesFolderName: String = "Duplicates",
        archiveAfterDays: Int = 0,
        archiveFolderName: String = "Archive",
        lastArchiveSweep: Date? = nil,
        usesIntelligence: Bool = false
    ) {
        self.id = id
        self.url = url
        self.bookmark = bookmark
        self.isAutoEnabled = isAutoEnabled
        self.scheme = scheme
        self.folderNames = folderNames
        self.ignoredCategories = ignoredCategories
        self.ignoredExtensions = ignoredExtensions
        self.overrides = overrides
        self.minimumAgeSeconds = minimumAgeSeconds
        self.nameRules = nameRules
        self.rules = rules
        self.quarantinesDuplicates = quarantinesDuplicates
        self.duplicatesFolderName = duplicatesFolderName
        self.archiveAfterDays = archiveAfterDays
        self.archiveFolderName = archiveFolderName
        self.lastArchiveSweep = lastArchiveSweep
        self.usesIntelligence = usesIntelligence
    }

    /// Folder names suggesting contents a user would not want a model reading.
    ///
    /// Not a security boundary — the model is on-device either way — but a signal worth
    /// respecting by default. The user can still switch it on deliberately.
    public var looksSensitive: Bool {
        let name = url.lastPathComponent.lowercased()
        return ["medical", "health", "tax", "taxes", "legal", "finance", "financial",
                "bank", "banking", "private", "confidential", "personal"]
            .contains { name.contains($0) }
    }

    /// The first enabled pattern matching this filename, if any.
    public func nameRule(matching fileName: String) -> NameRule? {
        nameRules.first { $0.matches(fileName) }
    }

    public var displayName: String { url.lastPathComponent }

    public func folderName(for category: FileCategory) -> String {
        folderNames[category] ?? category.defaultFolderName
    }

    /// Every folder name this configuration can produce.
    ///
    /// The organiser uses this to recognise its own destination folders, so a
    /// top-level `Images` directory is never itself treated as a candidate.
    public var managedFolderNames: Set<String> {
        var names = Set(FileCategory.allCases.map { folderName(for: $0) })
        names.formUnion(nameRules.map(\.folderName))
        names.formUnion(rules.compactMap(\.destinationFolder))
        names.insert(reviewFolderName)
        names.insert(duplicatesFolderName)
        names.insert(archiveFolderName)
        names.formUnion(ContentLabel.allCases.map(\.defaultFolderName))
        return names
    }

    /// Folders the archive sweep is allowed to look inside: the ones Tidewell itself
    /// files into. The archive is excluded, or the sweep would eat its own output.
    public var sweepableFolderNames: Set<String> {
        managedFolderNames.subtracting([archiveFolderName, duplicatesFolderName])
    }
}
