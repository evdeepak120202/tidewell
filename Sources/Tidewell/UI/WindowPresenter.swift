import AppKit
import SwiftUI

/// Brings a window forward from a menu bar app.
///
/// `LSUIElement` keeps Tidewell out of the Dock, and that also means opening a
/// window does not bring the process forward: the window appears *behind* whatever
/// the user was looking at, and they have to go hunting for it. Every open goes
/// through here so that cannot happen.
@MainActor
enum WindowPresenter {

    /// Open (or raise) the main window and focus it.
    static func showMain(_ openWindow: OpenWindowAction) {
        openWindow(id: MainWindow.identifier)
        focus(matching: MainWindow.identifier)
    }

    /// Bring the Settings window forward after `openSettings()` has asked for it.
    ///
    /// Opening is SwiftUI's job; being *seen* is not. Under `LSUIElement` the process
    /// does not come forward on its own, so without this the pane opens behind
    /// whatever the user was looking at.
    static func focusSettings() {
        focus(matching: "Settings")
    }

    /// Wait for SwiftUI to instantiate the window, then activate it.
    ///
    /// The delay is not cosmetic: the window does not exist on the same turn of the
    /// run loop that asked for it, so activating immediately finds nothing.
    private static func focus(matching identifier: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard let app = NSApp else { return }
            app.activate(ignoringOtherApps: true)

            let match = app.windows.first {
                $0.identifier?.rawValue.localizedCaseInsensitiveContains(identifier) == true
            } ?? app.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }

            match?.makeKeyAndOrderFront(nil)
        }
    }
}
