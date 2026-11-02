import SwiftUI

/// The colors of the window around the terminal: accent, backgrounds and
/// selection. 7 Term's own look is the 6 Bits family in tactical red; the
/// 6 Bits theme switches the whole window to 6 Bits' own green.
struct Chrome: Equatable, Sendable {
    /// Logo, cursor glyph, tab underline, REC badge, buttons.
    var accent: Color
    /// Window and toolbar background.
    var background: Color
    /// Sidebar and tab strip.
    var panel: Color
    /// Selected sidebar row.
    var selection: Color
    var isGreen: Bool

    /// 7 Term: #FF3434 on red-tinted black.
    static let red = Chrome(
        accent: Color(.sRGB, red: 1.00, green: 0.204, blue: 0.204),
        background: Color(.sRGB, red: 0.051, green: 0.035, blue: 0.035),
        panel: Color(.sRGB, red: 0.082, green: 0.059, blue: 0.059),
        selection: Color(.sRGB, red: 0.227, green: 0.078, blue: 0.078),
        isGreen: false
    )

    /// 6 Bits, measured from its window: #34FF68 on #090D0A, sidebar #0F1511,
    /// selected row #14361D.
    static let green = Chrome(
        accent: Color(.sRGB, red: 0.204, green: 1.00, blue: 0.408),
        background: Color(.sRGB, red: 0.035, green: 0.051, blue: 0.039),
        panel: Color(.sRGB, red: 0.059, green: 0.082, blue: 0.067),
        selection: Color(.sRGB, red: 0.078, green: 0.212, blue: 0.114),
        isGreen: true
    )

    static func forPalette(id: String) -> Chrome {
        id == "6bits" ? .green : .red
    }
}

extension EnvironmentValues {
    /// Set once at the top of each window from the current theme.
    @Entry var chrome: Chrome = .red
}

@MainActor
enum Brand {
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
    /// Defaults to the window's accent.
    var color: Color?
    @Environment(\.chrome) private var chrome

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
        let color = self.color ?? chrome.accent
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
    @Environment(\.chrome) private var chrome

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: dot * 1.6) {
            PixelGlyph(rows: PixelGlyph.seven, dot: dot)
                .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            Text("Term")
                .font(Brand.mono(dot * 5.2, weight: .bold))
                .foregroundStyle(chrome.accent)
                .shadow(color: chrome.accent.opacity(0.45), radius: dot * 0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("7 Term")
    }
}

/// A blinking block cursor after a prompt, like 6 Bits' "> select an entry█".
struct PromptLine: View {
    let text: String
    @Environment(\.chrome) private var chrome
    @State private var isVisible = true

    var body: some View {
        HStack(spacing: 0) {
            Text("> " + text)
            Rectangle()
                .fill(chrome.accent)
                .frame(width: 8, height: 15)
                .opacity(isVisible ? 1 : 0)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .font(Brand.mono(13))
        .foregroundStyle(chrome.accent)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(560))
                isVisible.toggle()
            }
        }
    }
}
