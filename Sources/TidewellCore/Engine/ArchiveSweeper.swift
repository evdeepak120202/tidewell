import Foundation

/// Moves filed files that have gone stale into a dated archive.
///
/// Without this, categories only ever grow: a folder tidied a year ago is still a
/// thousand files, just in eight neat piles. The sweep keeps the working set small.
///
/// Scope is deliberately narrow. It looks at the watched folder's loose files and
/// one level inside the folders Tidewell itself files into — never the archive, never
/// the duplicates folder, and never anything the user made. Files only, as always,
/// and moved rather than removed: an archived file is still exactly where you can
/// find it.
public struct ArchiveSweeper: Sendable {

    private let guardRail: SafetyGuard
    private let mover: FileMover

    public init(guardRail: SafetyGuard = SafetyGuard(), mover: FileMover = FileMover()) {
        self.guardRail = guardRail
        self.mover = mover
    }

    /// Files eligible for archiving, and where each would go.
    public func plan(for folder: WatchedFolder, now: Date = Date()) -> [MovedFile] {
        guard folder.archiveAfterDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(folder.archiveAfterDays) * 86_400)
        let fm = FileManager.default

        // The watched folder's own loose files, plus one level inside each folder
        // Tidewell files into.
        var searchRoots = [folder.url]
        for name in folder.sweepableFolderNames.sorted() {
            let sub = folder.url.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: sub.path, isDirectory: &isDirectory), isDirectory.boolValue {
                searchRoots.append(sub)
            }
        }

        var planned: [MovedFile] = []
        let classifier = Classifier(overrides: folder.overrides)

        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsSubdirectoryDescendants]
            ) else { continue }

            for entry in entries {
                // Directories are skipped here as everywhere else, which also keeps
                // the sweep from descending past the one level it is allowed.
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
                else { continue }

                guard let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate, modified < cutoff
                else { continue }

                let bucket = Self.monthComponent(for: modified)
                let destination = folder.url
                    .appendingPathComponent(folder.archiveFolderName)
                    .appendingPathComponent(bucket)
                    .appendingPathComponent(entry.lastPathComponent)

                let unique = mover.uniqueDestination(for: destination)
                guard case .move(let target) = guardRail.decide(
                    for: entry, proposedDestination: unique, stability: .settled
                ) else { continue }

                planned.append(
                    MovedFile(source: entry, destination: target,
                              category: classifier.category(for: entry))
                )
            }
        }
        return planned
    }

    /// Carry out the sweep.
    public func run(_ folder: WatchedFolder, now: Date = Date()) -> OrganizeRun {
        var moved: [MovedFile] = []
        var failures: [String] = []

        for candidate in plan(for: folder, now: now) {
            do {
                let final = mover.uniqueDestination(for: candidate.destination)
                try mover.move(candidate.source, to: final)
                moved.append(MovedFile(id: candidate.id, source: candidate.source,
                                       destination: final, category: candidate.category))
            } catch {
                failures.append("\(candidate.source.lastPathComponent): \(error)")
            }
        }
        return OrganizeRun(folder: folder.url, trigger: .archive,
                           moved: moved, skipped: [], failures: failures)
    }

    static func monthComponent(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return "Undated" }
        return String(format: "%04d-%02d", year, month)
    }
}
