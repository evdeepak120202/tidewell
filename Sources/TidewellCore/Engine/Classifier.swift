import Foundation
import UniformTypeIdentifiers

/// Maps a file onto a `FileCategory`.
///
/// Order matters: an explicit user rule wins, then a literal extension list, then the
/// system's type tree. The tree is consulted last because it is broad — `.swift`
/// conforms to `.plainText`, so asking the tree first would file source code as a
/// document.
public struct Classifier: Sendable {

    private let overrides: [String: FileCategory]

    /// - Parameter overrides: lowercased extension → category, from the user's rules.
    public init(overrides: [String: FileCategory] = [:]) {
        self.overrides = overrides
    }

    public func category(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()

        if let override = overrides[ext] { return override }
        if !ext.isEmpty {
            for category in FileCategory.allCases where category.explicitExtensions.contains(ext) {
                return category
            }
        }

        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext)
        else { return .other }

        // Most specific first so `.images` is tested before `.documents` can claim a
        // PDF-adjacent type.
        let order: [FileCategory] = [.images, .video, .audio, .archives, .code, .data, .documents]
        for category in order {
            if category.contentTypes.contains(where: { type.conforms(to: $0) }) { return category }
        }
        return .other
    }
}
