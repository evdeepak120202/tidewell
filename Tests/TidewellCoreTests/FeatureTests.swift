import Foundation
import Testing
@testable import TidewellCore

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tidewell-feat-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ name: String, in folder: URL, contents: String = "hello") throws {
    try contents.data(using: .utf8)!.write(to: folder.appendingPathComponent(name))
}

private var fastOrganizer: Organizer {
    Organizer(stability: StabilityGate(settleInterval: .milliseconds(1)))
}

@Suite("Name rules")
struct NameRuleTests {

    @Test("Globs match the way Finder's do", arguments: [
        ("day-sheet-*", "day-sheet-2026-08-28.pdf", true),
        ("day-sheet-*", "daysheet.pdf", false),
        ("*cause-list*", "kerala-hc_x_cause-list_ab.pdf", true),
        ("Jagriq-Invoice-*", "jagriq-invoice-001.pdf", true),   // case-insensitive
        ("task.?????", "task.mention", false),                  // ? is exactly one
        ("task.*", "task.overdue", true),
    ])
    func matching(pattern: String, name: String, expected: Bool) {
        #expect(NameRule(pattern: pattern, folderName: "X").matches(name) == expected)
    }

    @Test("A disabled or half-written rule never matches")
    func inertRules() {
        #expect(!NameRule(pattern: "*", folderName: "X", isEnabled: false).matches("a.pdf"))
        #expect(!NameRule(pattern: "", folderName: "X").matches("a.pdf"))
        #expect(!NameRule(pattern: "*", folderName: "").matches("a.pdf"))
    }

    @Test("A pattern outranks the file's type")
    func patternBeatsType() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("day-sheet-2026-08-28.pdf", in: root)
        try write("unrelated.pdf", in: root)

        var folder = WatchedFolder(url: root)
        folder.nameRules = [NameRule(pattern: "day-sheet-*", folderName: "Day Sheets")]

        _ = await fastOrganizer.run(folder, trigger: .manual)
        let fm = FileManager.default
        // The rule wins for the match; everything else still sorts by type.
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Day Sheets/day-sheet-2026-08-28.pdf").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Documents/unrelated.pdf").path))
    }

    @Test("The first matching rule wins, so order is priority")
    func firstMatchWins() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("report-final.pdf", in: root)

        var folder = WatchedFolder(url: root)
        folder.nameRules = [
            NameRule(pattern: "report-*", folderName: "Reports"),
            NameRule(pattern: "*-final.pdf", folderName: "Final"),
        ]
        _ = await fastOrganizer.run(folder, trigger: .manual)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Reports/report-final.pdf").path))
    }

    @Test("A rule's folder is not then treated as loose files")
    func ruleFolderIsManaged() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("day-sheet-1.pdf", in: root)

        var folder = WatchedFolder(url: root)
        folder.nameRules = [NameRule(pattern: "day-sheet-*", folderName: "Day Sheets")]
        let organizer = fastOrganizer
        _ = await organizer.run(folder, trigger: .manual)
        let second = await organizer.run(folder, trigger: .manual).run
        #expect(second.moved.isEmpty, "the rule's own folder was re-scanned")
    }
}

@Suite("Duplicates")
struct DuplicateTests {

    @Test("Identical bytes are detected; same size with different bytes is not")
    func detectsOnlyRealDuplicates() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.txt", in: root, contents: "same")
        try write("b.txt", in: root, contents: "same")
        try write("c.txt", in: root, contents: "diff")   // identical length, different bytes

        let detector = DuplicateDetector()
        let groups = detector.groups(in: [
            root.appendingPathComponent("a.txt"),
            root.appendingPathComponent("b.txt"),
            root.appendingPathComponent("c.txt"),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.count == 2)
        #expect(groups.first?.allSatisfy { ["a.txt", "b.txt"].contains($0.lastPathComponent) } == true)
    }

    @Test("A re-download is set aside, and both copies survive")
    func duplicateIsQuarantinedNotDeleted() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        // Already filed, plus the same bytes arriving again.
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try write("report.pdf", in: documents, contents: "identical bytes")
        try write("report (1).pdf", in: root, contents: "identical bytes")

        var folder = WatchedFolder(url: root)
        folder.nameRules = []
        let run = await fastOrganizer.run(folder, trigger: .manual).run

        #expect(run.duplicateCount == 1)
        let fm = FileManager.default
        // Nothing is destroyed: the original stays filed, the copy is set aside.
        #expect(fm.fileExists(atPath: documents.appendingPathComponent("report.pdf").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Duplicates/report (1).pdf").path))
    }

    @Test("A file that merely shares a name is filed normally, not quarantined")
    func sameNameDifferentBytesIsNotADuplicate() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try write("report.pdf", in: documents, contents: "original")
        try write("report.pdf", in: root, contents: "a different document entirely")

        let run = await fastOrganizer.run(WatchedFolder(url: root), trigger: .manual).run
        #expect(run.duplicateCount == 0)
        #expect(FileManager.default.fileExists(
            atPath: documents.appendingPathComponent("report 2.pdf").path))
    }

    @Test("Quarantine can be switched off")
    func quarantineIsOptional() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try write("r.pdf", in: documents, contents: "x")
        try write("r (1).pdf", in: root, contents: "x")

        var folder = WatchedFolder(url: root)
        folder.quarantinesDuplicates = false
        let run = await fastOrganizer.run(folder, trigger: .manual).run
        #expect(run.duplicateCount == 0)
        #expect(FileManager.default.fileExists(
            atPath: documents.appendingPathComponent("r (1).pdf").path))
    }
}

