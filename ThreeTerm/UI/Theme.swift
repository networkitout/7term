import AppKit
import SwiftTerm
import SwiftUI

/// 3 Term's accent: night-ops red. Used for chrome, the caret and focus,
/// never as the only signal for a state.
@MainActor
enum Brand {
    static let red = Color(red: 0.90, green: 0.16, blue: 0.16)
    static let redNS = NSColor(srgbRed: 0.90, green: 0.16, blue: 0.16, alpha: 1)
}

/// Terminal colors. Milestone 4 adds the 6 Bits, dark and light themes,
/// .itermcolors import and the 16 ANSI colors.
@MainActor
struct TerminalTheme {
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let selection: NSColor

    /// Warm off-white text on near-black; red is spent on the caret and selection.
    static let threeTerm = TerminalTheme(
        background: NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1),
        foreground: NSColor(srgbRed: 0.92, green: 0.89, blue: 0.86, alpha: 1),
        caret: Brand.redNS,
        selection: NSColor(srgbRed: 0.90, green: 0.16, blue: 0.16, alpha: 0.35)
    )

    func apply(to view: TerminalView) {
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeBackgroundColor = background
        view.nativeForegroundColor = foreground
        view.caretColor = caret
        view.selectedTextBackgroundColor = selection
    }
}
