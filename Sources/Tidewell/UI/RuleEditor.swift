import SwiftUI
import TidewellCore

/// The rules list for one folder.
///
/// Hazel's rule builder is the most capable thing in this category and also the reason
/// people bounce off it: a blank sheet with nested predicate rows asks you to design a
/// system before you have filed a single file. This starts from the finished sentence —
/// each rule reads as one line of English — and only opens the parts when you ask.
struct RuleEditor: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rules").font(.system(size: 12, weight: .semibold))
                Spacer()
                Menu {
                    Button("Blank rule") { add(.blank) }
                    Divider()
                    Text("Or start from one of these")
                    Button("Big downloads → Needs Review") { add(.bigFiles) }
                    Button("Screenshots → Screenshots/") { add(.screenshots) }
                    Button("Old installers → Needs Review") { add(.oldInstallers) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }

            Text("Checked before name patterns and before file type, top to bottom. "
                 + "The first rule that matches decides.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if folder.rules.isEmpty {
                Text("No rules. Type sorting handles everything.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(folder.rules.enumerated()), id: \.element.id) { index, rule in
                        RuleRow(
                            folder: folder,
                            index: index,
                            rule: rule,
                            isExpanded: expanded == rule.id,
                            toggle: { expanded = expanded == rule.id ? nil : rule.id }
                        )
                    }
                }
            }
        }
    }

    private enum Starter { case blank, bigFiles, screenshots, oldInstallers }

    private func add(_ starter: Starter) {
        var copy = folder
        copy.rules.append(Self.rule(for: starter))
        env.update(copy)
        expanded = copy.rules.last?.id
    }

    /// Starters exist because a blank rule is the hardest thing to face. Each one is a
    /// real, complete rule the user can edit rather than a placeholder.
    private static func rule(for starter: Starter) -> Rule {
        switch starter {
        case .blank:
            Rule(name: "New rule", conditions: [.nameContains("")], actions: [.moveTo("")])
        case .bigFiles:
            Rule(name: "Big downloads", match: .all,
                 conditions: [.largerThan(megabytes: 500)], actions: [.markForReview])
        case .screenshots:
            Rule(name: "Screenshots", match: .any,
                 conditions: [.nameHasPrefix("Screenshot"), .nameHasPrefix("CleanShot")],
                 actions: [.moveTo("Screenshots")])
        case .oldInstallers:
            Rule(name: "Old installers", match: .all,
                 conditions: [.categoryIs(.installers), .olderThan(days: 30)],
                 actions: [.markForReview])
        }
    }
}

// MARK: - One rule

