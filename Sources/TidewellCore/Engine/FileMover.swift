import Foundation

/// The single point in Tidewell that mutates the filesystem.
///
/// It has exactly two capabilities: create a directory, and move a file into one.
/// There is deliberately no delete, no trash, and no overwrite anywhere in this type
/// — not as a policy, but as a matter of what it is able to express. A bug in the
/// rules can therefore misfile something, which is reversible from the journal; it
/// cannot destroy it.
///
/// `FileManager.moveItem` on the same volume is a rename: the bytes never move, so a
/// crash mid-run leaves the file either at the source or the destination, never
/// half-written.
public struct FileMover: Sendable {

    public enum Failure: Error, Sendable {
        case destinationOccupied(URL)
        case couldNotCreateFolder(URL, underlying: String)
        case moveFailed(from: URL, to: URL, underlying: String)
    }

    // `FileManager` is not Sendable, so it is not stored. `FileManager.default` is
    // documented as safe to use concurrently for these operations, and reaching for
    // it at each call site keeps `FileMover` a Sendable value type.
    private var fileManager: FileManager { .default }

    public init() {}

    /// Return a URL that does not exist yet, by suffixing " 2", " 3", …
    ///
    /// Collisions are resolved by renaming the *incoming* file, never by replacing
    /// what is already on disk.
    public func uniqueDestination(for proposed: URL) -> URL {
        guard fileManager.fileExists(atPath: proposed.path) else { return proposed }

        let folder = proposed.deletingLastPathComponent()
        let ext = proposed.pathExtension
        let stem = proposed.deletingPathExtension().lastPathComponent

        // 2…999 is far past any sane collision count; the cap stops a pathological
        // directory from spinning here forever.
        for suffix in 2...999 {
            let name = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent("\(stem) \(UUID().uuidString)")
    }

    /// Move `source` to `destination`, creating the enclosing folder if needed.
    ///
    /// - Returns: the URL the file actually landed at.
    @discardableResult
    public func move(_ source: URL, to destination: URL) throws -> URL {
        let folder = destination.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw Failure.couldNotCreateFolder(folder, underlying: error.localizedDescription)
            }
        }

        // Re-check immediately before the move. The guard checked earlier, but a
        // download could have completed into this exact name since then.
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw Failure.destinationOccupied(destination)
        }

        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw Failure.moveFailed(
                from: source, to: destination, underlying: error.localizedDescription
            )
        }
        return destination
    }
}
