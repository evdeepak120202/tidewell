import Foundation
import Testing
@testable import TidewellCore

/// The guarantees that make Tidewell safe to leave running.
@Suite("Safety")
struct SafetyTests {

    /// Build a scratch directory that is removed when the test ends.
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidewell-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String, in folder: URL, bytes: Int = 8) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    // MARK: The headline guarantee

    /// TidewellCore must contain no way to delete a file.
    ///
    /// This is asserted against the source rather than behaviour on purpose: a
    /// behavioural test only proves the paths it exercises, whereas this fails the
    /// moment anyone *adds* a deletion call, in a path no test covers yet.
    @Test("No source file calls a deletion or overwrite API")
    func sourceContainsNoDestructiveCalls() throws {
        let core = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // TidewellCoreTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("Sources/TidewellCore")

        let banned = [
            "removeItem", "trashItem", "replaceItem", "replaceItemAt",
            "unlink(", "remove(at:", "truncate(",
        ]

        let files = FileManager.default.enumerator(at: core, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        #expect(!files.isEmpty, "no sources found — the path is wrong, not the code")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for call in banned {
                #expect(
                    !source.contains(call),
                    "\(file.lastPathComponent) contains \(call) — TidewellCore must never destroy data"
                )
            }
        }
    }

    /// Tidewell claims your files never leave the machine. That claim is only worth
    /// something if it is checked, so it is checked here rather than asserted in a
    /// privacy policy.
    @Test("No source file references a networking API")
    func sourceContainsNoNetworking() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")

        let banned = [
            "URLSession", "NWConnection", "NWBrowser", "NWListener",
            "CFSocket", "CFStream", "getaddrinfo", "URLRequest",
        ]

        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty, "no sources found — the path is wrong, not the code")

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for api in banned {
                #expect(
                    !source.contains(api),
                    "\(file.lastPathComponent) references \(api) — Tidewell must have no network code"
                )
            }
        }
    }

    // MARK: Guard behaviour

    @Test("Directories are never candidates")
    func skipsDirectories() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        let sub = root.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let decision = SafetyGuard().decide(
            for: sub,
            proposedDestination: root.appendingPathComponent("Other/Images"),
            stability: .settled
        )
        guard case .skip(let reason) = decision else {
            Issue.record("a directory was accepted for moving"); return
        }
        #expect(reason == .isDirectory)
    }

    @Test("Partial downloads are left alone", arguments: ["a.crdownload", "b.part", "c.download", "d.tmp"])
    func skipsPartialDownloads(name: String) throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeFile(name, in: root)

        let decision = SafetyGuard().decide(
            for: file,
            proposedDestination: root.appendingPathComponent("Other/\(name)"),
            stability: .settled
        )
        guard case .skip(let reason) = decision else {
            Issue.record("\(name) was accepted while still downloading"); return
        }
        #expect(reason == .isPartialDownload)
    }

    @Test("A file still being written is left alone")
    func skipsUnstableFile() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeFile("growing.zip", in: root)

        let decision = SafetyGuard().decide(
            for: file,
            proposedDestination: root.appendingPathComponent("Archives/growing.zip"),
            stability: .changing
        )
        guard case .skip(let reason) = decision else {
            Issue.record("an unstable file was accepted"); return
        }
        #expect(reason == .isUnstable)
    }

    @Test("An occupied destination is refused, never overwritten")
    func refusesOccupiedDestination() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = try makeFile("report.pdf", in: root)
        let dest = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let occupied = try makeFile("report.pdf", in: dest, bytes: 999)

        let decision = SafetyGuard().decide(for: file, proposedDestination: occupied, stability: .settled)
        guard case .skip(let reason) = decision else {
            Issue.record("Tidewell was willing to overwrite an existing file"); return
        }
        #expect(reason == .destinationExists)

        // and the occupant is untouched
        let size = try occupied.resourceValues(forKeys: [.fileSizeKey]).fileSize
        #expect(size == 999)
    }

    @Test("Dangerous roots cannot be watched", arguments: ["/", "/System", "/Applications", "/Volumes/Data"])
    func refusesForbiddenRoots(path: String) {
        #expect(SafetyGuard.isForbiddenRoot(URL(fileURLWithPath: path)))
    }

    @Test("The home directory cannot be watched")
    func refusesHome() {
        #expect(SafetyGuard.isForbiddenRoot(FileManager.default.homeDirectoryForCurrentUser))
    }

    @Test("An ordinary Downloads folder is allowed")
    func allowsNormalFolder() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        #expect(!SafetyGuard.isForbiddenRoot(downloads))
    }

    // MARK: Collisions

    @Test("Colliding names are suffixed, not replaced")
    func uniquifiesInsteadOfReplacing() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeFile("shot.png", in: root)

        let mover = FileMover()
        let unique = mover.uniqueDestination(for: root.appendingPathComponent("shot.png"))
        #expect(unique.lastPathComponent == "shot 2.png")

        _ = try makeFile("shot 2.png", in: root)
        #expect(mover.uniqueDestination(for: root.appendingPathComponent("shot.png"))
            .lastPathComponent == "shot 3.png")
    }
}

@Suite("Classification")
struct ClassificationTests {

    @Test("Extensions land in the expected category", arguments: [
        ("photo.png", FileCategory.images), ("clip.mp4", .video), ("song.flac", .audio),
        ("notes.pdf", .documents), ("bundle.zip", .archives), ("main.swift", .code),
        ("app.dmg", .installers), ("board.sketch", .design), ("rows.csv", .data),
    ])
    func classifies(name: String, expected: FileCategory) {
        let category = Classifier().category(for: URL(fileURLWithPath: "/tmp/\(name)"))
        #expect(category == expected)
    }

    @Test("Source code is not filed as a document")
    func codeBeatsPlainText() {
        // .swift conforms to .plainText, so ordering inside the classifier matters.
        #expect(Classifier().category(for: URL(fileURLWithPath: "/tmp/App.swift")) == .code)
    }

    @Test("A user override wins over the built-in tables")
    func overrideWins() {
        let classifier = Classifier(overrides: ["png": .documents])
        #expect(classifier.category(for: URL(fileURLWithPath: "/tmp/x.png")) == .documents)
    }

    @Test("An unknown extension falls to Other")
    func unknownIsOther() {
        #expect(Classifier().category(for: URL(fileURLWithPath: "/tmp/x.qqzz")) == .other)
    }

    @Test("Extension scheme has no destination for an extensionless file")
    func extensionSchemeNeedsAnExtension() {
        let components = SortScheme.fileExtension.destinationComponents(
            category: .other, folderName: "Other", fileExtension: "", date: Date()
        )
        #expect(components == nil)
    }
}
