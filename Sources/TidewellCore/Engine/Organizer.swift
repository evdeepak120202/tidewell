import Foundation

/// Files the loose files in a watched folder.
///
/// Scope is deliberately one level deep: the immediate children of the watched
/// folder, files only. Nothing recurses, so files already filed into `Images/` are
/// invisible to the next run and cannot be shuffled a second time.
/// What a pass intends to do, plus when it needs to be run again.
public struct OrganizePlan: Sendable {
    public var moves: [MovedFile]
    public var skips: [SkippedFile]

    /// Set when files were held back only because their delay had not elapsed.
    ///
    /// Without this the watcher would strand them: FSEvents fires once when a file
    /// lands, the pass a few seconds later finds it too young, and nothing ever
    /// triggers another look.
    public var retryAfter: Duration?

    public init(moves: [MovedFile] = [], skips: [SkippedFile] = [], retryAfter: Duration? = nil) {
        self.moves = moves
        self.skips = skips
        self.retryAfter = retryAfter
    }
}

public struct Organizer: Sendable {

    private let guardRail: SafetyGuard
    private let mover: FileMover
    private let stability: StabilityGate
    private let duplicates = DuplicateDetector()
    private let evaluator = RuleEvaluator()

    /// Shared so the classification cache survives between runs.
    private let intelligence: IntelligenceEngine?

    /// Not stored: `FileManager` is not Sendable, and storing one would force
    /// `Organizer` to give up being a Sendable value.
    private var fileManager: FileManager { .default }

    public init(
        guardRail: SafetyGuard = SafetyGuard(),
        mover: FileMover = FileMover(),
        stability: StabilityGate = StabilityGate(),
        intelligence: IntelligenceEngine? = nil
    ) {
        self.guardRail = guardRail
        self.mover = mover
        self.stability = stability
        self.intelligence = intelligence
    }

