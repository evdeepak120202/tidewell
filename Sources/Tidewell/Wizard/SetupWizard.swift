import AppKit
import SwiftUI
import TidewellCore

/// First run.
///
/// Four screens, one real decision, under a minute. It is deliberately a *preview* rather
/// than a questionnaire: it never asks something it could observe, and it ends by showing
/// what would happen to the user's own files instead of promising what it might do.
///
/// The last screen offers "Just watch from now on", which leaves the existing pile
/// untouched. For a lot of people that backlog is the intimidating part, and an organiser
/// that insists on touching it on day one is one they close.
struct SetupWizard: View {

    static let identifier = "tidewell.wizard"

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissAction) private var dismiss

    @State private var step: Step = .welcome
    @State private var candidates: [FolderCandidate] = []
    @State private var style: OrganizingStyle = .tidy
    @State private var styleWasSuggested = false
    @State private var plans: [UUID: OrganizePlan] = [:]
    @State private var isWorking = false
    @State private var wantsIntelligence = false

    enum Step: Int, CaseIterable { case welcome, folders, style, intelligence, preview }

    /// The intelligence step is skipped entirely on a Mac that cannot run it.
    ///
    /// Showing a screen only to say "your Mac can't do this" is the nagging the plan
    /// rules out — the app must feel designed for that Mac, not apologetic to it.
    private var showsIntelligenceStep: Bool {
        let availability = IntelligenceAvailability.current
        return availability == .ready || availability == .notEnabled
    }

    struct FolderCandidate: Identifiable {
        let id = UUID()
        let url: URL
        var isSelected: Bool
        var looseFileCount: Int
        var counts: [FileCategory: Int]
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 34)
                .padding(.top, 30)

            footer
        }
        .frame(width: 620, height: 560)
        .task { await loadCandidates() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .folders: folders
        case .style:        styleChooser
        case .intelligence: intelligenceOffer
        case .preview:      preview
        }
    }

    // MARK: 1 — Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            TidewellIconTile(canvas: 88)
                .accessibilityHidden(true)

            Text("Tidewell")
                .font(.system(size: 26, weight: .semibold))
                .padding(.top, 16)
            Text("Files land in a folder. Tidewell files them.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 11) {
                promise("checkmark.shield", "It never deletes anything",
                        "Files are moved, never removed. There is no delete anywhere in it.")
                promise("eye", "It shows you first",
                        "Every run can be previewed before a single file moves.")
                promise("arrow.uturn.backward", "You can always undo",
                        "Because nothing is destroyed, any run can be put back.")
            }
            .padding(.top, 26)
            .frame(maxWidth: 420, alignment: .leading)

            Spacer()
        }
    }

    private func promise(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 2 — Folders

    private var folders: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Which folders?", "Tidewell only touches loose files in the folders you "
                   + "pick. Folders inside them are never moved.")

            if candidates.isEmpty {
                ProgressView().frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
            } else {
                VStack(spacing: 6) {
                    ForEach($candidates) { $candidate in
                        Toggle(isOn: $candidate.isSelected) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(candidate.url.lastPathComponent)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(candidate.looseFileCount == 0
                                         ? "Nothing loose right now"
                                         : "\(candidate.looseFileCount) loose file\(candidate.looseFileCount == 1 ? "" : "s")")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(9)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
                    }
                }

                Button {
                    addCustomFolder()
                } label: { Label("Add another folder…", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            Spacer()
        }
    }

    // MARK: 3 — Style

    private var styleChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("How should it file things?",
                   styleWasSuggested
                   ? "Picked based on what is actually in your folders. Change it if you like — nothing here is permanent."
                   : "You can change any of this later, per folder.")

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(OrganizingStyle.allCases) { candidate in
                        StyleCard(style: candidate, isSelected: candidate == style) {
                            style = candidate
                            styleWasSuggested = false
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)
        }
    }

    // MARK: 4 — Intelligence (offered, never required)

    private var intelligenceOffer: some View {
        let availability = IntelligenceAvailability.current

        return VStack(alignment: .leading, spacing: 14) {
            header("Should Tidewell read documents it can't name?",
                   "Entirely optional. Everything else works the same without it.")

            VStack(alignment: .leading, spacing: 12) {
                // Concrete, not abstract: show the actual problem it solves.
                HStack(spacing: 10) {
                    Text("scan_001.pdf")
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text("Documents/").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("without").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    Text("scan_001.pdf")
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text("Invoices/").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tint)
                    Text("with").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 9) {
                promise("lock.shield", "Nothing is uploaded",
                        "The model runs on this Mac. Tidewell has no network code at all.")
                promise("list.bullet", "It only picks a word from a fixed list",
                        "It never chooses a folder path, so a bad guess is just a wrong "
                        + "folder — which you will see in the preview and can undo.")
                promise("slider.horizontal.3", "Off for any folder you don't choose",
                        "Folders named for tax, medical or legal documents stay off unless "
                        + "you say otherwise.")
            }

            if availability == .notEnabled {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Intelligence is turned off on this Mac")
                            .font(.system(size: 11, weight: .medium))
                        Text("macOS downloads the model itself — several gigabytes. "
                             + "Tidewell never downloads anything. You can turn this on "
                             + "later in Tidewell's Settings.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = IntelligenceAvailability.appleIntelligenceSettingsURL {
                            Button("Open System Settings…") { NSWorkspace.shared.open(url) }
                                .controlSize(.small).padding(.top, 2)
                        }
                    }
                }
                .padding(11)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
    }

    // MARK: 5 — Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Here is exactly what would happen",
                   "Nothing has moved yet. This is the real plan for the files you have now.")

            if isWorking {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Checking your folders…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if totalMoves == 0 {
                VStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26)).foregroundStyle(.green)
                    Text("Nothing to file right now")
                        .font(.system(size: 13, weight: .medium))
                    Text("Tidewell will file new files as they arrive.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(selectedCandidates) { candidate in
                            if let plan = plans[candidate.id], !plan.moves.isEmpty {
                                PlanGroup(folderName: candidate.url.lastPathComponent,
                                          root: candidate.url, plan: plan)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .welcome {
                Button("Back") { goBack() }
                    .controlSize(.large)
            }
            Spacer()

            switch step {
            case .welcome:
                Button("Choose folders") { step = .folders }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

            case .folders:
                Button("Continue") { Task { await goToStyle() } }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCandidates.isEmpty)

            case .style:
                Button(showsIntelligenceStep ? "Continue" : "See what happens") {
                    Task { await advanceFromStyle() }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

            case .intelligence:
                Button("Not now") {
                    wantsIntelligence = false
                    Task { await goToPreview() }
                }
                .controlSize(.large)
                Button("Turn it on") {
                    wantsIntelligence = true
                    Task { await goToPreview() }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(IntelligenceAvailability.current != .ready)
                .help(IntelligenceAvailability.current == .ready
                      ? "" : "Turn on Apple Intelligence in System Settings first.")

            case .preview:
                Button("Just watch from now on") { finish(organizeBacklog: false) }
                    .controlSize(.large)
                    .help("Leaves the files you already have where they are, and files only new arrivals.")
                Button(totalMoves == 0 ? "Finish" : "Organise \(totalMoves) file\(totalMoves == 1 ? "" : "s")") {
                    finish(organizeBacklog: true)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .background(.bar)
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 19, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Flow

    private var selectedCandidates: [FolderCandidate] { candidates.filter(\.isSelected) }
    private var totalMoves: Int { plans.values.reduce(0) { $0 + $1.moves.count } }

    private func goBack() {
        guard var previous = Step(rawValue: step.rawValue - 1) else { return }
        // Never land on a step this Mac does not show.
        if previous == .intelligence, !showsIntelligenceStep {
            previous = .style
        }
        step = previous
    }

    private func advanceFromStyle() async {
        if showsIntelligenceStep { step = .intelligence } else { await goToPreview() }
    }

    private func loadCandidates() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let suggested = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
        var found: [FolderCandidate] = []
        for url in suggested where FileManager.default.fileExists(atPath: url.path) {
            let (count, counts) = Self.survey(url)
            found.append(FolderCandidate(url: url, isSelected: url.lastPathComponent == "Downloads",
                                         looseFileCount: count, counts: counts))
        }
        candidates = found
    }

    /// Count loose files and their categories, without touching anything.
    static func survey(_ url: URL) -> (Int, [FileCategory: Int]) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        else { return (0, [:]) }

        let classifier = Classifier()
        var counts: [FileCategory: Int] = [:]
        var total = 0
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false
            else { continue }
            total += 1
            counts[classifier.category(for: entry), default: 0] += 1
        }
        return (total, counts)
    }

    private func addCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !candidates.contains(where: { $0.url == url.standardizedFileURL }) {
            if SafetyGuard.isForbiddenRoot(url) {
                let alert = NSAlert()
                alert.messageText = "Tidewell can't organise that folder"
                alert.informativeText = "\(url.lastPathComponent) is a system or home root. "
                    + "Reorganising it would scatter application data and hidden files."
                alert.runModal()
                continue
            }
            let (count, counts) = Self.survey(url)
            candidates.append(FolderCandidate(url: url.standardizedFileURL, isSelected: true,
                                              looseFileCount: count, counts: counts))
        }
    }

    private func goToStyle() async {
        // Pre-select from what is actually in the chosen folders, so the common case is
        // one click rather than a decision the user has no basis to make yet.
        var combined: [FileCategory: Int] = [:]
        for candidate in selectedCandidates {
            for (category, count) in candidate.counts { combined[category, default: 0] += count }
        }
        style = OrganizingStyle.suggestion(forCounts: combined)
        styleWasSuggested = true
        step = .style
    }

    private func goToPreview() async {
        step = .preview
        isWorking = true
        plans = [:]
        for candidate in selectedCandidates {
            var folder = style.apply(to: WatchedFolder(url: candidate.url))
            folder.nameRules = style.suggestedRules
            plans[candidate.id] = await env.preview(folder)
        }
        isWorking = false
    }

    private func finish(organizeBacklog: Bool) {
        for candidate in selectedCandidates {
            var folder = style.apply(to: WatchedFolder(url: candidate.url))
            folder.nameRules = style.suggestedRules
            // A folder whose name suggests private documents stays off even when the
            // user said yes overall. They can switch it on deliberately.
            folder.usesIntelligence = wantsIntelligence && !folder.looksSensitive
            env.addConfiguredFolder(folder)
        }
        env.settings.hasCompletedSetup = true
        env.settings.chosenStyle = style
        // Both switches are required, so this cannot turn on by accident.
        env.setIntelligenceEnabled(wantsIntelligence && IntelligenceAvailability.current.canRun)
        env.refreshWatchSet()

        if organizeBacklog {
            Task { await env.organizeAll(trigger: .manual) }
        }
        dismiss()
    }
}

