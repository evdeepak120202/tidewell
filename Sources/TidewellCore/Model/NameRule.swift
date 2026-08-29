import Foundation

/// A filename pattern that decides a file's folder before its type is considered.
///
/// Type alone is a poor axis for the files that actually pile up: twenty-three
/// `day-sheet-…pdf` and a dozen `task.…` templates are all "Documents", which sorts
/// them into one heap and calls it tidy. A pattern says what they *are*.
public struct NameRule: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID

    /// Glob against the whole filename: `*` any run, `?` one character.
    /// Matched case-insensitively.
    public var pattern: String

    /// Folder the match is filed into, relative to the watched folder.
    public var folderName: String

    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        pattern: String,
        folderName: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.pattern = pattern
        self.folderName = folderName
        self.isEnabled = isEnabled
    }

    /// Does `fileName` match?
    ///
    /// `LIKE[c]` gives glob semantics with the same `*`/`?` the user already knows
    /// from Finder and the shell, without hand-rolling a matcher.
    public func matches(_ fileName: String) -> Bool {
        guard isEnabled, !pattern.isEmpty, !folderName.isEmpty else { return false }
        return NSPredicate(format: "SELF LIKE[c] %@", pattern).evaluate(with: fileName)
    }

    /// A pattern that cannot match anything is worth flagging in the editor rather
    /// than silently never firing.
    public var isUsable: Bool {
        !pattern.trimmingCharacters(in: .whitespaces).isEmpty
            && !folderName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
