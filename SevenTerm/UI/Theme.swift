import AppKit
import SwiftTerm
import SwiftUI
import SevenTermCore

extension RGB {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var swiftUIColor: SwiftUI.Color {
        SwiftUI.Color(.sRGB, red: red, green: green, blue: blue)
    }

    /// SwiftTerm's own color type, 16 bits per component.
    var terminalColor: SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((red * 65535).rounded()),
            green: UInt16((green * 65535).rounded()),
            blue: UInt16((blue * 65535).rounded())
        )
    }
}

extension TerminalPalette {
    /// Sets every color the terminal view draws with.
    @MainActor func apply(to view: TerminalView) {
        view.nativeBackgroundColor = background.nsColor
        view.nativeForegroundColor = foreground.nsColor
        view.caretColor = cursor.nsColor
        view.selectedTextBackgroundColor = selection.nsColor.withAlphaComponent(selectionOpacity)
        view.installColors(ansi.map(\.terminalColor))
    }
}
