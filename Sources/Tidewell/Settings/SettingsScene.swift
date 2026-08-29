import AppKit
import SwiftUI
import TidewellCore

/// App-wide preferences.
///
/// Height is fixed deliberately. Letting a `Form` size to its content pushes a long pane
/// taller than the usable screen, and the bottom then sits behind the Dock with no way to
/// scroll to it — the pane has to scroll internally instead.
struct SettingsScene: View {

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            IntelligenceSettings().tabItem { Label("Intelligence", systemImage: "sparkles") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .environment(env)
        .frame(width: 540, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {

    @Environment(AppEnvironment.self) private var env
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var settings = env.settings

        Form {
            Section {
                Toggle("File automatically as files arrive", isOn: $settings.isAutoEnabled)
                    .onChange(of: settings.isAutoEnabled) { _, _ in env.refreshWatchSet() }
                Text("When off, nothing moves until you press Organize. Each folder also has "
                     + "its own switch — both have to be on.")
                    .settingsFootnote()
            } header: {
                Text("Filing")
            }

            Section {
                Toggle("Open Tidewell at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { wanted in
                        if case .failure(let error) = LoginItem.setEnabled(wanted) {
                            loginItemError = error.localizedDescription
                        } else {
                            loginItemError = nil
                        }
                    }
                ))
                LabeledContent("Status") {
                    Text(LoginItem.statusDescription).foregroundStyle(.secondary)
                }
                if let loginItemError {
                    Label(loginItemError, systemImage: "exclamationmark.triangle")
                        .settingsFootnote()
                        .foregroundStyle(.red)
                }
                Text("Tidewell registers through the system's Login Items, so you can always "
                     + "revoke it in System Settings › General › Login Items.")
                    .settingsFootnote()
            } header: {
                Text("Start-up")
            }

            Section {
                Toggle("Show a notification", isOn: $settings.notifiesOnFile)
                Toggle("Play a sound", isOn: $settings.playsSoundOnFile)
                Text("A run that moved nothing never notifies. Notifications carry Undo and "
                     + "Reveal buttons, so you never have to open the app to reverse one.")
                    .settingsFootnote()
            } header: {
                Text("When files are filed")
            }

            Section {
                LabeledContent("History") {
                    Text("\(env.settings.runs.count) run\(env.settings.runs.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Reveal Settings File") {
                        NSWorkspace.shared.activateFileViewerSelecting([Settings.storeURL])
                    }
                    Spacer()
                    Button("Run Setup Again…") { WizardPresenter.shared.show() }
                }
            } header: {
                Text("Data")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Intelligence

private struct IntelligenceSettings: View {

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let availability = env.intelligenceAvailability
        let isOn = env.settings.intelligenceEnabled

        Form {
            Section {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: availability.canRun ? "checkmark.seal.fill" : "info.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(availability.canRun ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(availability.headline).font(.system(size: 12, weight: .medium))
                        Text(availability.detail)
                            .settingsFootnote()
                        if availability.offersSystemSettings,
                           let url = IntelligenceAvailability.appleIntelligenceSettingsURL {
                            Button("Open System Settings…") { NSWorkspace.shared.open(url) }
                                .controlSize(.small)
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(.vertical, 3)
            }

            // The whole point of the feature, shown rather than described.
            Section {
                ComparisonRow(fileName: "scan_001.pdf",
                              without: "Documents/", with: "Invoices/")
                ComparisonRow(fileName: "IMG_4821.png",
                              without: "Images/", with: "Receipts/")
                ComparisonRow(fileName: "document.pdf",
                              without: "Documents/", with: "Contracts/")
                Text("Only for files whose name says nothing. Something called "
                     + "“Electricity Bill March.pdf” is already clear, so Tidewell never "
                     + "reads it.")
                    .settingsFootnote()
            } header: {
                Text("What it changes")
            }

            Section {
                Toggle("Read documents Tidewell can't name", isOn: Binding(
                    get: { isOn },
                    set: { env.setIntelligenceEnabled($0) }
                ))
                .disabled(!availability.canRun)

                if !availability.canRun {
                    Text("Everything else in Tidewell works exactly the same without this.")
                        .settingsFootnote()
                }
            } header: {
                Text("On-device reading")
            } footer: {
                if isOn {
                    Text("Turning this off forgets everything it learned and switches it off "
                         + "for every folder.")
                        .settingsFootnote()
                }
            }

            if isOn && availability.canRun {
                Section {
                    if env.settings.folders.isEmpty {
                        Text("No folders yet.").settingsFootnote()
                    }
                    ForEach(env.settings.folders) { folder in
                        Toggle(isOn: Binding(
                            get: { folder.usesIntelligence },
                            set: { var copy = folder; copy.usesIntelligence = $0; env.update(copy) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.displayName)
                                if folder.looksSensitive {
                                    Label("Left off — the name suggests private documents",
                                          systemImage: "hand.raised")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Which folders")
                } footer: {
                    Text("Off for every folder until you choose it here.")
                        .settingsFootnote()
                }

                Section {
                    Fact("lock.shield", "Nothing leaves this Mac",
                         "The model runs locally. Tidewell has no network code at all.")
                    Fact("list.bullet", "It picks one word from a fixed list",
                         "It never chooses a folder path, so a wrong guess is just a wrong "
                         + "folder — shown in the preview, and undoable.")
                    Fact("bolt.slash", "Skipped when your Mac is busy",
                         "Never runs in Low Power Mode or when the Mac is running hot.")
                    LabeledContent("Remembered") {
                        Text("\(env.settings.classificationCache.count) file\(env.settings.classificationCache.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    Button("Forget What It Learned") { env.purgeClassificationCache() }
                        .disabled(env.settings.classificationCache.isEmpty)
                } header: {
                    Text("How it behaves")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// One before/after line: what a file does without the feature, and with it.
private struct ComparisonRow: View {
    let fileName: String
    let without: String
    let with: String

    var body: some View {
        HStack(spacing: 8) {
            Text(fileName)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 118, alignment: .leading)
                .lineLimit(1)

            Text(without)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(with)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tint)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fileName) goes to \(without) without this, and \(with) with it")
    }
}

private struct Fact: View {
    let symbol: String
    let title: String
    let detail: String

    init(_ symbol: String, _ title: String, _ detail: String) {
        self.symbol = symbol; self.title = title; self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).settingsFootnote()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                TidewellIconTile(canvas: 88).accessibilityHidden(true)

                VStack(spacing: 3) {
                    Text("Tidewell").font(.system(size: 17, weight: .semibold))
                    Text("Files land in a folder. Tidewell files them.")
                        .settingsFootnote()
                    Text(Self.versionString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                GroupBox("What it will never do") {
                    VStack(alignment: .leading, spacing: 6) {
                        Guarantee("Delete or trash a file — it can only move")
                        Guarantee("Overwrite anything — collisions get renamed")
                        Guarantee("Touch a folder, only loose files")
                        Guarantee("Move a file that is still downloading")
                        Guarantee("Send anything anywhere — there is no network code")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                }

                HStack(spacing: 14) {
                    Link("iam-deepak.space", destination: URL(string: "https://iam-deepak.space")!)
                    Link("Source", destination: URL(string: "https://github.com/evdeepak120202/tidewell")!)
                }
                .font(.system(size: 11))

                Text("GPL-3.0-or-later · personal build, not notarised")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}

private struct Guarantee: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 10))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 11))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared

private extension View {
    /// Secondary explanatory text, sized and coloured the same everywhere.
    func settingsFootnote() -> some View {
        self.font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
