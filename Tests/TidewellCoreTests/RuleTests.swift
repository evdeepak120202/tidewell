import Foundation
import Testing
@testable import TidewellCore

@Suite("Rule engine")
struct RuleTests {

    private func facts(
        name: String = "a.pdf", ext: String = "pdf", category: FileCategory = .documents,
        bytes: Int64 = 1024, ageDays: Double = 0, isDuplicate: Bool = false
    ) -> RuleEvaluator.FileFacts {
        let when = Date().addingTimeInterval(-ageDays * 86_400)
        return .init(name: name, fileExtension: ext, category: category,
                     sizeBytes: bytes, modified: when, added: when, isDuplicate: isDuplicate)
    }

    // MARK: Conditions

    @Test("Name conditions", arguments: [
        (RuleCondition.nameMatches("day-sheet-*"), "day-sheet-1.pdf", true),
        (.nameMatches("day-sheet-*"), "sheet.pdf", false),
        (.nameContains("invoice"), "2026-Invoice-3.pdf", true),
        (.nameHasPrefix("IMG"), "img_001.png", true),
        (.nameHasSuffix(".pdf"), "report.pdf", true),
        (.nameHasSuffix(".pdf"), "report.png", false),
    ])
    func nameConditions(condition: RuleCondition, name: String, expected: Bool) {
        #expect(RuleEvaluator().holds(condition, for: facts(name: name)) == expected)
    }

    @Test("Size conditions use megabytes, not bytes")
    func sizeConditions() {
        let evaluator = RuleEvaluator()
        let tenMB = facts(bytes: 10 * 1_048_576)
        #expect(evaluator.holds(.largerThan(megabytes: 5), for: tenMB))
        #expect(!evaluator.holds(.largerThan(megabytes: 20), for: tenMB))
        #expect(evaluator.holds(.smallerThan(megabytes: 20), for: tenMB))
    }

    @Test("Age conditions")
    func ageConditions() {
        let evaluator = RuleEvaluator()
        #expect(evaluator.holds(.olderThan(days: 30), for: facts(ageDays: 90)))
        #expect(!evaluator.holds(.olderThan(days: 30), for: facts(ageDays: 5)))
        #expect(evaluator.holds(.newerThan(days: 7), for: facts(ageDays: 1)))
        #expect(!evaluator.holds(.newerThan(days: 7), for: facts(ageDays: 30)))
    }

    @Test("An empty pattern never matches, rather than matching everything")
    func emptyPatternIsInert() {
        let evaluator = RuleEvaluator()
        // A half-typed rule that silently claimed every file would be a catastrophe.
        #expect(!evaluator.holds(.nameMatches(""), for: facts(name: "anything.pdf")))
        #expect(!evaluator.holds(.nameContains(""), for: facts(name: "anything.pdf")))
        #expect(!evaluator.holds(.nameHasPrefix(""), for: facts(name: "anything.pdf")))
    }

    // MARK: Match modes

