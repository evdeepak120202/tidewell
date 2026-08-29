import Foundation

/// Decides whether a file has stopped changing.
///
/// A download in progress is a real file with a real size; the only way to tell it
/// apart from a finished one is to look twice. Everything here exists so Tidewell
/// never moves a file out from under whatever is writing it.
public struct StabilityGate: Sendable {

    public enum Verdict: Sendable {
        case settled
        case changing
        case vanished
    }

    /// Gap between the two samples. Long enough that a slow writer is caught, short
    /// enough that filing does not feel laggy.
    public let settleInterval: Duration

    public init(settleInterval: Duration = .milliseconds(900)) {
        self.settleInterval = settleInterval
    }

    private struct Sample: Equatable {
        let size: Int64
        let modified: Date?
    }

    private func sample(_ url: URL) -> Sample? {
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return nil }
        return Sample(size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate)
    }

    /// Sample twice, `settleInterval` apart.
    public func verdict(for url: URL) async -> Verdict {
        guard let first = sample(url) else { return .vanished }
        try? await Task.sleep(for: settleInterval)
        guard let second = sample(url) else { return .vanished }
        return first == second ? .settled : .changing
    }
}
