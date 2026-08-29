import AppKit
import SwiftUI
import TidewellCore

/// Everything configurable about one folder, plus a dry-run preview.
///
/// The preview is the point of this screen: an organiser that moves files is only
/// trustworthy if you can see what it intends to do first.
struct FolderDetailView: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder

    @State private var moves: [MovedFile] = []
    @State private var skips: [SkippedFile] = []
    @State private var isPreviewing = false
    @State private var hasPreviewed = false
    @State private var archivePending = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heading
                schemeSection
                RuleEditor(folder: folder)
                nameRulesSection
                rulesSection
                housekeepingSection
                previewSection
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(folder.displayName)
        .task(id: folder.id) { await runPreview() }
    }

    private var binding: Binding<WatchedFolder> {
        Binding(get: { folder }, set: { env.update($0) })
    }

    // MARK: Sections

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Only loose files here are filed. Folders are never moved or deleted.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Auto", isOn: binding.isAutoEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var schemeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sort into").font(.system(size: 12, weight: .semibold))
            Picker("", selection: binding.scheme) {
                ForEach(SortScheme.allCases) { scheme in
                    Text(scheme.title).tag(scheme)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(folder.scheme.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Wait before filing")
                    .font(.system(size: 11))
                Picker("", selection: binding.minimumAgeSeconds) {
                    Text("Immediately").tag(0)
                    Text("30 seconds").tag(30)
                    Text("5 minutes").tag(300)
                    Text("1 hour").tag(3600)
                    Text("1 day").tag(86_400)
                }
                .labelsHidden()
                .frame(width: 150)
            }
            .padding(.top, 4)
        }
    }

    /// Filename patterns, checked before type. Ordered — first match wins.
    private var nameRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Name patterns").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    var copy = folder
                    copy.nameRules.append(NameRule(pattern: "", folderName: ""))
                    env.update(copy)
                } label: { Label("Add", systemImage: "plus") }
                    .controlSize(.small)
            }
            Text("A simpler form of the rules above: just a filename pattern and a folder. "
                 + "Checked after rules, before file type.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if folder.nameRules.isEmpty {
                Text("No patterns yet. e.g. day-sheet-*  →  Day Sheets")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(folder.nameRules.enumerated()), id: \.element.id) { index, rule in
                        NameRuleRow(folder: folder, index: index, rule: rule)
                    }
                }
            }
        }
    }

    private var housekeepingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Housekeeping").font(.system(size: 12, weight: .semibold))

            Toggle(isOn: Binding(
                get: { folder.quarantinesDuplicates },
                set: { var c = folder; c.quarantinesDuplicates = $0; env.update(c) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Set aside byte-identical copies")
                    Text("A file whose contents already exist in the destination goes to "
                         + "\(folder.duplicatesFolderName)/ instead of being filed twice. "
                         + "Nothing is ever deleted.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Always shown, never silently absent. A control that disappears when a
            // global switch is off leaves the user unable to tell whether the feature
            // exists, is broken, or is simply elsewhere.
            IntelligenceRow(folder: folder)

            HStack(spacing: 8) {
                Text("Archive filed files older than").font(.system(size: 11))
                Picker("", selection: Binding(
                    get: { folder.archiveAfterDays },
                    set: { var c = folder; c.archiveAfterDays = $0; env.update(c) }
                )) {
                    Text("Never").tag(0)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("1 year").tag(365)
                }
                .labelsHidden()
                .frame(width: 130)

                if folder.archiveAfterDays > 0 {
                    Button("Archive Now") {
                        Task {
                            await env.archiveNow(folder)
                            await runPreview()
                        }
                    }
                    .controlSize(.small)
                }
                Spacer()
            }

            if folder.archiveAfterDays > 0 {
                Text("Moves stale files out of the category folders into "
                     + "\(folder.archiveFolderName)/YYYY-MM. A move, not a delete — "
                     + "and the archive is never swept into itself.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if archivePending > 0 {
                    Text("\(archivePending) file\(archivePending == 1 ? "" : "s") ready to archive.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories").font(.system(size: 12, weight: .semibold))
            Text("Untick to leave a kind of file where it is. Rename to change the folder it goes into.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
                ForEach(FileCategory.allCases) { category in
                    CategoryRow(folder: folder, category: category)
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview").font(.system(size: 12, weight: .semibold))
                Spacer()
                if isPreviewing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Button("Refresh") { Task { await runPreview() } }
                    .controlSize(.small)
                    .disabled(isPreviewing)
                Button("Organize Now") {
                    Task {
                        await env.organize(folder, trigger: .manual)
                        await runPreview()
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(moves.isEmpty || isPreviewing)
            }

            if !hasPreviewed {
                Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if moves.isEmpty && skips.isEmpty {
                Label("Nothing loose in this folder.", systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                if !moves.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(moves) { move in
                            HStack(spacing: 6) {
                                Image(systemName: move.isDuplicate ? "doc.on.doc"
                                      : move.contentLabel?.symbolName ?? move.category.symbolName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(move.isDuplicate
                                                     ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                                    .frame(width: 14)
                                Text(move.source.lastPathComponent)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Text(relativeDestination(move))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                // Always say when a model decided this, so the user can
                                // see it and correct it rather than wonder.
                                if let label = move.contentLabel {
                                    Text("read as \(label.rawValue)")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.tint)
                                }
                                Spacer()
                            }
                        }
                    }
                }

                if !skips.isEmpty {
                    DisclosureGroup("\(skips.count) left alone") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(skips) { skip in
                                HStack(spacing: 6) {
                                    Text(skip.fileName)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Text(skip.reason.rawValue)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }

    /// Destination shown relative to the watched folder — the absolute path is
    /// mostly the folder you are already looking at.
    private func relativeDestination(_ move: MovedFile) -> String {
        let base = folder.url.standardizedFileURL.path
        let full = move.destination.standardizedFileURL.path
        guard full.hasPrefix(base) else { return move.destination.path }
        return String(full.dropFirst(base.count).drop(while: { $0 == "/" }))
    }

    private var intelligenceState: (canToggle: Bool, note: String?) {
        let availability = env.intelligenceAvailability
        if !availability.canRun {
            return (false, availability.headline)
        }
        if !env.settings.intelligenceEnabled {
            return (false, "Turn on document reading in Settings › Intelligence first.")
        }
        if folder.looksSensitive {
            return (true, "This folder's name suggests private documents, so it starts off.")
        }
        return (true, nil)
    }

    private func runPreview() async {
        isPreviewing = true
        let plan = await env.preview(folder)
        moves = plan.moves
        skips = plan.skips
        archivePending = env.archivePreview(folder).count
        isPreviewing = false
        hasPreviewed = true
    }
}

/// One category: on/off, and the folder name it files into.
private struct CategoryRow: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder
    let category: FileCategory

    private var isOn: Bool { !folder.ignoredCategories.contains(category) }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { enabled in
                    var copy = folder
                    if enabled { copy.ignoredCategories.remove(category) }
                    else { copy.ignoredCategories.insert(category) }
                    env.update(copy)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: category.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)

            TextField(
                category.defaultFolderName,
                text: Binding(
                    get: { folder.folderName(for: category) },
                    set: { newValue in
                        var copy = folder
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        // An empty name would produce a path component of "", which
                        // silently files into the watched folder itself.
                        if trimmed.isEmpty || trimmed == category.defaultFolderName {
                            copy.folderNames.removeValue(forKey: category)
                        } else {
                            copy.folderNames[category] = trimmed
                        }
                        env.update(copy)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .disabled(!isOn)
        }
    }
}


/// One name rule: pattern, destination folder, and its place in the order.
private struct NameRuleRow: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder
    let index: Int
    let rule: NameRule

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: bind(\.isEnabled))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Rule enabled")

            TextField("day-sheet-*", text: bind(\.pattern))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            TextField("Day Sheets", text: bind(\.folderName))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)

            // Order is priority, so moving a rule up is a real edit, not decoration.
            Button {
                var copy = folder
                copy.nameRules.swapAt(index, index - 1)
                env.update(copy)
            } label: { Image(systemName: "chevron.up").font(.system(size: 9)) }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .accessibilityLabel("Move rule up")
                .help("Earlier rules win — order is priority.")

            Button {
                var copy = folder
                copy.nameRules.remove(at: index)
                env.update(copy)
            } label: { Image(systemName: "minus.circle").font(.system(size: 10)) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove rule")
        }
        .opacity(rule.isUsable ? 1 : 0.55)
        .help(rule.isUsable ? "" : "A rule needs both a pattern and a folder before it does anything.")
    }

    private func bind<V>(_ path: WritableKeyPath<NameRule, V>) -> Binding<V> {
        Binding(
            get: { rule[keyPath: path] },
            set: { newValue in
                var copy = folder
                guard copy.nameRules.indices.contains(index) else { return }
                copy.nameRules[index][keyPath: path] = newValue
                env.update(copy)
            }
        )
    }
}


/// Per-folder document reading, with the reason it is unavailable when it is.
private struct IntelligenceRow: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder

    var body: some View {
        let availability = env.intelligenceAvailability
        let globallyOn = env.settings.intelligenceEnabled
        let usable = availability.canRun && globallyOn

        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: Binding(
                get: { folder.usesIntelligence && usable },
                set: { var copy = folder; copy.usesIntelligence = $0; env.update(copy) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Read documents this folder can't name")
                    Text("A scan called scan_001.pdf gets filed as an invoice or a contract "
                         + "instead of just “Documents”. On-device only.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!usable)

            // Say *why* it is unavailable, and offer the way to fix it.
            if !availability.canRun {
                Label(availability.headline, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if !globallyOn {
                HStack(spacing: 6) {
                    Label("Turned off for all folders", systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Open Settings…") {
                        WindowPresenter.focusSettings()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                }
            } else if folder.looksSensitive {
                Label("This folder's name suggests private documents — it stays off unless "
                      + "you choose it.", systemImage: "hand.raised")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