    @Test("all / any / none")
    func matchModes() {
        let evaluator = RuleEvaluator()
        let f = facts(name: "invoice-9.pdf", ext: "pdf")
        let conditions: [RuleCondition] = [.nameContains("invoice"), .extensionIs(["png"])]

        #expect(!evaluator.applies(
            Rule(name: "r", match: .all, conditions: conditions, actions: [.moveTo("X")]), to: f))
        #expect(evaluator.applies(
            Rule(name: "r", match: .any, conditions: conditions, actions: [.moveTo("X")]), to: f))
        #expect(!evaluator.applies(
            Rule(name: "r", match: .none, conditions: conditions, actions: [.moveTo("X")]), to: f))
    }

    @Test("A rule with no conditions or no actions never fires")
    func incompleteRulesAreInert() {
        let evaluator = RuleEvaluator()
        let f = facts()
        #expect(!evaluator.applies(Rule(name: "no conditions", actions: [.moveTo("X")]), to: f))
        #expect(!evaluator.applies(Rule(name: "no actions", conditions: [.categoryIs(.documents)]), to: f))
        #expect(!evaluator.applies(
            Rule(name: "disabled", isEnabled: false,
                 conditions: [.categoryIs(.documents)], actions: [.moveTo("X")]), to: f))
    }

    @Test("First match wins, so order is priority")
    func firstMatchWins() {
        let evaluator = RuleEvaluator()
        let rules = [
            Rule(name: "one", conditions: [.extensionIs(["pdf"])], actions: [.moveTo("First")]),
            Rule(name: "two", conditions: [.nameContains("a")], actions: [.moveTo("Second")]),
        ]
        #expect(evaluator.firstMatch(in: rules, for: facts())?.name == "one")
    }

    // MARK: The safety property

    /// The action set is deliberately incapable of destruction. If someone adds a
    /// `.delete` case, this fails — which is the point.
    @Test("No action can destroy a file")
    func actionsCannotDestroy() {
        let actions: [RuleAction] = [
            .moveTo("X"), .addFinderTag("t"), .setColourLabel(1), .leaveAlone, .markForReview,
        ]
        for action in actions {
            let text = action.summary.lowercased()
            #expect(!text.contains("delete"))
            #expect(!text.contains("trash"))
            #expect(!text.contains("remove"))
        }
    }

    @Test("A rule can never name an absolute path")
    func destinationsStayRelative() {
        // The organiser appends the destination to the watched folder, so an absolute
        // path or a traversal would escape it.
        let rule = Rule(name: "r", conditions: [.categoryIs(.documents)],
                        actions: [.moveTo("Invoices")])
        let folder = rule.destinationFolder
        #expect(folder == "Invoices")
        #expect(folder?.hasPrefix("/") == false)
        #expect(folder?.contains("..") == false)
    }

    // MARK: Persistence

    @Test("Rules round-trip, and a folder without them still decodes")
    func persistence() throws {
        var folder = WatchedFolder(url: URL(fileURLWithPath: "/tmp/x"))
        folder.rules = [
            Rule(name: "Big archives", match: .all,
                 conditions: [.categoryIs(.archives), .largerThan(megabytes: 100)],
                 actions: [.markForReview]),
        ]
        let data = try JSONEncoder().encode(folder)
        let back = try JSONDecoder().decode(WatchedFolder.self, from: data)
        #expect(back.rules.count == 1)
        #expect(back.rules[0].conditions.count == 2)

        let legacy = """
        {"id":"55555555-5555-5555-5555-555555555555","url":"file:///tmp/y",
         "isAutoEnabled":true,"scheme":"category","folderNames":[],
         "ignoredCategories":[],"ignoredExtensions":[],"overrides":{},"minimumAgeSeconds":0}
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(WatchedFolder.self, from: legacy).rules.isEmpty)
    }

    @Test("A rule's destination folder is recognised, so it is never re-scanned")
    func destinationsAreManaged() {
        var folder = WatchedFolder(url: URL(fileURLWithPath: "/tmp/x"))
        folder.rules = [Rule(name: "r", conditions: [.categoryIs(.documents)],
                             actions: [.moveTo("Invoices")])]
        #expect(folder.managedFolderNames.contains("Invoices"))
        #expect(folder.managedFolderNames.contains(folder.reviewFolderName))
    }
}

@Suite("App Sweep")
struct AppSweepTests {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidewell-sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Finds leftovers by bundle identifier, in the standard places")
    func findsLeftovers() throws {
        let library = try scratch()
        defer { try? FileManager.default.removeItem(at: library) }
        let fm = FileManager.default

        for area in ["Application Support", "Caches", "Preferences"] {
            try fm.createDirectory(at: library.appendingPathComponent(area),
                                   withIntermediateDirectories: true)
        }
        try fm.createDirectory(
            at: library.appendingPathComponent("Application Support/com.example.Widget"),
            withIntermediateDirectories: true)
        try Data("x".utf8).write(
            to: library.appendingPathComponent("Preferences/com.example.Widget.plist"))
        try Data("x".utf8).write(
            to: library.appendingPathComponent("Caches/com.other.Thing.plist"))

        let found = AppSweep().leftovers(forBundleID: "com.example.Widget", in: library)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.name.hasPrefix("com.example.Widget") })
    }

    /// Matching on a display name would sweep anything containing the word. The bundle
    /// identifier is the only signal specific enough to act on.
    @Test("Never matches on a name fragment", arguments: ["Widget", "com", "", "example"])
    func refusesLooseIdentifiers(bundleID: String) throws {
        let library = try scratch()
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(
            at: library.appendingPathComponent("Caches/com.example.Widget"),
            withIntermediateDirectories: true)

        #expect(AppSweep().leftovers(forBundleID: bundleID, in: library).isEmpty)
    }

    @Test("A near-miss identifier does not match")
    func exactPrefixOnly() throws {
        let library = try scratch()
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(
            at: library.appendingPathComponent("Caches/com.example.WidgetPro"),
            withIntermediateDirectories: true)

        // `com.example.WidgetPro` is a different app from `com.example.Widget`.
        #expect(AppSweep().leftovers(forBundleID: "com.example.Widget", in: library).isEmpty)
    }

    @Test("Gathering moves, and both ends survive")
    func gatherMovesRatherThanDeletes() throws {
        let library = try scratch()
        let review = try scratch()
        defer {
            try? FileManager.default.removeItem(at: library)
            try? FileManager.default.removeItem(at: review)
        }
        try FileManager.default.createDirectory(
            at: library.appendingPathComponent("Caches"), withIntermediateDirectories: true)
        let leftover = library.appendingPathComponent("Caches/com.example.Widget.plist")
        try Data("payload".utf8).write(to: leftover)

        let sweep = AppSweep()
        let found = sweep.leftovers(forBundleID: "com.example.Widget", in: library)
        let run = sweep.gather(found, forApp: "Widget", into: review)

        #expect(run.moved.count == 1)
        #expect(run.failures.isEmpty)
        // Moved out of Library, and still on disk where the user can look at it.
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: run.moved[0].destination.path))
        #expect(try String(contentsOf: run.moved[0].destination, encoding: .utf8) == "payload")
    }
}
