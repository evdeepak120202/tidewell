import SwiftUI

// The mark, and the tile it sits on.
//
// Deliberately SwiftUI and nothing else: Icon/make-icon.sh compiles this file on its
// own to render the .icns, so it must not reach into the rest of TidewellCore.

/// Tidewell's mark: a tide line, and three bars settling into order beneath it.
///
/// The idea is the app's whole job in one shape — loose things arriving from above,
/// coming to rest as even layers. It survives to 16 pt because it is four solid
/// shapes with no interior detail; at that size the bars merge into a readable stack
/// rather than turning to mud.
public struct TidewellMark: View {

    /// Side of the square the mark is drawn to fill.
    public var side: CGFloat
    /// Drop the crest and the falling chip below this size, where they only smear.
    public var isDetailed: Bool

    public init(side: CGFloat, isDetailed: Bool = true) {
        self.side = side
        self.isDetailed = isDetailed
    }

    public var body: some View {
        let unit = side / 100

        ZStack {
            // The tide crest — a shallow arc across the upper third.
            if isDetailed {
                TideCrest()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.95), .white.opacity(0.45)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 6 * unit, lineCap: .round)
                    )
                    .frame(width: 68 * unit, height: 20 * unit)
                    .offset(y: -30 * unit)

                // One chip still falling, just off the stack's centre line.
                RoundedRectangle(cornerRadius: 2 * unit, style: .continuous)
                    .fill(.white.opacity(0.9))
                    .frame(width: 13 * unit, height: 5 * unit)
                    .rotationEffect(.degrees(-14))
                    .offset(x: 17 * unit, y: -12 * unit)
            }

            // Three settled layers, widest at the bottom.
            //
            // Without the crest there is nothing above the stack, so the small-size
            // variant re-centres and opens up: at 16 pt the gaps are what carry the
            // shape, and 6.5 units of them close to nothing on a 16 px grid.
            VStack(spacing: (isDetailed ? 6.5 : 10) * unit) {
                bar(width: (isDetailed ? 40 : 46) * unit, unit: unit, opacity: 0.92)
                bar(width: (isDetailed ? 54 : 64) * unit, unit: unit, opacity: 0.96)
                bar(width: (isDetailed ? 66 : 82) * unit, unit: unit, opacity: 1.00)
            }
            .offset(y: isDetailed ? 18 * unit : 0)
        }
        .frame(width: side, height: side)
    }

    private func bar(width: CGFloat, unit: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 3.5 * unit, style: .continuous)
            .fill(.white.opacity(opacity))
            .frame(width: width, height: (isDetailed ? 11 : 13) * unit)
    }
}

/// A shallow, asymmetric arc — a wave crest rather than a circle segment.
struct TideCrest: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.52),
            control1: CGPoint(x: rect.width * 0.30, y: -rect.maxY * 0.30),
            control2: CGPoint(x: rect.width * 0.62, y: rect.maxY * 1.25)
        )
        return path
    }
}

/// The full app icon: mark on the squircle tile macOS expects.
public struct TidewellIconTile: View {

    public var canvas: CGFloat

    public init(canvas: CGFloat) {
        self.canvas = canvas
    }

    public var body: some View {
        // Apple's grid insets the art inside the 1024 canvas; matching it keeps the
        // tile the same visual weight as system icons in the Dock.
        let inset = canvas * 0.085
        let side = canvas - inset * 2
        let detailed = canvas >= 64

        ZStack {
            RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.72, blue: 0.76),
                            Color(red: 0.09, green: 0.42, blue: 0.62),
                            Color(red: 0.06, green: 0.24, blue: 0.44),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // A light wash from above, so the tile reads as lit rather than flat.
                    RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .clear],
                                startPoint: .top, endPoint: .center
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: max(1, side * 0.006))
                )
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(detailed ? 0.28 : 0), radius: side * 0.05, y: side * 0.02)

            TidewellMark(side: side * 0.72, isDetailed: detailed)
        }
        .frame(width: canvas, height: canvas)
    }
}

/// Monochrome template for the menu bar.
///
/// The status item shows the mark only — no counts, no readouts. macOS does not show
/// "files filed today" anywhere, but a status item full of numbers still reads as
/// clutter, and detail belongs in the popover.
public struct TidewellStatusMark: View {

    public var side: CGFloat

    public init(side: CGFloat = 18) {
        self.side = side
    }

    public var body: some View {
        let unit = side / 100
        VStack(spacing: 11 * unit) {
            Capsule().frame(width: 42 * unit, height: 12 * unit)
            Capsule().frame(width: 66 * unit, height: 12 * unit)
            Capsule().frame(width: 88 * unit, height: 12 * unit)
        }
        .frame(width: side, height: side)
    }
}
