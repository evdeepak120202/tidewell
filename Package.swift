// swift-tools-version: 6.2

import PackageDescription

// Two targets, not one: TidewellCore is the organiser — classification, the
// filesystem watcher, the move engine, persistence — and knows nothing about
// windows. Tidewell is the shell around it.
//
// The split earns its keep because the engine is the part that touches the user's
// files: it can be reasoned about, and tested, without a running app.
let shared: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .unsafeFlags(["-warnings-as-errors"], .when(configuration: .debug)),
]

let package = Package(
    name: "Tidewell",
    // Declared so translation is a pull request rather than a refactor: with a default
    // localisation set, SwiftUI's string literals are extractable into a catalogue and a
    // translator never has to touch Swift.
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TidewellCore",
            path: "Sources/TidewellCore",
            swiftSettings: shared
        ),
        .executableTarget(
            name: "Tidewell",
            dependencies: ["TidewellCore"],
            path: "Sources/Tidewell",
            swiftSettings: shared + [
                // App Intents metadata is normally produced by an Xcode build phase.
                // SwiftPM has no such phase, so the compiler is asked directly for the
                // const values `appintentsmetadataprocessor` needs; Scripts/build.sh
                // then runs the processor.
                .unsafeFlags([
                    "-emit-const-values",
                    "-Xfrontend", "-const-gather-protocols-file",
                    "-Xfrontend", "Scripts/appintents-protocols.json",
                ]),
            ]
        ),
        .testTarget(
            name: "TidewellCoreTests",
            dependencies: ["TidewellCore"],
            path: "Tests/TidewellCoreTests",
            swiftSettings: shared
        ),
    ]
)
