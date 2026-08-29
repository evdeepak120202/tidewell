import SwiftUI
import TidewellCore

/// The popover behind the status item.
///
/// Sized for a glance and one action: is filing on, which folders are live, file
/// them now. Anything that needs reading rather than glancing lives in the window.
struct MenuBarContent: View {

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var contentHeight: CGFloat = 0

    private let maxListHeight: CGFloat = 260

    var body: some View {
        @Bindable var settings = env.settings

        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 8)

            if env.settings.folders.isEmpty {
                emptyState
            } else {
                todaySection
                    .padding(.bottom, 6)
                folderList
            }

            Divider().padding(.vertical, 8)

            footer
        }
        .padding(12)
        .frame(width: 320)
        .gentleAnimation(env.settings.folders.count)
    }

    // MARK: Pieces

    private var header: some View {
        @Bindable var settings = env.settings
        return HStack(spacing: 10) {
            TidewellMark(side: 20)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tidewell").font(.system(size: 13, weight: .semibold))
                Text(env.lastRunSummary ?? statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $settings.isAutoEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .onChange(of: env.settings.isAutoEnabled) { _, _ in env.refreshWatchSet() }
                .help("Automatic filing")
                .accessibilityLabel("Automatic filing")
        }
    }

    private var statusLine: String {
        let active = env.settings.folders.filter(\.isAutoEnabled).count
        guard env.settings.isAutoEnabled else { return "Automatic filing off" }
        switch active {
        case 0:  return "No folders watched"
        case 1:  return "Watching 1 folder"
        default: return "Watching \(active) folders"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Not set up yet")
                .font(.system(size: 12, weight: .medium))
            Text("Pick a folder and Tidewell will file what lands in it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set Up Tidewell…") { WizardPresenter.shared.show() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
    }

    /// What moved today, so the popover answers "what did it just do" without opening
    /// a window. Collapsed to nothing on a quiet day rather than showing an empty box.
    @ViewBuilder
    private var todaySection: some View {
        let today = env.settings.runs.filter {
            Calendar.current.isDateInToday($0.startedAt) && !$0.moved.isEmpty
        }
        let count = today.reduce(0) { $0 + $1.moved.count }

        if count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("\(count) file\(count == 1 ? "" : "s") filed today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Undo All") {
                    Task { for run in today where !run.isUndone { await env.undo(run) } }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Put back everything Tidewell filed today.")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// A `ScrollView` inside a `MenuBarExtra` popover collapses to about 33 pt — it
    /// has no intrinsic height to offer. Measuring the content and pinning the frame
    /// is the way around it.
    private var folderList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(env.settings.folders) { folder in
                    FolderRow(folder: folder)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(max(contentHeight, 1), maxListHeight))
        .scrollIndicators(.visible)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button {
                Task { await env.organizeAll() }
            } label: {
                Label("Organize Now", systemImage: "arrow.down.to.line")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(env.settings.folders.isEmpty || !env.busyFolders.isEmpty)

            if let undoable = env.settings.mostRecentUndoable {
                Button {
                    Task { await env.undo(undoable) }
                } label: {
                    Label("Undo \(undoable.moved.count) moves", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }

            if env.settings.folders.isEmpty == false && !env.settings.hasCompletedSetup {
                Button { WizardPresenter.shared.show() } label: {
                    Label("Finish Setup…", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }

            Button {
                WindowPresenter.showMain(openWindow)
            } label: {
                Label("Folders & Rules…", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Button {
                // `openSettings` is the supported action (macOS 14+). The previous
                // `showSettingsWindow:` selector is private and silently does
                // nothing when it is not there, which is exactly how it failed.
                openSettings()
                WindowPresenter.focusSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Divider().padding(.vertical, 2)

            Button {
                AppActivationController.shared.quitFromMenuBar()
            } label: {
                Label("Quit Tidewell", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
        .labelStyle(.titleAndIcon)
    }
}

/// One folder in the popover: name, live state, and a per-folder file-now button.
private struct FolderRow: View {

    @Environment(AppEnvironment.self) private var env
    let folder: WatchedFolder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(folder.isAutoEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 0) {
                Text(folder.displayName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Text(folder.scheme.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if env.busyFolders.contains(folder.id) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
                Button {
                    Task { await env.organize(folder, trigger: .manual) }
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("File this folder now")
                .accessibilityLabel("File \(folder.displayName) now")
            }

            Toggle("", isOn: Binding(
                get: { folder.isAutoEnabled },
                set: { newValue in
                    var copy = folder
                    copy.isAutoEnabled = newValue
                    env.update(copy)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .accessibilityLabel("Watch \(folder.displayName) automatically")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .glassPanel(cornerRadius: 6)
    }
}
