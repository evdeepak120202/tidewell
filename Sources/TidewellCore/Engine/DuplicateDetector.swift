import CryptoKit
import Foundation

/// Finds files that are byte-for-byte identical.
///
/// "Same name" and "same size" are both wrong answers — `report (1).pdf` is usually
/// a genuine duplicate and two 4 KB files usually are not. Only the content settles
/// it, so content is what gets compared.
///
/// Hashing is the expensive part, so size is used as a free pre-filter: files whose
/// length differs cannot be identical, and in a folder of mixed downloads that
/// eliminates almost everything before a byte is read.
public struct DuplicateDetector: Sendable {

    /// Read in chunks so a 44 MB PDF is never held in memory whole.
    private static let chunkSize = 1 << 20      // 1 MiB

    public init() {}

    /// SHA-256 of a file's contents, streamed.
    public func digest(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Is `candidate` byte-identical to any file already in `folder`?
    ///
    /// Used on the filing path: if the exact same bytes are already sitting in the
    /// destination, the arriving copy is a duplicate rather than something to file
    /// alongside it as `… 2`.
    public func identicalTwin(of candidate: URL, existingIn folder: URL) -> URL? {
        guard let size = fileSize(candidate), size > 0,
              let siblings = try? FileManager.default.contentsOfDirectory(
                  at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                  options: [.skipsSubdirectoryDescendants])
        else { return nil }

        // Only same-size files can possibly match, so hash the candidate lazily.
        let sameSize = siblings.filter { sibling in
            sibling.standardizedFileURL != candidate.standardizedFileURL
                && (try? sibling.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && fileSize(sibling) == size
        }
        guard !sameSize.isEmpty, let candidateDigest = digest(of: candidate) else { return nil }

        return sameSize.first { digest(of: $0) == candidateDigest }
    }

    /// Every group of identical files among `urls`, newest last within each group.
    ///
    /// Groups of one are not returned — there is nothing to decide about a file with
    /// no twin.
    public func groups(in urls: [URL]) -> [[URL]] {
        var bySize: [Int64: [URL]] = [:]
        for url in urls {
            guard let size = fileSize(url), size > 0 else { continue }
            bySize[size, default: []].append(url)
        }

        var result: [[URL]] = []
        for (_, candidates) in bySize where candidates.count > 1 {
            var byDigest: [String: [URL]] = [:]
            for url in candidates {
                guard let digest = digest(of: url) else { continue }
                byDigest[digest, default: []].append(url)
            }
            for (_, matches) in byDigest where matches.count > 1 {
                result.append(matches.sorted { modified($0) < modified($1) })
            }
        }
        return result.sorted { ($0.first?.lastPathComponent ?? "") < ($1.first?.lastPathComponent ?? "") }
    }

    private func fileSize(_ url: URL) -> Int64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(value)
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
