import AppKit
import SwiftUI
import TidewellCore

/// What Tidewell is doing, what is piling up, and what to change about it.
///
/// Not a dashboard. Three honest questions with answers a person can act on, and
/// suggestions that become real settings in one click. The numbers are exact where they
/// can be and openly estimated where they cannot — a made-up "4.2 hours saved" is worse
/// than no number at all.
struct InsightsView: View {

    @Environment(AppEnvironment.self) private var env
    @State private var suggestions: [Suggestion] = []
    @State private var isScanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if env.settings.runs.isEmpty {
                    ContentUnavailableView(
                        "Not enough history yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Once Tidewell has filed a few things, this is where "
                                          + "you will see what it did and what to change.")
                    )
                    .padding(.top, 40)
                } else {
                    activity
                    if !suggestions.isEmpty { suggestionList }
                    breakdown
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("Insights")
        .task { await refresh() }
    }

    // MARK: Activity

    private var activity: some View {
        let runs = env.settings.runs
        let week = runs.filter { $0.startedAt > Date().addingTimeInterval(-7 * 86_400) }
        let filed = week.reduce(0) { $0 + $1.moved.count(where: { !$0.isDuplicate }) }
        let dupes = week.reduce(0) { $0 + $1.duplicateCount }
        let archived = week.filter { $0.trigger == .archive }.reduce(0) { $0 + $1.moved.count }

        return VStack(alignment: .leading, spacing: 9) {
            Text("This week").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                stat("\(filed)", "filed", "tray.full")
                stat("\(dupes)", "duplicates set aside", "doc.on.doc")
                stat("\(archived)", "archived", "archivebox")
                stat("\(runs.count)", "runs kept", "clock.arrow.circlepath")
            }
            if filed > 0 {
                // Stated as an estimate with the assumption visible. A precise-looking
                // fabricated number would be worse than saying nothing.
                Text("Roughly \(max(1, filed * 5 / 60)) minute\(filed * 5 / 60 == 1 ? "" : "s") "
                     + "of filing, assuming five seconds a file by hand.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.tint)
                Text(value).font(.system(size: 19, weight: .medium)).monospacedDigit()
            }
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: Suggestions

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Worth changing").font(.system(size: 12, weight: .semibold))
                Spacer()
                if isScanning { ProgressView().controlSize(.small).scaleEffect(0.7) }
            }
            ForEach(suggestions) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: suggestion.symbol)
                        .font(.system(size: 12)).foregroundStyle(.tint)
                        .frame(width: 18).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title).font(.system(size: 12, weight: .medium))
                        Text(suggestion.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if let apply = suggestion.apply {
                        Button(suggestion.actionTitle) {
                            apply()
                            Task { await refresh() }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(11)
                .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Breakdown

    private var breakdown: some View {
        let counts = env.settings.runs
            .flatMap(\.moved)
            .reduce(into: [FileCategory: Int]()) { $0[$1.category, default: 0] += 1 }
        let total = max(1, counts.values.reduce(0, +))

        return VStack(alignment: .leading, spacing: 9) {
            Text("What Tidewell has filed").font(.system(size: 12, weight: .semibold))
            ForEach(counts.sorted { $0.value > $1.value }.prefix(8), id: \.key) { category, count in
                HStack(spacing: 8) {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(width: 15).accessibilityHidden(true)
                    Text(category.rawValue).font(.system(size: 11)).frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.tint)
                            .frame(width: max(2, geo.size.width * Double(count) / Double(total)))
                    }
                    .frame(height: 7)
                    Text("\(count)").font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(category.rawValue): \(count) files")
            }
        }
    }

    // MARK: Building suggestions

    struct Suggestion: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
        let actionTitle: String
        let apply: (@MainActor () -> Void)?
    }

    private func refresh() async {
        isScanning = true
        defer { isScanning = false }
        var found: [Suggestion] = []

        for folder in env.settings.folders {
            // 1. Filename families a name rule would express better than a category.
            for (stem, count) in Self.families(in: folder.url) where count >= 5 {
                let pattern = "\(stem)*"
                guard !folder.nameRules.contains(where: { $0.pattern == pattern }) else { continue }
                let suggested = stem.trimmingCharacters(in: CharacterSet(charactersIn: "-_ ")).capitalized
                found.append(Suggestion(
                    symbol: "text.magnifyingglass",
                    title: "\(count) files start with “\(stem)”",
                    detail: "In \(folder.displayName). A rule would file them together as "
                          + "\(suggested) instead of scattering them by type.",
                    actionTitle: "Add rule",
                    apply: {
                        var copy = folder
                        copy.nameRules.append(NameRule(pattern: pattern, folderName: suggested))
                        env.update(copy)
                    }
                ))
            }

            // 2. Stale files, when archiving is not yet on.
            if folder.archiveAfterDays == 0 {
                let old = Self.countOlderThan(days: 180, in: folder)
                if old >= 20 {
                    found.append(Suggestion(
                        symbol: "archivebox",
                        title: "\(old) files in \(folder.displayName) are over six months old",
                        detail: "Archiving moves them into Archive/YYYY-MM so the categories "
                              + "stay usable. Nothing is deleted.",
                        actionTitle: "Archive after 180 days",
                        apply: {
                            var copy = folder
                            copy.archiveAfterDays = 180
                            env.update(copy)
                        }
                    ))
                }
            }
        }

        suggestions = Array(found.prefix(4))
    }

    /// Cluster loose filenames by their leading token, so `day-sheet-…` groups together.
    static func families(in url: URL) -> [(String, Int)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        else { return [] }

        var counts: [String: Int] = [:]
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            else { continue }
            let stem = entry.deletingPathExtension().lastPathComponent
            // Cut at the first digit run: that is where a family name usually stops and
            // the date or counter begins.
            guard let cut = stem.firstIndex(where: \.isNumber), cut != stem.startIndex else { continue }
            let prefix = String(stem[..<cut])
            guard prefix.count >= 4 else { continue }
            counts[prefix, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    static func countOlderThan(days: Int, in folder: WatchedFolder) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var roots = [folder.url]
        for name in folder.sweepableFolderNames {
            roots.append(folder.url.appendingPathComponent(name))
        }
        var count = 0
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) else { continue }
            for entry in entries {
                let values = try? entry.resourceValues(
                    forKeys: [.contentModificationDateKey, .isDirectoryKey])
                guard values?.isDirectory == false,
                      let modified = values?.contentModificationDate, modified < cutoff
                else { continue }
                count += 1
            }
        }
        return count
    }
}
