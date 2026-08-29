import Foundation

/// Finds the files an uninstalled app left behind.
///
/// Dragging an app to the Bin leaves its preferences, caches and support folders on disk
/// — often hundreds of megabytes, and invisible unless you go looking. Hazel's App Sweep
/// popularised offering to clear them.
///
/// Tidewell's version differs in the way the rest of the app differs: **it gathers, it
/// does not decide.** Leftovers are moved into a folder you can look through, not deleted,
/// because "probably belongs to that app" is a guess, and a guess should not be able to
/// destroy a licence file or a save game.
///
/// Being sandboxed constrains this deliberately. The app cannot wander through
/// `~/Library`; the user grants that folder once, through a panel, and the grant is a
/// bookmark like any other. That is a worse experience than an unconfined competitor and
/// a much better guarantee.
public struct AppSweep: Sendable {

    /// The standard places a Mac app leaves things, relative to a granted Library folder.
    static let searchAreas = [
        "Application Support", "Caches", "Preferences", "Logs",
        "Containers", "Saved Application State", "HTTPStorages", "WebKit",
    ]

    public struct Leftover: Sendable, Identifiable, Hashable {
        public let id: UUID
        public let url: URL
        public let sizeBytes: Int64
        /// Which of the search areas it was found in, for the UI to group by.
        public let area: String

        public init(id: UUID = UUID(), url: URL, sizeBytes: Int64, area: String) {
            self.id = id
            self.url = url
            self.sizeBytes = sizeBytes
            self.area = area
        }

        public var name: String { url.lastPathComponent }
    }

    private let mover = FileMover()

    public init() {}

    /// Read an app bundle's identifier, which is what leftovers are named after.
    public func bundleIdentifier(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    /// Everything under `library` that appears to belong to `bundleID`.
    ///
    /// Matching is on the bundle identifier only — never on the app's display name. A
    /// name match would sweep "Notes" into anything containing the word, and the whole
    /// point is that a wrong guess here is expensive.
    public func leftovers(forBundleID bundleID: String, in library: URL) -> [Leftover] {
        guard !bundleID.isEmpty, bundleID.contains(".") else { return [] }
        let fileManager = FileManager.default
        var found: [Leftover] = []

        for area in Self.searchAreas {
            let directory = library.appendingPathComponent(area)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsSubdirectoryDescendants]
            ) else { continue }

            for entry in entries {
                let name = entry.lastPathComponent
                // `com.foo.Bar`, `com.foo.Bar.plist`, `com.foo.Bar.savedState`.
                guard name == bundleID || name.hasPrefix(bundleID + ".") else { continue }
                found.append(
                    Leftover(url: entry, sizeBytes: Self.size(of: entry), area: area)
                )
            }
        }
        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Move the chosen leftovers into a folder for the user to review.
    ///
    /// Nothing is deleted here, and nothing can be: this goes through the same
    /// `FileMover` as every other path in the app.
    public func gather(
        _ leftovers: [Leftover], forApp appName: String, into destination: URL
    ) -> OrganizeRun {
        var moved: [MovedFile] = []
        var failures: [String] = []
        let folder = destination.appendingPathComponent(appName)

        for leftover in leftovers {
            do {
                let target = mover.uniqueDestination(
                    for: folder.appendingPathComponent(leftover.name))
                try mover.move(leftover.url, to: target)
                moved.append(MovedFile(source: leftover.url, destination: target, category: .other))
            } catch {
                failures.append("\(leftover.name): \(error)")
            }
        }
        return OrganizeRun(folder: destination, trigger: .manual,
                           moved: moved, skipped: [], failures: failures)
    }

    /// Recursive size, capped so a pathological tree cannot stall the scan.
    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values?.isDirectory == true else { return Int64(values?.fileSize ?? 0) }

        var total: Int64 = 0
        var visited = 0
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }

        for case let child as URL in walker {
            visited += 1
            if visited > 20_000 { break }
            total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
