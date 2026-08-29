import Foundation

/// Decides whether a rule applies to a file, and what that means.
///
/// Pure: it inspects and reports. Nothing here can change the filesystem, so a rule can
/// misfire but cannot destroy anything — the outcome still travels through `SafetyGuard`
/// and `FileMover` like every other path.
public struct RuleEvaluator: Sendable {

    /// Everything a condition might need, gathered once per file rather than re-read for
    /// each condition. A folder of 2,000 files against 10 rules is 20,000 evaluations;
    /// stat'ing per condition would make that visible.
    public struct FileFacts: Sendable {
        public let name: String
        public let fileExtension: String
        public let category: FileCategory
        public let sizeBytes: Int64
        public let modified: Date
        public let added: Date
        public let isDuplicate: Bool

        public init(
            name: String, fileExtension: String, category: FileCategory,
            sizeBytes: Int64, modified: Date, added: Date, isDuplicate: Bool
        ) {
            self.name = name
            self.fileExtension = fileExtension
            self.category = category
            self.sizeBytes = sizeBytes
            self.modified = modified
            self.added = added
            self.isDuplicate = isDuplicate
        }
    }

    public init() {}

    /// Gather the facts for one file.
    public func facts(
        for url: URL, category: FileCategory, isDuplicate: Bool, now: Date = Date()
    ) -> FileFacts {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey,
        ])
        let modified = values?.contentModificationDate ?? now
        return FileFacts(
            name: url.lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            category: category,
            sizeBytes: Int64(values?.fileSize ?? 0),
            modified: modified,
            added: values?.addedToDirectoryDate ?? modified,
            isDuplicate: isDuplicate
        )
    }

    /// Does this single condition hold?
    public func holds(_ condition: RuleCondition, for facts: FileFacts, now: Date = Date()) -> Bool {
        switch condition {
        case .nameMatches(let pattern):
            guard !pattern.isEmpty else { return false }
            return NSPredicate(format: "SELF LIKE[c] %@", pattern).evaluate(with: facts.name)

        case .nameContains(let text):
            guard !text.isEmpty else { return false }
            return facts.name.localizedCaseInsensitiveContains(text)

        case .nameHasPrefix(let text):
            guard !text.isEmpty else { return false }
            return facts.name.lowercased().hasPrefix(text.lowercased())

        case .nameHasSuffix(let text):
            guard !text.isEmpty else { return false }
            return facts.name.lowercased().hasSuffix(text.lowercased())

        case .extensionIs(let extensions):
            return extensions.contains { $0.lowercased() == facts.fileExtension }

        case .categoryIs(let category):
            return facts.category == category

        case .largerThan(let megabytes):
            return Double(facts.sizeBytes) > megabytes * 1_048_576

        case .smallerThan(let megabytes):
            return Double(facts.sizeBytes) < megabytes * 1_048_576

        case .olderThan(let days):
            return now.timeIntervalSince(facts.modified) > Double(days) * 86_400

        case .newerThan(let days):
            return now.timeIntervalSince(facts.added) < Double(days) * 86_400

        case .isDuplicate:
            return facts.isDuplicate
        }
    }

    /// Does the rule as a whole apply?
    public func applies(_ rule: Rule, to facts: FileFacts, now: Date = Date()) -> Bool {
        guard rule.isUsable else { return false }
        let results = rule.conditions.map { holds($0, for: facts, now: now) }

        switch rule.match {
        case .all:  return results.allSatisfy { $0 }
        case .any:  return results.contains(true)
        case .none: return !results.contains(true)
        }
    }

    /// The first rule that applies, in the user's order.
    ///
    /// First match wins rather than merging several rules' actions: a file that two rules
    /// both want to move has no sensible combined answer, and asking the user to reason
    /// about precedence *and* merging is how rule engines become unusable.
    public func firstMatch(in rules: [Rule], for facts: FileFacts, now: Date = Date()) -> Rule? {
        rules.first { applies($0, to: facts, now: now) }
    }
}
