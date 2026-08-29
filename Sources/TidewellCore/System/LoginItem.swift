import Foundation
import ServiceManagement

/// Start-at-login, via `SMAppService`.
///
/// The older `LSSharedFileList` API is deprecated and needs a helper bundle;
/// `SMAppService.mainApp` registers the app itself and the user can revoke it from
/// System Settings › General › Login Items, which is where they will look anyway.
public enum LoginItem {

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` when macOS has the registration but the user switched it off in System
    /// Settings. Worth surfacing, because re-registering will not override them.
    public static var isDeniedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return .success(()) }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return .success(()) }
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:          "Enabled"
        case .requiresApproval: "Needs approval in System Settings › General › Login Items"
        case .notFound:         "Not registered"
        case .notRegistered:    "Off"
        @unknown default:       "Unknown"
        }
    }
}
