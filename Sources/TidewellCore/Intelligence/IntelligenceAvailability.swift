import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether on-device classification can run, and what to tell the user if it cannot.
///
/// Tidewell never downloads a model. Apple Intelligence is managed by macOS and enabling
/// it is a System Settings action costing several gigabytes, so this type's whole job is
/// to *report and explain*, never to fetch.
public enum IntelligenceAvailability: Equatable, Sendable {
    /// The model is ready.
    case ready
    /// The Mac supports it, but the user has not turned Apple Intelligence on.
    case notEnabled
    /// macOS is still downloading the model.
    case downloading
    /// This Mac cannot run it. Said once, then never mentioned again.
    case unsupportedHardware
    /// The OS is older than macOS 26.
    case unsupportedOS

    public static var current: IntelligenceAvailability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .unsupportedOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .downloading
        case .unavailable(.deviceNotEligible):
            return .unsupportedHardware
        @unknown default:
            return .unsupportedHardware
        }
        #else
        return .unsupportedOS
        #endif
    }

    public var canRun: Bool { self == .ready }

    /// Honest copy for each state. No nagging, no "upgrade your Mac".
    public var headline: String {
        switch self {
        case .ready:               "On-device AI is ready"
        case .notEnabled:          "Apple Intelligence is turned off"
        case .downloading:         "macOS is still downloading the model"
        case .unsupportedHardware: "This Mac can't run on-device AI"
        case .unsupportedOS:       "Needs macOS 26 or later"
        }
    }

    public var detail: String {
        switch self {
        case .ready:
            "Tidewell can read a document to work out what it is. Nothing is uploaded — "
            + "the model runs on this Mac and Tidewell has no network code at all."
        case .notEnabled:
            "Turn it on in System Settings › Apple Intelligence & Siri. macOS downloads "
            + "the model itself, which takes several gigabytes. Tidewell never downloads "
            + "anything."
        case .downloading:
            "Nothing to do — this option becomes available once macOS has finished."
        case .unsupportedHardware:
            "Apple Intelligence needs Apple silicon. Everything else in Tidewell works "
            + "exactly the same without it."
        case .unsupportedOS:
            "Everything else in Tidewell works exactly the same without it."
        }
    }

    /// Whether to offer a button into System Settings.
    public var offersSystemSettings: Bool { self == .notEnabled }

    public static let appleIntelligenceSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?AppleIntelligence"
    )
}