    /// Work out what would happen, without touching anything.
    ///
    /// The manual button previews through this first, so "Organize" can say what it
    /// is about to do rather than announcing it afterwards.
    public func plan(for folder: WatchedFolder) async -> OrganizePlan {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .addedToDirectoryDateKey],
            options: [.skipsSubdirectoryDescendants]
        ) else { return OrganizePlan() }

        let classifier = Classifier(overrides: folder.overrides)
        let managed = folder.managedFolderNames
        var moves: [MovedFile] = []
        var skips: [SkippedFile] = []
        var shortestWait: TimeInterval?

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {

            // Never consider one of our own destination folders, even before the
            // guard runs — cheap, and it keeps the skip log free of noise.
            if managed.contains(entry.lastPathComponent) { continue }

            let ext = entry.pathExtension.lowercased()
            if folder.ignoredExtensions.contains(ext) {
                skips.append(SkippedFile(url: entry, reason: .excludedByRule)); continue
            }

            let category = classifier.category(for: entry)

            // Precedence, most specific first:
            //   1. condition/action rules, in the user's order
            //   2. filename patterns (the older, simpler form)
            //   3. the type tables
            // A filename pattern outranks type because twenty-three `day-sheet-…pdf` are
            // all "Documents" by type, which is true and useless.
            let matchedRule = folder.nameRule(matching: entry.lastPathComponent)

            // Rules are evaluated before anything else decides a destination.
            var ruleFolder: String?
            var ruleLeftAlone = false
            if !folder.rules.isEmpty {
                let facts = evaluator.facts(for: entry, category: category, isDuplicate: false)
                if let rule = evaluator.firstMatch(in: folder.rules, for: facts) {
                    for action in rule.actions {
                        switch action {
                        case .moveTo(let name):    ruleFolder = name
                        case .markForReview:       ruleFolder = folder.reviewFolderName
                        case .leaveAlone:          ruleLeftAlone = true
                        // Tags and labels are metadata, applied after the move rather
                        // than deciding where it goes.
                        case .addFinderTag, .setColourLabel: break
                        }
                    }
                }
            }

            if ruleLeftAlone {
                skips.append(SkippedFile(url: entry, reason: .excludedByRule)); continue
            }


            if matchedRule == nil, folder.ignoredCategories.contains(category) {
                skips.append(SkippedFile(url: entry, reason: .excludedByRule)); continue
            }

            if folder.minimumAgeSeconds > 0, let added = addedDate(entry) {
                let waited = Date().timeIntervalSince(added)
                let remaining = Double(folder.minimumAgeSeconds) - waited
                if remaining > 0 {
                    // Remember the soonest one so the caller can come back for it.
                    shortestWait = min(shortestWait ?? remaining, remaining)
                    skips.append(SkippedFile(url: entry, reason: .tooYoung))
                    continue
                }
            }

            // Only when the name says nothing, only when the folder opted in, and only
            // when a rule has not already decided. The label maps through the same table
            // the user can see — the model never produces a path.
            var label: ContentLabel?
            if matchedRule == nil, folder.usesIntelligence, let intelligence {
                label = await intelligence.classify(entry)?.label
            }

            // A matched rule files flat into its own folder — the scheme's month or
            // extension nesting is a property of type sorting, not of the rule.
            let components: [String]? = ruleFolder.map { [$0] }
                ?? matchedRule.map { [$0.folderName] }
                ?? label.map { [$0.defaultFolderName] }
                ?? folder.scheme.destinationComponents(
                    category: category,
                    folderName: folder.folderName(for: category),
                    fileExtension: ext,
                    date: modifiedDate(entry) ?? Date()
                )

            let destinationFolder = components.map { parts in
                parts.reduce(folder.url) { $0.appendingPathComponent($1) }
            }
            let proposed = destinationFolder?.appendingPathComponent(entry.lastPathComponent)

            // Before uniquifying into `… 2`, ask whether this is simply the same file
            // again. `report (1).pdf` beside `report.pdf` is the common case, and
            // filing a second identical copy is how a folder doubles in size for no
            // reason. The duplicate is set aside, never removed.
            var isDuplicate = false
            if folder.quarantinesDuplicates,
               let destinationFolder,
               fileManager.fileExists(atPath: destinationFolder.path),
               duplicates.identicalTwin(of: entry, existingIn: destinationFolder) != nil {
                isDuplicate = true
            }

            let target: URL? = isDuplicate
                ? folder.url.appendingPathComponent(folder.duplicatesFolderName)
                    .appendingPathComponent(entry.lastPathComponent)
                : proposed
            let unique = target.map { mover.uniqueDestination(for: $0) }

            // The stability sample is the slow part, so it runs only for entries that
            // have survived every cheap check above.
            let verdict = await stability.verdict(for: entry)

            switch guardRail.decide(for: entry, proposedDestination: unique, stability: verdict) {
            case .move(let destination):
                moves.append(
                    MovedFile(source: entry, destination: destination,
                              category: category, isDuplicate: isDuplicate,
                              contentLabel: label)
                )
            case .skip(let reason):
                // Directories are the normal case in a folder being organised; logging
                // each one would bury the interesting skips.
                if reason != .isDirectory, reason != .isHidden {
                    skips.append(SkippedFile(url: entry, reason: reason))
                }
            }
        }
        // A second of slack, so the retry lands after the threshold rather than on it.
        let retry = shortestWait.map { Duration.seconds(max(1, $0 + 1)) }
        return OrganizePlan(moves: moves, skips: skips, retryAfter: retry)
    }

    /// Plan, then carry the plan out.
    public func run(_ folder: WatchedFolder, trigger: OrganizeRun.Trigger) async -> (run: OrganizeRun, retryAfter: Duration?) {
        // Reset the per-run classification budget before planning.
        await intelligence?.beginRun()
        let planned = await plan(for: folder)
        var performed: [MovedFile] = []
        var failures: [String] = []

        for move in planned.moves {
            do {
                // Re-uniquify at the moment of the move: an earlier move in this same
                // run may have taken the name.
                let final = mover.uniqueDestination(for: move.destination)
                try mover.move(move.source, to: final)
                performed.append(
                    MovedFile(id: move.id, source: move.source, destination: final,
                              category: move.category, isDuplicate: move.isDuplicate,
                              contentLabel: move.contentLabel)
                )
            } catch {
                failures.append("\(move.source.lastPathComponent): \(error)")
            }
        }

        let run = OrganizeRun(
            folder: folder.url, trigger: trigger,
            moved: performed, skipped: planned.skips, failures: failures
        )
        return (run, planned.retryAfter)
    }

    /// Put a run's files back where they came from.
    ///
    /// Possible only because nothing is ever deleted: both ends of every move still
    /// exist, so undo is another move rather than a restore.
    public func undo(_ run: OrganizeRun) async -> OrganizeRun {
        var restored: [MovedFile] = []
        var failures: [String] = []

        for move in run.moved.reversed() {
            do {
                let back = mover.uniqueDestination(for: move.source)
                try mover.move(move.destination, to: back)
                restored.append(
                    MovedFile(source: move.destination, destination: back,
                              category: move.category, isDuplicate: move.isDuplicate)
                )
            } catch {
                failures.append("\(move.fileName): \(error)")
            }
        }

        return OrganizeRun(
            folder: run.folder, trigger: .undo,
            moved: restored, skipped: [], failures: failures
        )
    }

    private func modifiedDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func addedDate(_ url: URL) -> Date? {
        let v = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
        return v?.addedToDirectoryDate ?? v?.contentModificationDate
    }
}
