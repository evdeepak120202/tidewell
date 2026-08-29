import Foundation
import UniformTypeIdentifiers

/// The buckets a file can be sorted into.
///
/// Categories are resolved from the system's Uniform Type Identifier tree first and
/// only fall back to a literal extension list, so a `.heic` lands in `Images` without
/// anyone having had to list `heic` anywhere.
public enum FileCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case images     = "Images"
    case documents  = "Documents"
    case archives   = "Archives"
    case video      = "Video"
    case audio      = "Audio"
    case code       = "Code"
    case installers = "Installers"
    case design     = "Design"
    case data       = "Data"
    case other      = "Other"

    public var id: String { rawValue }

    /// Folder name used on disk. Editable per rule set; this is the default.
    public var defaultFolderName: String { rawValue }

    public var symbolName: String {
        switch self {
        case .images:     "photo"
        case .documents:  "doc.text"
        case .archives:   "archivebox"
        case .video:      "film"
        case .audio:      "waveform"
        case .code:       "chevron.left.forwardslash.chevron.right"
        case .installers: "shippingbox"
        case .design:     "paintbrush.pointed"
        case .data:       "tablecells"
        case .other:      "questionmark.folder"
        }
    }

    /// UTI roots that map onto this category, most specific first.
    var contentTypes: [UTType] {
        switch self {
        case .images:     [.image]
        case .video:      [.movie, .video]
        case .audio:      [.audio]
        case .archives:   [.archive, .gzip, .bz2, .zip]
        case .code:       [.sourceCode, .script, .shellScript]
        case .documents:  [.pdf, .rtf, .plainText, .spreadsheet, .presentation, .compositeContent]
        case .data:       [.json, .xml, .commaSeparatedText, .database]
        case .design:     []
        case .installers: []
        case .other:      []
        }
    }

    /// Extensions checked before the UTI tree, for the cases where the tree is
    /// either too broad or silent.
    ///
    /// `documents` is deliberately absent here: `.plainText` already covers `.txt`
    /// and `.md`, and listing them again would shadow `code`'s claim on `.swift`,
    /// which also conforms to `.plainText`.
    var explicitExtensions: Set<String> {
        switch self {
        case .installers: ["dmg", "pkg", "mpkg", "exe", "msi", "deb", "rpm", "appimage"]
        case .design:     ["sketch", "fig", "xd", "psd", "ai", "afdesign", "afphoto", "blend"]
        case .archives:   ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst"]
        case .data:       ["csv", "tsv", "json", "ndjson", "jsonl", "xml", "yaml", "yml",
                           "sqlite", "db", "parquet", "bson"]
        case .code:       ["swift", "py", "js", "ts", "tsx", "jsx", "rb", "go", "rs", "java",
                           "kt", "c", "h", "cpp", "hpp", "m", "mm", "sh", "zsh", "bash",
                           "php", "dart", "lua", "sql", "toml", "gradle", "podspec"]
        default:          []
        }
    }
}
