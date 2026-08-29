import AppKit
import SwiftUI
import TidewellCore

/// The window where folders are configured and history is read.
///
/// A sidebar split rather than a tall settings pane: the content here is a list of
/// things with detail attached, which is exactly what `NavigationSplitView` is for.
struct MainWindow: View {

    static let identifier = "tidewell.main"

    @Environment(AppEnvironment.self) private var env
    @State private var selection: Selection? = .insights

    enum Selection: Hashable {
        case folder(UUID)
        case activity
        case insights
        case appSweep
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Folders") {
                ForEach(env.settings.folders) { folder in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(folder.displayName).lineLimit(1)
                            Text(folder.url.deletingLastPathComponent().path)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    } icon: {
                        Image(systemName: folder.isAutoEnabled ? "folder.fill" : "folder")
                            .foregroundStyle(folder.isAutoEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .tag(Selection.folder(folder.id))
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        }
                        Button("Stop Watching", role: .destructive) {
                            env.removeFolder(folder.id)
                            selection = .activity
                        }
                    }
                }
            }

            Section {
                Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(Selection.insights)
                Label("Activity", systemImage: "clock.arrow.circlepath")
                    .tag(Selection.activity)
                Label("App Sweep", systemImage: "shippingbox")
                    .tag(Selection.appSweep)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                addFolder()
            } label: {
                Label("Add Folder…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .folder(let id):
            if let folder = env.settings.folders.first(where: { $0.id == id }) {
                FolderDetailView(folder: folder)
            } else {
                ContentUnavailableView("Folder removed", systemImage: "folder.badge.questionmark")
            }
        case .insights:
            InsightsView()
        case .appSweep:
            AppSweepView()
        case .activity, nil:
            ActivityView()
        }
    }

    /// Pick a folder. `NSOpenPanel` is also how the app earns access to Downloads or
    /// Desktop: choosing it there is what satisfies macOS's privacy prompt.
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "Choose folders for Tidewell to keep tidy."

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let complaint = env.addPickedFolder(url) {
                let alert = NSAlert()
                alert.messageText = "Can't watch that folder"
                alert.informativeText = complaint
                alert.alertStyle = .warning
                alert.runModal()
            } else if let added = env.settings.folders.last {
                selection = .folder(added.id)
            }
        }
    }
}