private struct RuleRow: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder
    let index: Int
    let rule: Rule
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Toggle("", isOn: bind(\.isEnabled))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Rule enabled")

                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.name.isEmpty ? "Untitled rule" : rule.name)
                        .font(.system(size: 12))
                    Text(rule.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if !rule.isUsable && rule.isEnabled {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help("This rule has nothing to test, or nothing to do, so it never fires.")
                }

                Button {
                    var copy = folder
                    copy.rules.swapAt(index, index - 1)
                    env.update(copy)
                } label: { Image(systemName: "chevron.up").font(.system(size: 9)) }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityLabel("Move rule up")
                    .help("Earlier rules win — order is priority.")

                Button(action: toggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "slider.horizontal.3")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "Hide rule details" : "Edit rule")

                Button {
                    var copy = folder
                    copy.rules.remove(at: index)
                    env.update(copy)
                } label: { Image(systemName: "minus.circle").font(.system(size: 10)) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove rule")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if isExpanded { details }
        }
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()

            HStack(spacing: 8) {
                TextField("Rule name", text: bind(\.name))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Picker("", selection: bind(\.match)) {
                    ForEach(MatchMode.allCases, id: \.self) { mode in
                        Text("match \(mode.rawValue)").tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
            }

            // Conditions
            VStack(alignment: .leading, spacing: 4) {
                Text("When").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                ForEach(Array(rule.conditions.enumerated()), id: \.offset) { i, condition in
                    ConditionRow(folder: folder, ruleIndex: index, conditionIndex: i, condition: condition)
                }
                Button {
                    edit { $0.conditions.append(.nameContains("")) }
                } label: { Label("Add condition", systemImage: "plus").font(.system(size: 11)) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }

            // Actions
            VStack(alignment: .leading, spacing: 4) {
                Text("Then").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                ForEach(Array(rule.actions.enumerated()), id: \.offset) { i, action in
                    ActionRow(folder: folder, ruleIndex: index, actionIndex: i, action: action)
                }
                Button {
                    edit { $0.actions.append(.moveTo("")) }
                } label: { Label("Add action", systemImage: "plus").font(.system(size: 11)) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }

            Text("Actions can move, tag, label, or set a file aside. There is deliberately "
                 + "no delete and no script — a mistyped rule should cost you a misfiled "
                 + "file, not a lost one.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 2)
    }

    private func edit(_ change: (inout Rule) -> Void) {
        var copy = folder
        guard copy.rules.indices.contains(index) else { return }
        change(&copy.rules[index])
        env.update(copy)
    }

    private func bind<V>(_ path: WritableKeyPath<Rule, V>) -> Binding<V> {
        Binding(
            get: { rule[keyPath: path] },
            set: { newValue in edit { $0[keyPath: path] = newValue } }
        )
    }
}

// MARK: - Condition and action rows

/// One condition: pick the kind, then fill in whatever that kind needs.
///
/// The value editor changes with the kind rather than showing every field greyed out, so
/// the row only ever asks for what it actually uses.
private struct ConditionRow: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder
    let ruleIndex: Int
    let conditionIndex: Int
    let condition: RuleCondition

    private enum Kind: String, CaseIterable {
        case matches = "name matches"
        case contains = "name contains"
        case prefix = "name starts with"
        case suffix = "name ends with"
        case ext = "extension is"
        case kind = "kind is"
        case larger = "larger than"
        case smaller = "smaller than"
        case older = "older than"
        case newer = "added within"
        case duplicate = "is a duplicate"
    }

    private var currentKind: Kind {
        switch condition {
        case .nameMatches:  .matches
        case .nameContains: .contains
        case .nameHasPrefix: .prefix
        case .nameHasSuffix: .suffix
        case .extensionIs:  .ext
        case .categoryIs:   .kind
        case .largerThan:   .larger
        case .smallerThan:  .smaller
        case .olderThan:    .older
        case .newerThan:    .newer
        case .isDuplicate:  .duplicate
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { currentKind },
                set: { replace(with: Self.blank(for: $0)) }
            )) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 138)

            valueEditor

            Spacer(minLength: 0)

            Button {
                mutate { $0.conditions.remove(at: conditionIndex) }
            } label: { Image(systemName: "minus.circle").font(.system(size: 9)) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove condition")
        }
    }

    // Bindings are built inline rather than through helpers: routing them through a
    // function parameter strips the main-actor isolation the view already has, and
    // `Binding.set` is `@Sendable`, so the two cannot be reconciled without pretending.
    @ViewBuilder
    private var valueEditor: some View {
        switch condition {
        case .nameMatches(let text):
            TextField("day-sheet-*", text: Binding(
                get: { text }, set: { replace(with: .nameMatches($0)) }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 190)

        case .nameContains(let text):
            TextField("invoice", text: Binding(
                get: { text }, set: { replace(with: .nameContains($0)) }))
                .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(maxWidth: 190)

        case .nameHasPrefix(let text):
            TextField("Screenshot", text: Binding(
                get: { text }, set: { replace(with: .nameHasPrefix($0)) }))
                .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(maxWidth: 190)

        case .nameHasSuffix(let text):
            TextField(".pdf", text: Binding(
                get: { text }, set: { replace(with: .nameHasSuffix($0)) }))
                .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(maxWidth: 190)

        case .extensionIs(let list):
            TextField("pdf, png", text: Binding(
                get: { list.joined(separator: ", ") },
                set: { raw in
                    let parts = raw.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty }
                    replace(with: .extensionIs(parts))
                }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 190)

        case .categoryIs(let category):
            Picker("", selection: Binding(
                get: { category }, set: { replace(with: .categoryIs($0)) })) {
                    ForEach(FileCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 118)

        case .largerThan(let mb):
            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { mb }, set: { replace(with: .largerThan(megabytes: $0)) }),
                    format: .number)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 62)
                Text("MB").font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .smallerThan(let mb):
            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { mb }, set: { replace(with: .smallerThan(megabytes: $0)) }),
                    format: .number)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 62)
                Text("MB").font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .olderThan(let days):
            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { days }, set: { replace(with: .olderThan(days: $0)) }),
                    format: .number)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 62)
                Text("days").font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .newerThan(let days):
            HStack(spacing: 4) {
                TextField("0", value: Binding(
                    get: { days }, set: { replace(with: .newerThan(days: $0)) }),
                    format: .number)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).frame(width: 62)
                Text("days").font(.system(size: 11)).foregroundStyle(.secondary)
            }

        case .isDuplicate:
            Text("of something already filed")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// A fresh condition of the chosen kind, with an empty value — never carrying the old
    /// value across, which would silently mean something different.
    private static func blank(for kind: Kind) -> RuleCondition {
        switch kind {
        case .matches:   .nameMatches("")
        case .contains:  .nameContains("")
        case .prefix:    .nameHasPrefix("")
        case .suffix:    .nameHasSuffix("")
        case .ext:       .extensionIs([])
        case .kind:      .categoryIs(.documents)
        case .larger:    .largerThan(megabytes: 100)
        case .smaller:   .smallerThan(megabytes: 1)
        case .older:     .olderThan(days: 30)
        case .newer:     .newerThan(days: 7)
        case .duplicate: .isDuplicate
        }
    }

    private func replace(with new: RuleCondition) {
        mutate { $0.conditions[conditionIndex] = new }
    }

    private func mutate(_ change: (inout Rule) -> Void) {
        var copy = folder
        guard copy.rules.indices.contains(ruleIndex),
              copy.rules[ruleIndex].conditions.indices.contains(conditionIndex) else { return }
        change(&copy.rules[ruleIndex])
        env.update(copy)
    }
}

