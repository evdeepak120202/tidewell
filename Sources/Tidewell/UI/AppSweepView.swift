import AppKit
import SwiftUI
import TidewellCore

/// Find what a removed app left behind.
///
/// Two grants are needed and both are asked for explicitly: the app itself, so its bundle
/// identifier can be read, and your Library folder, so the leftovers can be found. Inside
/// the sandbox neither is available without you choosing it, which is the point.
struct AppSweepView: View {

    @Environment(AppEnvironment.self) private var env

    @State private var appURL: URL?
    @State private var bundleID: String?
    @State private var libraryURL: URL?
    @State private var found: [AppSweep.Leftover] = []
    @State private var selected: Set<UUID> = []
    @State private var isScanning = false
    @State private var didScan = false
    @State private var message: String?

    private let sweep = AppSweep()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                steps
                if didScan { results }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("App Sweep")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Find what a removed app left behind")
                .font(.system(size: 15, weight: .medium))
            Text("Dragging an app to the Bin leaves its preferences, caches and support "
                 + "folders on disk. Tidewell finds them and moves them somewhere you can "
                 + "look through — it does not delete them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "Choose the app", appURL?.lastPathComponent) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                panel.prompt = "Choose"
                panel.message = "Choose the app whose leftovers you want to find."
                guard panel.runModal() == .OK, let url = panel.url else { return }
                appURL = url
                bundleID = sweep.bundleIdentifier(of: url)
                found = []; didScan = false
                message = bundleID == nil
                    ? "Couldn't read that app's identifier — it may not be a normal app bundle."
                    : nil
            }

            if let bundleID {
                Text(bundleID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }

            step(2, "Allow access to your Library", libraryURL == nil ? nil : "Granted") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.directoryURL = FileManager.default
                    .homeDirectoryForCurrentUser.appendingPathComponent("Library")
                panel.prompt = "Allow"
                panel.message = "Choose your Library folder so Tidewell can look for leftovers."
                guard panel.runModal() == .OK, let url = panel.url else { return }
                libraryURL = url
                found = []; didScan = false
            }

            Text("Tidewell is sandboxed, so it cannot look inside Library until you choose "
                 + "it here. That is one extra step, and the reason the app cannot wander.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, 26)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Find Leftovers") { scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(bundleID == nil || libraryURL == nil || isScanning)
                if isScanning { ProgressView().controlSize(.small).scaleEffect(0.7) }
                if let message {
                    Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            .padding(.top, 2)
        }
    }

    private func step(
        _ number: Int, _ title: String, _ value: String?, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10, weight: .medium))
                .frame(width: 17, height: 17)
                .background(value == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint),
                            in: Circle())
                .foregroundStyle(value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            Button(title, action: action).controlSize(.small)
            if let value {
                Text(value).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var results: some View {
        if found.isEmpty {
            Label("Nothing left behind.", systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("\(found.count) item\(found.count == 1 ? "" : "s") · \(totalSize)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(selected.count == found.count ? "Select None" : "Select All") {
                        selected = selected.count == found.count ? [] : Set(found.map(\.id))
                    }
                    .controlSize(.small)
                }

                VStack(spacing: 3) {
                    ForEach(found) { item in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { selected.contains(item.id) },
                                set: { on in
                                    if on { selected.insert(item.id) } else { selected.remove(item.id) }
                                }
                            ))
                            .toggleStyle(.checkbox).labelsHidden()
                            .accessibilityLabel("Include \(item.name)")

                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.name).font(.system(size: 11.5)).lineLimit(1)
                                Text(item.area).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(byteText(item.sizeBytes))
                                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: { Image(systemName: "arrow.up.forward.app").font(.system(size: 9)) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Reveal \(item.name) in Finder")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                HStack(spacing: 10) {
                    Button("Set Aside \(selected.count) Item\(selected.count == 1 ? "" : "s")") {
                        gather()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)

                    Text("Moved into a folder you choose. Nothing is deleted, and the run "
                         + "appears in Activity where it can be undone.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
    }

    private var totalSize: String {
        byteText(found.reduce(0) { $0 + $1.sizeBytes })
    }

    private func byteText(_ bytes: Int64) -> String {
        bytes < 1_048_576
            ? "\(max(1, bytes / 1024)) KB"
            : String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func scan() {
        guard let bundleID, let libraryURL else { return }
        isScanning = true
        Task {
            let result = sweep.leftovers(forBundleID: bundleID, in: libraryURL)
            found = result
            selected = Set(result.map(\.id))
            isScanning = false
            didScan = true
        }
    }

    private func gather() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Set Aside Here"
        panel.message = "Choose where to put the leftovers so you can look through them."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let chosen = found.filter { selected.contains($0.id) }
        let name = appURL?.deletingPathExtension().lastPathComponent ?? "App"
        let run = sweep.gather(chosen, forApp: name, into: destination)
        env.settings.record(run)
        message = run.failures.isEmpty
            ? "Moved \(run.moved.count) item\(run.moved.count == 1 ? "" : "s") — see Activity to undo."
            : "Moved \(run.moved.count), \(run.failures.count) failed."
        scan()
    }
}
