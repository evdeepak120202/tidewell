import Foundation

/// How a destination path is built for a file that has already been categorised.
///
/// All three are offered per folder rather than app-wide: a Downloads folder and a
/// screenshots folder want different shapes, and forcing one on both is the reason
/// most organisers get switched off.
public enum SortScheme: String, Codable, CaseIterable, Sendable, Identifiable {
    /// `Images/`, `Documents/` — one folder per category.
    case category

    /// `PNG/`, `PDF/` — one folder per extension, uppercased.
    case fileExtension

    /// `Images/2026-08/` — category, then year-month.
    case categoryByMonth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .category:        "Category folders"
        case .fileExtension:   "Extension folders"
        case .categoryByMonth: "Category, then month"
        }
    }

    public var detail: String {
        switch self {
        case .category:        "Images, Documents, Archives…"
        case .fileExtension:   "PNG, PDF, ZIP…"
        case .categoryByMonth: "Images/2026-08, Documents/2026-08…"
        }
    }

    /// Relative path components beneath the watched folder.
    ///
    /// Returns `nil` when no sensible destination exists, which the caller must treat
    /// as "leave this file alone" rather than inventing a fallback.
    public func destinationComponents(
        category: FileCategory,
        folderName: String,
        fileExtension: String,
        date: Date,
        calendar: Calendar = .current
    ) -> [String]? {
        switch self {
        case .category:
            return [folderName]

        case .fileExtension:
            // A file with no extension has no extension folder to go to.
            let trimmed = fileExtension.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return [trimmed.uppercased()]

        case .categoryByMonth:
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { return [folderName] }
            return [folderName, String(format: "%04d-%02d", year, month)]
        }
    }
}
