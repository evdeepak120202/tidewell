import AppKit

/// Owns two decisions that a menu bar app has to make together: whether it currently
/// looks like an ordinary app, and what is allowed to quit it.
///
/// ## The Dock tile and ⌘-Tab
///
/// macOS ties them to a single switch. `.accessory` removes the Dock tile *and* the
/// ⌘-Tab entry; `.regular` restores both. There is no public way to have one without
/// the other. So the policy follows the windows rather than being fixed: with a
/// window open the app is `.regular` and behaves like anything else in ⌘-Tab, and
/// when the last window closes it drops back to `.accessory` and disappears from
/// both. The Dock icon exists exactly while there is something to switch to.
///
/// ## Quitting
///
/// ⌘Q on a window is far too easy to hit by accident for an app meant to sit in
/// the menu bar all day. ⌘Q is rebound to close the front window instead (see the
/// `CommandGroup(replacing: .appTermination)` in the scene), and this guard catches
/// the other routes — the Dock tile's right-click Quit, and anything scripted.
///
/// Two things are deliberately still allowed to terminate the process, because
/// refusing them would be a bug rather than a feature:
///
///   * the Quit item in the app's own menu bar popover, which sets `isDeliberateQuit`;
///   * a system power-off, restart or logout, which is announced by
///     `NSWorkspace.willPowerOffNotification` — blocking that would hang the user's
///     logout on this app.
///
/// Force Quit is unaffected either way; it does not ask.
@MainActor
final class AppActivationController {

    static let shared = AppActivationController()

    /// Lets an app gate the Dock behaviour behind a user setting. Defaults to on.
    var wantsDockWhenWindowOpen: () -> Bool = { true }

    private var observers: [any NSObjectProtocol] = []
    private var isDeliberateQuit = false
    private var isSystemPowerOff = false

    private init() {}

    func start() {
        let center = NotificationCenter.default
        // Both edges are needed: `didBecomeKey` catches a window opening, `willClose`
        // the last one going away. `willClose` fires *before* the window leaves
        // `NSApp.windows`, so the re-evaluation is deferred a turn.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in AppActivationController.shared.reevaluate() }
                }
            )
        }

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willPowerOffNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in AppActivationController.shared.isSystemPowerOff = true }
            }
        )

        reevaluate()
    }

    /// `isolated deinit` so the observer tokens — opaque `NSObjectProtocol` values
    /// that are not `Sendable` — are torn down on the actor that made them.
    isolated deinit {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
    }

    // MARK: Dock presence

    /// Windows that count as "the app is open".
    ///
    /// Panels are excluded: a menu bar popover is an `NSPanel`, and it should not put
    /// the app in the Dock every time it is opened.
    private var hasVisibleWindow: Bool {
        // `NSApp` is an implicitly-unwrapped optional and is genuinely nil until the
        // application object exists. Touching it from an `App`'s `init` — before
        // `applicationDidFinishLaunching` — traps. Checked rather than assumed, so a
        // future caller cannot reintroduce that crash.
        guard let app = NSApp else { return false }
        return app.windows.contains { window in
            window.isVisible
                && !(window is NSPanel)
                && window.styleMask.contains(.titled)
                && window.className != "NSStatusBarWindow"
        }
    }

    func reevaluate() {
        let wantsRegular = wantsDockWhenWindowOpen() && hasVisibleWindow
        let desired: NSApplication.ActivationPolicy = wantsRegular ? .regular : .accessory
        guard NSApp.activationPolicy() != desired else { return }

        _ = NSApp.setActivationPolicy(desired)

        // Becoming `.regular` while already frontmost leaves the app without key
        // focus until the user clicks, which reads as the window having opened behind
        // something. Re-activating settles it.
        if desired == .regular { NSApp.activate() }
    }

    // MARK: Quitting

    /// The one sanctioned way out, wired to the Quit item in the menu bar popover.
    func quitFromMenuBar() {
        isDeliberateQuit = true
        NSApp.terminate(nil)
    }

    func shouldTerminate() -> NSApplication.TerminateReply {
        isDeliberateQuit || isSystemPowerOff ? .terminateNow : .terminateCancel
    }
}
