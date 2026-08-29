import Foundation
import Testing
@testable import TidewellCore

/// End-to-end passes over a real directory.
///
/// The unit tests prove the guard answers correctly; these prove the organiser
/// actually asks it, on a folder containing the things that go wrong in practice.
@Suite("Organizer", .serialized)
struct OrganizerTests {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidewell-org-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, in folder: URL, bytes: Int = 16) throws {
        try Data(repeating: 0x42, count: bytes)
            .write(to: folder.appendingPathComponent(name))
    }

    /// No settle delay, so the tests do not sleep for a second per file.
    private var fastOrganizer: Organizer {
        Organizer(stability: StabilityGate(settleInterval: .milliseconds(1)))
    }

    @Test("A mixed folder is filed, and only the real files move")
    func filesOnlyLooseFiles() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("holiday.png", in: root)
        try write("invoice.pdf", in: root)
        try write("backup.zip", in: root)
        try write("half.crdownload", in: root)          // still downloading
        try write(".hidden-note", in: root)             // dotfile
        try FileManager.default.createDirectory(        // a real subfolder
            at: root.appendingPathComponent("My Stuff"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(     // a link
            at: root.appendingPathComponent("link.png"),
            withDestinationURL: root.appendingPathComponent("holiday.png"))

        let folder = WatchedFolder(url: root)
        let run = await fastOrganizer.run(folder, trigger: .manual).run

        #expect(run.failures.isEmpty, "unexpected failures: \(run.failures)")
        #expect(run.moved.count == 3, "expected 3 moves, got \(run.moved.map(\.fileName))")

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Images/holiday.png").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Documents/invoice.pdf").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Archives/backup.zip").path))

        // Everything that must not have been touched.
        #expect(fm.fileExists(atPath: root.appendingPathComponent("half.crdownload").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent(".hidden-note").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("My Stuff").path))

        // The symlink must still be *there*. `fileExists` follows links and its
        // target has legitimately moved, so the link now dangles — checking with
        // `attributesOfItem`, which does not follow, is what actually asks whether
        // Tidewell left the link alone.
        let link = root.appendingPathComponent("link.png")
        #expect((try? fm.attributesOfItem(atPath: link.path)) != nil,
                "the symlink itself was moved or removed")
        #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    @Test("A second pass does not re-file what it already filed")
    func isIdempotent() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.png", in: root)

        let folder = WatchedFolder(url: root)
        let first = await fastOrganizer.run(folder, trigger: .manual).run
        let second = await fastOrganizer.run(folder, trigger: .manual).run

        #expect(first.moved.count == 1)
        #expect(second.moved.isEmpty, "the organiser re-filed an already-filed file")
    }

    @Test("Undo puts every file back")
    func undoRestores() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.png", in: root)
        try write("b.pdf", in: root)

        let organizer = fastOrganizer
        let folder = WatchedFolder(url: root)
        let run = await organizer.run(folder, trigger: .manual).run
        #expect(run.moved.count == 2)

        let undone = await organizer.undo(run)
        #expect(undone.failures.isEmpty)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appendingPathComponent("a.png").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("b.pdf").path))
    }

    @Test("Nothing is lost when two files want the same name")
    func collidingNamesBothSurvive() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        // Pre-place a file where the incoming one wants to go.
        let images = root.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try write("shot.png", in: images, bytes: 111)
        try write("shot.png", in: root, bytes: 222)

        let run = await fastOrganizer.run(WatchedFolder(url: root), trigger: .manual).run
        #expect(run.moved.count == 1)

        // Both files exist, and the original is untouched.
        let original = images.appendingPathComponent("shot.png")
        let renamed = images.appendingPathComponent("shot 2.png")
        #expect(try original.resourceValues(forKeys: [.fileSizeKey]).fileSize == 111)
        #expect(try renamed.resourceValues(forKeys: [.fileSizeKey]).fileSize == 222)
    }

    @Test("Ignored categories are left where they are")
    func honoursIgnoredCategories() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.png", in: root)
        try write("b.pdf", in: root)

        var folder = WatchedFolder(url: root)
        folder.ignoredCategories = [.images]

        let run = await fastOrganizer.run(folder, trigger: .manual).run
        #expect(run.moved.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.png").path))
    }

    @Test("Month scheme nests under the category")
    func monthScheme() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.png", in: root)

        var folder = WatchedFolder(url: root)
        folder.scheme = .categoryByMonth

        let run = await fastOrganizer.run(folder, trigger: .manual).run
        #expect(run.moved.count == 1)

        let parts = run.moved[0].destination.pathComponents.suffix(3)
        #expect(parts.first == "Images")
        #expect(parts.dropFirst().first?.count == 7)   // YYYY-MM
    }

    @Test("A renamed category folder is used and then recognised")
    func customFolderName() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.png", in: root)

        var folder = WatchedFolder(url: root)
        folder.folderNames[.images] = "Pictures"

        let organizer = fastOrganizer
        _ = await organizer.run(folder, trigger: .manual)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Pictures/a.png").path))

        // The renamed folder must not then be treated as a candidate itself.
        let second = await organizer.run(folder, trigger: .manual).run
        #expect(second.moved.isEmpty)
    }

    // MARK: The arrival-delay regression

    @Test("A file held back by the delay asks to be re-checked")
    func deferredFileSchedulesRetry() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("fresh.png", in: root)

        var folder = WatchedFolder(url: root)
        folder.minimumAgeSeconds = 30          // just landed, so not yet eligible

        let plan = await fastOrganizer.plan(for: folder)

        #expect(plan.moves.isEmpty, "a file inside its delay window was filed early")
        #expect(plan.skips.contains { $0.reason == .tooYoung })

        // The bug: without a retry the watcher never looks again, because the
        // arrival already spent its filesystem event.
        let retry = try #require(plan.retryAfter, "no retry scheduled — the file would be stranded")
        #expect(retry <= .seconds(32) && retry >= .seconds(1))
    }

    @Test("Once the delay has passed the same file is filed")
    func deferredFileIsFiledLater() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("ready.png", in: root)

        var folder = WatchedFolder(url: root)
        folder.minimumAgeSeconds = 1
        try await Task.sleep(for: .milliseconds(1200))

        let plan = await fastOrganizer.plan(for: folder)
        #expect(plan.moves.count == 1)
        #expect(plan.retryAfter == nil, "nothing is waiting, so nothing should be rescheduled")
    }

    @Test("No delay means no retry is booked")
    func noDelayNoRetry() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.png", in: root)

        let plan = await fastOrganizer.plan(for: WatchedFolder(url: root))
        #expect(plan.retryAfter == nil)
    }
}
