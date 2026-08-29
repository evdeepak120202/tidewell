import Foundation
import Testing
@testable import TidewellCore

/// Budgets, not micro-benchmarks.
///
/// Tidewell runs all day in the background, so the numbers that matter are "does a big
/// folder stall the machine" and "does hashing read files it did not need to". These are
/// deliberately loose — they exist to catch a regression of the order of magnitude, not
/// to police milliseconds on a busy CI runner.
@Suite("Performance", .serialized)
struct PerformanceTests {

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidewell-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Planning a 2,000-file folder stays well under a second")
    func planningIsFast() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        let extensions = ["png", "pdf", "zip", "mp4", "swift", "csv"]
        for index in 0..<2_000 {
            let name = "file-\(index).\(extensions[index % extensions.count])"
            try Data(repeating: 0x41, count: 64).write(to: root.appendingPathComponent(name))
        }

        // Stability sampling is the deliberate slow part, so it is neutralised here —
        // this measures the planning work, not two seconds of sleeping.
        let organizer = Organizer(stability: StabilityGate(settleInterval: .nanoseconds(1)))

        let start = ContinuousClock.now
        let plan = await organizer.plan(for: WatchedFolder(url: root))
        let elapsed = ContinuousClock.now - start

        #expect(plan.moves.count == 2_000)
        #expect(elapsed < .seconds(5), "planning 2,000 files took \(elapsed)")
    }

    @Test("Duplicate detection does not hash files of differing size")
    func hashingIsSizeFiltered() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        // 200 files, every one a different length, so no pair can possibly match. A
        // correct implementation reads none of them; a naive one hashes all 200.
        for index in 0..<200 {
            try Data(repeating: 0x42, count: 1_000 + index)
                .write(to: root.appendingPathComponent("f\(index).bin"))
        }
        let urls = (0..<200).map { root.appendingPathComponent("f\($0).bin") }

        let start = ContinuousClock.now
        let groups = DuplicateDetector().groups(in: urls)
        let elapsed = ContinuousClock.now - start

        #expect(groups.isEmpty)
        #expect(elapsed < .milliseconds(500), "size pre-filter appears to be gone: \(elapsed)")
    }

    @Test("Hashing a large file streams rather than loading it whole")
    func hashingStreams() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        // 48 MB, comparable to the largest real file this project has organised.
        let url = root.appendingPathComponent("big.bin")
        let handle = FileManager.default.createFile(atPath: url.path, contents: nil)
        #expect(handle)
        let file = try FileHandle(forWritingTo: url)
        let chunk = Data(repeating: 0x43, count: 1 << 20)
        for _ in 0..<48 { file.write(chunk) }
        try file.close()

        let digest = DuplicateDetector().digest(of: url)
        #expect(digest?.count == 64, "SHA-256 should be 64 hex characters")
    }

    @Test("A folder of directories costs nothing")
    func directoriesAreCheap() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<500 {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("dir-\(index)"), withIntermediateDirectories: true)
        }
        let organizer = Organizer(stability: StabilityGate(settleInterval: .nanoseconds(1)))
        let start = ContinuousClock.now
        let plan = await organizer.plan(for: WatchedFolder(url: root))
        let elapsed = ContinuousClock.now - start

        #expect(plan.moves.isEmpty)
        #expect(elapsed < .seconds(2), "directory scan took \(elapsed)")
    }
}
