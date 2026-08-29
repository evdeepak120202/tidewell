import Foundation
import PDFKit
import Vision

/// Pulls a short text sample out of a file so it can be classified.
///
/// Deliberately small: the sample is capped, stripped of control characters, and taken
/// from the first page only. The model needs enough to tell an invoice from a lease, not
/// the document.
///
/// PDFKit and Vision are the only frameworks in `TidewellCore` that reach beyond
/// Foundation. Both are data extraction, not UI, and neither prevents the engine from
/// being tested headlessly — which is what the no-UI rule exists to protect.
public struct ContentExtractor: Sendable {

    /// Hard cap on what is handed to the model.
    ///
    /// Two kilobytes is plenty to identify a document, and keeping it small bounds both
    /// inference time and how much of a hostile document can reach the prompt.
    public static let sampleLimit = 2_048

    public init() {}

    /// Whether this file is even a candidate.
    ///
    /// Classification is expensive, so it only runs where the filename tells us nothing.
    /// A file called `Electricity Bill March.pdf` does not need a model.
    public func isWorthClassifying(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["pdf", "txt", "md", "rtf", "png", "jpg", "jpeg", "heic", "tiff"].contains(ext)
        else { return false }

        let stem = url.deletingPathExtension().lastPathComponent

        // Names that carry no meaning: scanner and camera output, hashes, bare numbers.
        let uninformative = [
            "^scan[\\s_-]*\\d*$", "^img[\\s_-]*\\d+$", "^image[\\s_-]*\\d*$",
            "^document[\\s_-]*\\d*$", "^untitled[\\s_-]*\\d*$", "^file[\\s_-]*\\d*$",
            "^[0-9]+$", "^[0-9a-f]{16,}$", "^dsc[\\s_-]*\\d+$", "^photo[\\s_-]*\\d*$",
        ]
        let lower = stem.lowercased()
        if uninformative.contains(where: { lower.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }
        // Very short names carry little either.
        return stem.count <= 3
    }

    /// Extract a sample, or nil if there is nothing readable.
    public func sample(from url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        let raw: String?

        switch ext {
        case "pdf":                          raw = pdfText(url)
        case "txt", "md", "rtf":             raw = plainText(url)
        case "png", "jpg", "jpeg", "heic", "tiff": raw = await ocrText(url)
        default:                             raw = nil
        }

        guard let raw else { return nil }
        let cleaned = Self.clean(raw)
        return cleaned.count >= 24 ? cleaned : nil
    }

    /// Strip control characters and collapse whitespace, then truncate.
    ///
    /// Control characters are removed because they are a cheap way to smuggle structure
    /// into what is supposed to be a flat block of untrusted text.
    static func clean(_ text: String) -> String {
        let stripped = text.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(sampleLimit))
    }

    private func pdfText(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url), document.pageCount > 0,
              let page = document.page(at: 0)
        else { return nil }
        return page.string
    }

    private func plainText(_ url: URL) -> String? {
        // Read only the head of the file: a 200 MB log should not be loaded whole.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.sampleLimit * 4) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private func ocrText(_ url: URL) async -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: nil) }
        }
    }
}
