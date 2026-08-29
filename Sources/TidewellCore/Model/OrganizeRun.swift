import Foundation

/// One file that moved, kept so the run can be reversed.
public struct MovedFile: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let source: URL
    public let destination: URL
    public let category: FileCategory

    /// Set aside as a byte-identical copy of something already filed, rather than
    /// filed on its own merits. Never means "deleted".
    public var isDuplicate: Bool

    /// Set when an on-device classification decided this file's destination. Recorded so
    /// "why did it do that?" always has an answer.
    public var contentLabel: ContentLabel?

    public init(
        id: UUID = UUID(), source: URL, destination: URL,
        category: FileCategory, isDuplicate: Bool = false,
        contentLabel: ContentLabel? = nil
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.category = category
        self.isDuplicate = isDuplicate
        self.contentLabel = contentLabel
    }

    public var fileName: String { destination.lastPathComponent }

    // Journals written before `isDuplicate` existed have no such key. Without this,
    // decoding the whole settings file throws and every watched folder is lost.
    private enum CodingKeys: String, CodingKey {
        case id, source, destination, category, isDuplicate, contentLabel
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        source = try c.decode(URL.self, forKey: .source)
        destination = try c.decode(URL.self, forKey: .destination)
        category = try c.decodeIfPresent(FileCategory.self, forKey: .category) ?? .other
        isDuplicate = try c.decodeIfPresent(Bool.self, forKey: .isDuplicate) ?? false
        contentLabel = try c.decodeIfPresent(ContentLabel.self, forKey: .contentLabel)
    }
}

/// One file that was deliberately left alone, and why.
public struct SkippedFile: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let url: URL
    public let reason: SkipReason

    public init(id: UUID = UUID(), url: URL, reason: SkipReason) {
        self.id = id
        self.url = url
        self.reason = reason
    }

    public var fileName: String { url.lastPathComponent }
}

/// The record of a single pass over a folder.
///
/// Runs are journalled whether or not anything moved, because "it ran and found
/// nothing" and "it never ran" look identical from the outside otherwise.
public struct OrganizeRun: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let folder: URL
    public let startedAt: Date
    public let trigger: Trigger
    public var moved: [MovedFile]
    public var skipped: [SkippedFile]
    public var failures: [String]
    public var isUndone: Bool

    public enum Trigger: String, Codable, Sendable {
        case automatic = "Auto"
        case manual    = "Manual"
        case undo      = "Undo"
        case archive   = "Archive"
        case duplicates = "Duplicates"
    }

    public init(
        id: UUID = UUID(),
        folder: URL,
        startedAt: Date = Date(),
        trigger: Trigger,
        moved: [MovedFile] = [],
        skipped: [SkippedFile] = [],
        failures: [String] = [],
        isUndone: Bool = false
    ) {
        self.id = id
        self.folder = folder
        self.startedAt = startedAt
        self.trigger = trigger
        self.moved = moved
        self.skipped = skipped
        self.failures = failures
        self.isUndone = isUndone
    }

    private enum CodingKeys: String, CodingKey {
        case id, folder, startedAt, trigger, moved, skipped, failures, isUndone
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        folder = try c.decode(URL.self, forKey: .folder)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        trigger = try c.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .manual
        moved = try c.decodeIfPresent([MovedFile].self, forKey: .moved) ?? []
        skipped = try c.decodeIfPresent([SkippedFile].self, forKey: .skipped) ?? []
        failures = try c.decodeIfPresent([String].self, forKey: .failures) ?? []
        isUndone = try c.decodeIfPresent(Bool.self, forKey: .isUndone) ?? false
    }

    public var isEmpty: Bool { moved.isEmpty && failures.isEmpty }

    public var duplicateCount: Int { moved.count(where: \.isDuplicate) }

    public var summary: String {
        if !failures.isEmpty { return "\(moved.count) moved, \(failures.count) failed" }
        if moved.isEmpty { return trigger == .archive ? "Nothing to archive" : "Nothing to file" }
        if trigger == .archive {
            return moved.count == 1 ? "1 file archived" : "\(moved.count) files archived"
        }
        let filed = moved.count - duplicateCount
        var parts: [String] = []
        if filed > 0 { parts.append(filed == 1 ? "1 file filed" : "\(filed) files filed") }
        if duplicateCount > 0 { parts.append("\(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s") set aside") }
        return parts.joined(separator: ", ")
    }
}
