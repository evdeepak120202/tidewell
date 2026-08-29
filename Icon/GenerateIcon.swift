import AppKit
import SwiftUI

// Renders the Tidewell icon set from the same SwiftUI mark the app uses, so the Dock
// icon and the in-app mark cannot drift apart.
//
// Usage:  ./Icon/make-icon.sh

@MainActor
func render(_ view: some View, pixels: Int) -> NSBitmapImageRep? {
    let renderer = ImageRenderer(
        content: view.frame(width: CGFloat(pixels), height: CGFloat(pixels))
    )
    renderer.scale = 1
    renderer.isOpaque = false
    guard let cgImage = renderer.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: cgImage)
}

@MainActor
func write(_ view: some View, pixels: Int, to url: URL) throws {
    guard let rep = render(view, pixels: pixels),
          let data = rep.representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
    print("  \(url.lastPathComponent)  \(pixels)×\(pixels)")
}

@main
@MainActor
struct IconGenerator {
    static func main() throws {
        let arguments = CommandLine.arguments
        let outputRoot = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "build/icon")
        let fileManager = FileManager.default

        let iconset = outputRoot.appendingPathComponent("Tidewell.iconset")
        try? fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

        let representations: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]

        print("App icon:")
        for (name, pixels) in representations {
            // Rendered natively at each size rather than downsampled, so the crest
            // drops out cleanly below 64 px instead of smearing.
            try write(
                TidewellIconTile(canvas: CGFloat(pixels)),
                pixels: pixels,
                to: iconset.appendingPathComponent("\(name).png")
            )
        }

        try write(
            TidewellIconTile(canvas: 1024),
            pixels: 1024,
            to: outputRoot.appendingPathComponent("Tidewell-1024.png")
        )

        print("DMG background:")
        for (suffix, scale) in [("", 1), ("@2x", 2)] {
            let renderer = ImageRenderer(
                content: DMGBackground().frame(width: DMGBackground.width, height: DMGBackground.height)
            )
            renderer.scale = CGFloat(scale)
            renderer.isOpaque = true
            guard let cgImage = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown) }
            let url = outputRoot.appendingPathComponent("dmg-background\(suffix).png")
            try data.write(to: url)
            print("  \(url.lastPathComponent)  \(cgImage.width)x\(cgImage.height)")
        }

        print("\nWrote to \(outputRoot.path)")
    }
}

// MARK: - DMG backdrop

/// Artwork behind the drag-to-install window. The baseline here is the source of
/// truth for the icon-well positions Scripts/make-dmg.sh sets.
struct DMGBackground: View {
    static let width: CGFloat = 600
    static let height: CGFloat = 400
    static let baseline: CGFloat = 186

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.13, blue: 0.20),
                         Color(red: 0.03, green: 0.07, blue: 0.12)],
                startPoint: .top, endPoint: .bottom
            )
            Ellipse()
                .fill(Color(red: 0.20, green: 0.72, blue: 0.76).opacity(0.18))
                .frame(width: 420, height: 260)
                .blur(radius: 90)
                .offset(x: -110, y: -20)

            VStack(spacing: 0) {
                Text("Tidewell")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 44)
                Text("Drag it into Applications")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6)
                Spacer()
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
                .position(x: Self.width / 2, y: Self.baseline)

            Text("Personal build · not notarised")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.30))
                .position(x: Self.width / 2, y: Self.height - 26)
        }
        .frame(width: Self.width, height: Self.height)
    }
}
