import SwiftUI

/// 7 Term's look: the 6 Bits family in tactical red. Same structure as 6 Bits
/// (tinted near-black, one bright accent, monospaced type, dot-matrix logo),
/// with every green swapped for red.
@MainActor
enum Brand {
    /// The accent. 6 Bits uses #34FF68; this is its red counterpart.
    static let red = Color(.sRGB, red: 1.00, green: 0.204, blue: 0.204)
    /// Headings and secondary accent text.
    static let redDim = red.opacity(0.62)
    /// Window background (6 Bits: #090D0A).
    static let background = Color(.sRGB, red: 0.051, green: 0.035, blue: 0.035)
    /// Sidebar background (6 Bits: #0F1511).
    static let panel = Color(.sRGB, red: 0.082, green: 0.059, blue: 0.059)
    /// Selected sidebar row (6 Bits: #14361D).
    static let selection = Color(.sRGB, red: 0.227, green: 0.078, blue: 0.078)

    /// Monospaced, like everything in 6 Bits.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A 5×7 dot-matrix digit drawn as square dots with a small gap and a soft
/// glow, matching the "6" in the 6 Bits logo.
struct PixelGlyph: View {
    let rows: [String]
    var dot: CGFloat = 3
    var color: Color = Brand.red

    /// The "7" from 7 Term's logo and app icon: SSH is a layer 7 protocol.
    static let seven = [
        "#####",
        "....#",
        "...#.",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
    ]

    var body: some View {
        let columns = rows.map(\.count).max() ?? 0
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, cell) in row.enumerated() where cell == "#" {
                    let rect = CGRect(x: CGFloat(x) * dot, y: CGFloat(y) * dot, width: dot, height: dot)
                        .insetBy(dx: dot * 0.09, dy: dot * 0.09)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(columns) * dot, height: CGFloat(rows.count) * dot)
        .shadow(color: color.opacity(0.55), radius: dot * 0.8)
        .accessibilityHidden(true)
    }
}

/// The dot-matrix "7" and "Term", as in "6 Bits".
struct Wordmark: View {
    var dot: CGFloat = 3

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: dot * 1.6) {
            PixelGlyph(rows: PixelGlyph.seven, dot: dot)
                .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            Text("Term")
                .font(Brand.mono(dot * 5.2, weight: .bold))
                .foregroundStyle(Brand.red)
                .shadow(color: Brand.red.opacity(0.45), radius: dot * 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("7 Term")
    }
}

/// A blinking block cursor after a prompt, like 6 Bits' "> select an entry█".
struct PromptLine: View {
    let text: String
    var color: Color = Brand.red
    @State private var isVisible = true

    var body: some View {
        HStack(spacing: 0) {
            Text("> " + text)
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 15)
                .opacity(isVisible ? 1 : 0)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .font(Brand.mono(13))
        .foregroundStyle(color)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(560))
                isVisible.toggle()
            }
        }
    }
}
