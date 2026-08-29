import AppKit
import SwiftUI
import TidewellCore

@main
struct TidewellApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The same instance the delegate starts. Nothing in `AppEnvironment.init` may
    /// touch `NSApp` — it does not exist yet at this point.
    @State private var environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(environment)
        } label: {
            // The mark only. No counts, no readouts — detail belongs in the popover,
            // and a status item full of numbers is clutter next to the system's own.
            Image(nsImage: .tidewellStatusItem)
                .accessibilityLabel("Tidewell")
        }
        .menuBarExtraStyle(.window)

        // A `Window` scene opens itself at launch, which is wrong for a menu bar app.
        // `.defaultLaunchBehavior(.suppressed)` fixes that but is macOS 15+, and
        // `SceneBuilder` will not take an availability branch. Rather than raise the
        // minimum to 15 for one modifier — losing the whole Sonoma audience — the
        // delegate closes the launch window on every version. One code path, no
        // version-dependent behaviour to reason about.
        mainWindow

        Settings {
            SettingsScene()
                .environment(environment)
        }
        .windowResizability(.contentMinSize)
    }

    private var mainWindow: some Scene {
        Window("Tidewell", id: MainWindow.identifier) {
            MainWindow()
                .environment(environment)
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            // ⌘Q on a window Tidewell is *meant* to leave open all day is far too
            // easy to hit. Rebinding it to close the front window keeps the reflex
            // working and leaves the app in the menu bar; the popover's Quit item is
            // the sanctioned way out, and AppActivationController refuses the rest.
            CommandGroup(replacing: .appTermination) {
                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only. Set here rather than in `init` for the same reason the
        // watcher starts here: `NSApp` exists by now.
        NSApp.setActivationPolicy(.accessory)
        // Started here, not from `init`: the controller reads `NSApp`, which does not
        // exist yet during `App.init`.
        AppActivationController.shared.start()
        AppEnvironment.shared.start()
        closeLaunchWindowIfNeeded()
        showSetupIfNeeded()
    }

    /// Open the wizard the first time, once the app is up.
    ///
    /// Deferred a turn: opening a window from inside `applicationDidFinishLaunching`
    /// races the scene graph being ready, and the window arrives without focus.
    private func showSetupIfNeeded() {
        guard !AppEnvironment.shared.settings.hasCompletedSetup else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            WizardPresenter.shared.show()
        }
    }

    /// Close the window SwiftUI opens at launch, so Tidewell starts in the menu bar and
    /// nowhere else. See the note on the `mainWindow` scene for why this is done here
    /// rather than with `.defaultLaunchBehavior`.
    private func closeLaunchWindowIfNeeded() {
        for window in NSApp.windows
        where window.styleMask.contains(.titled) && !(window is NSPanel) {
            window.close()
        }
    }

    /// Closing the last window must not end a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Only the popover's Quit item and a system power-off may end the process.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppActivationController.shared.shouldTerminate()
    }

    /// Persist synchronously and let AppKit terminate.
    ///
    /// The tempting shape — return `.terminateLater` from
    /// `applicationShouldTerminate` and reply from a `@MainActor` task — deadlocks:
    /// after `.terminateLater` AppKit spins the run loop in a restricted mode and the
    /// task is never scheduled, so the reply never arrives and Quit appears to do
    /// nothing.
    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.flushForTermination()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

extension NSImage {
    /// The status item image, rasterised once.
    ///
    /// `MenuBarExtra` will not render a SwiftUI shape that depends on a
    /// `GeometryReader` as its label — the item stays clickable but invisible — so
    /// the mark is baked into a template image instead.
    @MainActor static let tidewellStatusItem: NSImage = {
        let side: CGFloat = 18
        let renderer = ImageRenderer(content: TidewellStatusMark(side: side).foregroundStyle(.black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: side, height: side))
        image.isTemplate = true          // follows the menu bar's light/dark appearance
        return image
    }()
}
