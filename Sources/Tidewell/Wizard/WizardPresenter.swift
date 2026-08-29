import AppKit
import SwiftUI
import TidewellCore

/// Owns the first-run window.
///
/// A real `NSWindow` hosting the SwiftUI view rather than a `Window` scene, because the
/// wizard has to open from `applicationDidFinishLaunching` — before any view exists to
/// carry an `openWindow` action, and before the scene graph is reliably ready. Building
/// the window directly removes that race entirely and gives exact control over sizing,
/// centring and focus, which a menu bar app does not get for free.
@MainActor
final class WizardPresenter: NSObject, NSWindowDelegate {

    static let shared = WizardPresenter()

    private var window: NSWindow?
    private override init() { super.init() }

    var isShowing: Bool { window != nil }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SetupWizard()
            .environment(AppEnvironment.shared)
            // The wizard dismisses itself; `dismiss` in a hosted view needs somewhere to
            // go, so it is routed back here.
            .environment(\.dismissAction, DismissAction { [weak self] in self?.close() })

        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "Welcome to Tidewell"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        self.window = window

        // A menu bar app is `.accessory`, so showing a window does not bring the process
        // forward on its own — the wizard would open behind whatever is in front.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    /// Closing the wizard without finishing must not leave the app in a state where it
    /// never offers setup again — but nor should it reopen on every launch forever. The
    /// compromise: the folder list is empty, so the menu bar popover shows its own
    /// "Set up Tidewell" action, and the wizard is reachable from there and from Settings.
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - Dismiss plumbing

private struct DismissActionKey: EnvironmentKey {
    static let defaultValue = DismissAction {}
}

extension EnvironmentValues {
    var dismissAction: DismissAction {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }
}

/// A dismissal the host provides, since a hosted view has no window scene to close.
struct DismissAction {
    private let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor func callAsFunction() { action() }
}