// MARK: - Pieces

private struct StyleCard: View {
    let style: OrganizingStyle
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: style.symbolName)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(style.title).font(.system(size: 12, weight: .semibold))
                        Text(style.tagline).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(style.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        ForEach(style.exampleTree, id: \.self) { name in
                            Text(name)
                                .font(.system(size: 9, design: .monospaced))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .accessibilityHidden(true)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.22)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(style.title). \(style.tagline). \(style.detail)")
    }
}

private struct PlanGroup: View {
    let folderName: String
    let root: URL
    let plan: OrganizePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(.tint)
                Text(folderName).font(.system(size: 12, weight: .semibold))
                Text("\(plan.moves.count) file\(plan.moves.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(plan.moves.prefix(40)) { move in
                    HStack(spacing: 6) {
                        Image(systemName: move.isDuplicate ? "doc.on.doc" : move.category.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(move.isDuplicate ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .frame(width: 13)
                        Text(move.source.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                        Image(systemName: "arrow.right").font(.system(size: 7)).foregroundStyle(.tertiary)
                        Text(relative(move.destination))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
                if plan.moves.count > 40 {
                    Text("and \(plan.moves.count - 40) more")
                        .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.leading, 19)
                }
            }
            .padding(.leading, 4)
        }
    }

    private func relative(_ url: URL) -> String {
        let base = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(base) else { return url.lastPathComponent }
        return String(full.dropFirst(base.count).drop(while: { $0 == "/" }))
    }
}
