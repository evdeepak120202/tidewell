import Foundation

/// A condition a file is tested against.
///
/// Closed enum rather than a free-form predicate string: every condition here is something
/// the app can evaluate, explain in the preview, and round-trip through JSON. A rule
/// language would be more expressive and would also let a rule mean something the UI
/// cannot show — which, for a tool that moves your files, is the wrong trade.
public enum RuleCondition: Codable, Sendable, Hashable {
    /// Glob against the whole filename: `*` any run, `?` one character.
    case nameMatches(String)
    case nameContains(String)
    case nameHasPrefix(String)
    case nameHasSuffix(String)
    case extensionIs([String])
    case categoryIs(FileCategory)
    case largerThan(megabytes: Double)
    case smallerThan(megabytes: Double)
    /// Untouched for at least this many days.
    case olderThan(days: Int)
    /// Arrived within this many days.
    case newerThan(days: Int)
    /// Byte-identical to something already filed in the destination.
    case isDuplicate

    public var summary: String {
        switch self {
        case .nameMatches(let p):     "name matches \(p)"
        case .nameContains(let t):    "name contains \(t)"
        case .nameHasPrefix(let t):   "name starts with \(t)"
        case .nameHasSuffix(let t):   "name ends with \(t)"
        case .extensionIs(let e):     "extension is \(e.joined(separator: ", "))"
        case .categoryIs(let c):      "kind is \(c.rawValue)"
        case .largerThan(let mb):     "larger than \(formatted(mb)) MB"
        case .smallerThan(let mb):    "smaller than \(formatted(mb)) MB"
        case .olderThan(let d):       "older than \(d) day\(d == 1 ? "" : "s")"
        case .newerThan(let d):       "added in the last \(d) day\(d == 1 ? "" : "s")"
        case .isDuplicate:            "is an identical copy"
        }
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// What a matching file has done to it.
///
/// **There is deliberately no delete, no trash, and no run-a-script.** Hazel has all
/// three; a folder-watching background agent that can execute shell is a permanent
/// remote-code-execution surface, and a rule engine that can delete turns a mistyped
/// pattern into data loss. Everything here is reversible.
public enum RuleAction: Codable, Sendable, Hashable {
    /// Folder beneath the watched folder. Never an absolute path.
    case moveTo(String)
    case addFinderTag(String)
    case setColourLabel(Int)
    /// Leave it where it is and stop evaluating later rules.
    case leaveAlone
    /// Move it to a review folder for the user to look at.
    case markForReview

    public var summary: String {
        switch self {
        case .moveTo(let folder):     "file into \(folder)/"
        case .addFinderTag(let tag):  "tag as \(tag)"
        case .setColourLabel(let i):  "set colour label \(i)"
        case .leaveAlone:             "leave it alone"
        case .markForReview:          "set aside for review"
        }
    }
}

/// How a rule's conditions combine.
public enum MatchMode: String, Codable, Sendable, CaseIterable {
    case all, any, none

    public var summary: String {
        switch self {
        case .all:  "all of"
        case .any:  "any of"
        case .none: "none of"
        }
    }
}

/// A named rule: conditions, and what to do when they hold.
public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var match: MatchMode
    public var conditions: [RuleCondition]
    public var actions: [RuleAction]

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        match: MatchMode = .all,
        conditions: [RuleCondition] = [],
        actions: [RuleAction] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.match = match
        self.conditions = conditions
        self.actions = actions
    }

    /// A rule with nothing to test, or nothing to do, silently never fires — worth
    /// showing in the editor rather than letting the user wonder.
    public var isUsable: Bool {
        isEnabled && !conditions.isEmpty && !actions.isEmpty
    }

    public var summary: String {
        guard !conditions.isEmpty else { return "no conditions" }
        let tests = conditions.map(\.summary).joined(separator: ", ")
        let doing = actions.map(\.summary).joined(separator: " and ")
        return "\(match.summary) \(tests) → \(doing)"
    }

    /// The folder this rule files into, if it files anywhere. Used so the organiser can
    /// recognise its own destinations and never re-scan them.
    public var destinationFolder: String? {
        for action in actions {
            if case .moveTo(let folder) = action { return folder }
        }
        return nil
    }
}