/// One action. The list is short on purpose — see `RuleAction`.
private struct ActionRow: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder
    let ruleIndex: Int
    let actionIndex: Int
    let action: RuleAction

    private enum Kind: String, CaseIterable {
        case move = "file into"
        case tag = "tag as"
        case label = "colour label"
        case leave = "leave alone"
        case review = "set aside for review"
    }

    private var currentKind: Kind {
        switch action {
        case .moveTo:         .move
        case .addFinderTag:   .tag
        case .setColourLabel: .label
        case .leaveAlone:     .leave
        case .markForReview:  .review
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { currentKind }, set: { replace(with: Self.blank(for: $0)) }
            )) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 138)

            switch action {
            case .moveTo(let folderName):
                TextField("Invoices", text: Binding(
                    get: { folderName }, set: { replace(with: .moveTo($0)) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(maxWidth: 170)
            case .addFinderTag(let tag):
                TextField("Receipts", text: Binding(
                    get: { tag }, set: { replace(with: .addFinderTag($0)) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(maxWidth: 170)
            case .setColourLabel(let index):
                Picker("", selection: Binding(
                    get: { index }, set: { replace(with: .setColourLabel($0)) }
                )) {
                    ForEach(0..<8, id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .frame(width: 62)
            case .leaveAlone, .markForReview:
                EmptyView()
            }

            Spacer(minLength: 0)

            Button {
                mutate { $0.actions.remove(at: actionIndex) }
            } label: { Image(systemName: "minus.circle").font(.system(size: 9)) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove action")
        }
    }

    private static func blank(for kind: Kind) -> RuleAction {
        switch kind {
        case .move:   .moveTo("")
        case .tag:    .addFinderTag("")
        case .label:  .setColourLabel(1)
        case .leave:  .leaveAlone
        case .review: .markForReview
        }
    }

    private func replace(with new: RuleAction) { mutate { $0.actions[actionIndex] = new } }

    private func mutate(_ change: (inout Rule) -> Void) {
        var copy = folder
        guard copy.rules.indices.contains(ruleIndex),
              copy.rules[ruleIndex].actions.indices.contains(actionIndex) else { return }
        change(&copy.rules[ruleIndex])
        env.update(copy)
    }
}