@Suite("Archive")
struct ArchiveTests {

    private func age(_ url: URL, days: Int) throws {
        let date = Date().addingTimeInterval(-Double(days) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test("Stale filed files are archived by month; fresh ones are left")
    func archivesOnlyStaleFiles() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try write("old.pdf", in: documents)
        try write("new.pdf", in: documents)
        try age(documents.appendingPathComponent("old.pdf"), days: 200)

        var folder = WatchedFolder(url: root)
        folder.archiveAfterDays = 90

        let run = ArchiveSweeper().run(folder)
        #expect(run.moved.count == 1)
        #expect(run.moved.first?.source.lastPathComponent == "old.pdf")

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: documents.appendingPathComponent("new.pdf").path))
        // Landed under Archive/YYYY-MM, and still exists — moved, never removed.
        let archived = run.moved[0].destination
        #expect(fm.fileExists(atPath: archived.path))
        #expect(archived.deletingLastPathComponent().lastPathComponent.count == 7)
    }

    @Test("The archive never sweeps itself")
    func archiveIsNotReSwept() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Archive/2020-01")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try write("ancient.pdf", in: archive)
        try age(archive.appendingPathComponent("ancient.pdf"), days: 2000)

        var folder = WatchedFolder(url: root)
        folder.archiveAfterDays = 30
        #expect(ArchiveSweeper().run(folder).moved.isEmpty)
    }

    @Test("Off by default")
    func offByDefault() {
        #expect(ArchiveSweeper().plan(for: WatchedFolder(url: URL(fileURLWithPath: "/tmp"))).isEmpty)
    }

    @Test("Folders the user made are not swept")
    func leavesUserFoldersAlone() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let mine = root.appendingPathComponent("My Own Folder")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try write("old.pdf", in: mine)
        try age(mine.appendingPathComponent("old.pdf"), days: 500)

        var folder = WatchedFolder(url: root)
        folder.archiveAfterDays = 30
        #expect(ArchiveSweeper().run(folder).moved.isEmpty)
    }
}

@Suite("Settings migration")
struct MigrationTests {

    /// A journal written before `isDuplicate` existed.
    ///
    /// This is not hypothetical: adding that field with no default made the whole
    /// settings file undecodable, `load()` swallowed the error, and the app started
    /// with no watched folders at all — one save away from losing them permanently.
    @Test("A pre-isDuplicate journal entry still decodes")
    func decodesLegacyMovedFile() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "source":"file:///a/b.pdf",
         "destination":"file:///a/Documents/b.pdf",
         "category":"Documents"}
        """.data(using: .utf8)!

        let moved = try JSONDecoder().decode(MovedFile.self, from: json)
        #expect(moved.isDuplicate == false)
        #expect(moved.fileName == "b.pdf")
    }

    @Test("A pre-nameRules folder still decodes, with the new options defaulted")
    func decodesLegacyWatchedFolder() throws {
        let json = """
        {"id":"22222222-2222-2222-2222-222222222222",
         "url":"file:///Users/x/Downloads/",
         "isAutoEnabled":true,"scheme":"category",
         "folderNames":[],"ignoredCategories":[],"ignoredExtensions":[],
         "overrides":{},"minimumAgeSeconds":30}
        """.data(using: .utf8)!

        let folder = try JSONDecoder().decode(WatchedFolder.self, from: json)
        #expect(folder.minimumAgeSeconds == 30)
        #expect(folder.nameRules.isEmpty)
        #expect(folder.quarantinesDuplicates)            // sensible default
        #expect(folder.archiveAfterDays == 0)            // off unless asked for
        #expect(folder.duplicatesFolderName == "Duplicates")
    }

    @Test("A run missing optional fields still decodes")
    func decodesMinimalRun() throws {
        let json = """
        {"id":"33333333-3333-3333-3333-333333333333",
         "folder":"file:///Users/x/Downloads/","trigger":"Manual"}
        """.data(using: .utf8)!
        let run = try JSONDecoder().decode(OrganizeRun.self, from: json)
        #expect(run.moved.isEmpty)
        #expect(!run.isUndone)
    }

    @Test("New fields round-trip")
    func roundTrips() throws {
        var folder = WatchedFolder(url: URL(fileURLWithPath: "/tmp/x"))
        folder.nameRules = [NameRule(pattern: "day-sheet-*", folderName: "Day Sheets")]
        folder.archiveAfterDays = 90

        let data = try JSONEncoder().encode(folder)
        let back = try JSONDecoder().decode(WatchedFolder.self, from: data)
        #expect(back.nameRules.first?.pattern == "day-sheet-*")
        #expect(back.archiveAfterDays == 90)
    }
}
