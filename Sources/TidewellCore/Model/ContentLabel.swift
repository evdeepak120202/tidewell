import Foundation

/// What a document is, as opposed to what kind of file it is.
///
/// A closed set, deliberately. The model is only ever asked to choose from these — it can
/// never invent a label, and therefore can never invent a folder name or a path. That one
/// constraint removes the entire class of "model output reaches the filesystem" problems,
/// and means the worst a bad answer can do is misfile something visibly and reversibly.
public enum ContentLabel: String, Codable, CaseIterable, Sendable, Identifiable {
    case invoice
    case receipt
    case contract
    case statement
    case report
    case letter
    case form
    case ticket
    case manual
    case article
    case resume
    case certificate
    case unknown

    public var id: String { rawValue }

    /// Folder this label files into, by default. Editable like any other folder name.
    public var defaultFolderName: String {
        switch self {
        case .invoice:     "Invoices"
        case .receipt:     "Receipts"
        case .contract:    "Contracts"
        case .statement:   "Statements"
        case .report:      "Reports"
        case .letter:      "Letters"
        case .form:        "Forms"
        case .ticket:      "Tickets"
        case .manual:      "Manuals"
        case .article:     "Articles"
        case .resume:      "Resumes"
        case .certificate: "Certificates"
        case .unknown:     "Documents"
        }
    }

    public var symbolName: String {
        switch self {
        case .invoice, .receipt, .statement: "banknote"
        case .contract, .form:               "signature"
        case .report, .article:              "doc.richtext"
        case .letter:                        "envelope"
        case .ticket:                        "ticket"
        case .manual:                        "book"
        case .resume:                        "person.text.rectangle"
        case .certificate:                   "rosette"
        case .unknown:                       "doc"
        }
    }

    /// Labels the model may return. `unknown` is excluded from the prompt: it is the
    /// app's own fallback, not something the model should be encouraged to pick.
    public static var selectable: [ContentLabel] {
        allCases.filter { $0 != .unknown }
    }
}

/// One classification result, cached by the file's content hash.
public struct ContentClassification: Codable, Sendable, Hashable {
    public let label: ContentLabel
    public let confidence: Double
    public let sampledCharacters: Int
    public let decidedAt: Date

    public init(label: ContentLabel, confidence: Double, sampledCharacters: Int, decidedAt: Date = Date()) {
        self.label = label
        self.confidence = confidence
        self.sampledCharacters = sampledCharacters
        self.decidedAt = decidedAt
    }
}
