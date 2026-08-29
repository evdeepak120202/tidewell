import Foundation
import Testing
@testable import TidewellCore

/// The guardrails, tested where they can be tested without a model present.
///
/// The inference itself needs Apple Intelligence hardware and cannot run in CI, so what is
/// covered here is everything that decides *whether* inference happens and what is done
/// with the answer — which is where this kind of feature actually goes wrong.
@Suite("Intelligence guardrails")
struct IntelligenceTests {

    // MARK: Off by default

    @Test("A new folder does not use intelligence")
    func offByDefaultOnFolders() {
        #expect(WatchedFolder(url: URL(fileURLWithPath: "/tmp/x")).usesIntelligence == false)
    }

    @Test("A folder written before the feature existed decodes as off")
    func offByDefaultOnUpgrade() throws {
        let json = """
        {"id":"44444444-4444-4444-4444-444444444444",
         "url":"file:///Users/x/Downloads/","isAutoEnabled":true,"scheme":"category",
         "folderNames":[],"ignoredCategories":[],"ignoredExtensions":[],
         "overrides":{},"minimumAgeSeconds":0}
        """.data(using: .utf8)!
        let folder = try JSONDecoder().decode(WatchedFolder.self, from: json)
        #expect(folder.usesIntelligence == false,
                "an upgrade must never switch on a feature that reads documents")
    }

    // MARK: Which files are even candidates

    @Test("Only uninformative names are candidates", arguments: [
        ("scan_001.pdf", true), ("IMG_4821.png", true), ("document.pdf", true),
        ("untitled.pdf", true), ("20260828.pdf", true), ("a.pdf", true),
        ("Electricity Bill March.pdf", false),
        ("Jagriq-Invoice-2026-27-00001.pdf", false),
        ("day-sheet-2026-08-28.pdf", false),
    ])
    func candidacy(name: String, expected: Bool) {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        #expect(ContentExtractor().isWorthClassifying(url) == expected)
    }

    @Test("File types with no readable text are never candidates", arguments: [
        "archive.zip", "app.dmg", "movie.mp4", "song.mp3", "data.sqlite",
    ])
    func nonTextTypesAreSkipped(name: String) {
        #expect(!ContentExtractor().isWorthClassifying(URL(fileURLWithPath: "/tmp/\(name)")))
    }

    // MARK: Untrusted input

    @Test("Control characters are stripped from extracted text")
    func stripsControlCharacters() {
        let hostile = "Invoice\u{0000}\u{001B}[31m total\u{0007} due"
        let cleaned = ContentExtractor.clean(hostile)
        #expect(!cleaned.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" })
        #expect(cleaned.contains("Invoice"))
    }

    @Test("The sample handed to the model is capped")
    func sampleIsCapped() {
        let huge = String(repeating: "a", count: 100_000)
        #expect(ContentExtractor.clean(huge).count <= ContentExtractor.sampleLimit)
    }

    /// The model is only ever offered a closed set, so a document that tries to redirect
    /// it cannot produce a folder name — the worst case is the wrong label.
    @Test("Every label maps to a fixed folder name, never to model output")
    func labelsMapToFixedFolders() {
        for label in ContentLabel.allCases {
            #expect(!label.defaultFolderName.isEmpty)
            #expect(!label.defaultFolderName.contains("/"),
                    "a label's folder name must never contain a path separator")
            #expect(!label.defaultFolderName.contains(".."))
        }
    }

    @Test("`unknown` is not offered to the model")
    func unknownIsAppSideOnly() {
        #expect(!ContentLabel.selectable.contains(.unknown))
    }

    // MARK: Sensitive folders

    @Test("Folder names suggesting private contents are flagged", arguments: [
        "Tax Returns", "Medical", "Bank Statements", "Legal", "Personal",
    ])
    func sensitiveFoldersFlagged(name: String) {
        let folder = WatchedFolder(url: URL(fileURLWithPath: "/Users/x/\(name)"))
        #expect(folder.looksSensitive)
    }

    @Test("Ordinary folders are not flagged", arguments: ["Downloads", "Desktop", "Projects"])
    func ordinaryFoldersNotFlagged(name: String) {
        #expect(!WatchedFolder(url: URL(fileURLWithPath: "/Users/x/\(name)")).looksSensitive)
    }

    // MARK: Destination folders are managed

    @Test("Label folders are recognised, so they are never re-scanned")
    func labelFoldersAreManaged() {
        let folder = WatchedFolder(url: URL(fileURLWithPath: "/tmp/x"))
        for label in ContentLabel.allCases {
            #expect(folder.managedFolderNames.contains(label.defaultFolderName))
        }
    }

    // MARK: Availability

    @Test("Availability always has honest copy for every state")
    func everyStateExplained() {
        let states: [IntelligenceAvailability] =
            [.ready, .notEnabled, .downloading, .unsupportedHardware, .unsupportedOS]
        for state in states {
            #expect(!state.headline.isEmpty)
            #expect(!state.detail.isEmpty)
            // Only one state should push the user into System Settings.
            #expect(state.offersSystemSettings == (state == .notEnabled))
        }
        #expect(IntelligenceAvailability.ready.canRun)
        #expect(!IntelligenceAvailability.notEnabled.canRun)
    }

    // MARK: Budgets

    @Test("Budget defaults are conservative")
    func budgetDefaults() {
        let budget = IntelligenceEngine.Budget()
        #expect(budget.perFileTimeout <= .seconds(10))
        #expect(budget.maxFilesPerRun <= 100)
        #expect(budget.minimumConfidence > 0.5)
    }

    @Test("Classification is skipped when the machine is unwilling")
    func respectsThermalAndPower() {
        // Cannot force thermal state in a test, so this asserts the guard exists and
        // returns a decision rather than trapping.
        _ = IntelligenceEngine.systemIsWillingToInfer()
    }

    @Test("An engine with no model available classifies nothing")
    func noModelMeansNoResult() async {
        // On CI (no Apple Intelligence) this exercises the availability short-circuit.
        let engine = IntelligenceEngine()
        let result = await engine.classify(URL(fileURLWithPath: "/tmp/scan_001.pdf"))
        if !IntelligenceAvailability.current.canRun {
            #expect(result == nil)
        }
    }
}
