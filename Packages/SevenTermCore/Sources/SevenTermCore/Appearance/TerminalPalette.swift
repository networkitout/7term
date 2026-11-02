import Foundation

/// An sRGB color with components from 0 to 1.
public struct RGB: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// "#RRGGBB" or "RRGGBB". Traps on malformed input: only used for the
    /// built-in palettes, which are covered by tests.
    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            preconditionFailure("Bad hex color: \(hex)")
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    private func byte(_ component: Double) -> Int { Int((component * 255).rounded()) }
    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

/// The colors a terminal draws with: background, text, cursor, selection,
/// and the 16 ANSI colors (0–7 normal, 8–15 bright).
public struct TerminalPalette: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var background: RGB
    public var foreground: RGB
    public var cursor: RGB
    public var selection: RGB
    public var selectionOpacity: Double
    public var ansi: [RGB]
    public var isBuiltIn: Bool

    public init(
        id: String,
        name: String,
        background: RGB,
        foreground: RGB,
        cursor: RGB,
        selection: RGB,
        selectionOpacity: Double = 0.35,
        ansi: [RGB],
        isBuiltIn: Bool = false
    ) {
        precondition(ansi.count == 16, "A palette needs 16 ANSI colors")
        self.id = id
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.selectionOpacity = selectionOpacity
        self.ansi = ansi
        self.isBuiltIn = isBuiltIn
    }

    /// Whether the background is dark, so UI around the terminal can match.
    public var isDark: Bool {
        let b = background
        return 0.2126 * b.red + 0.7152 * b.green + 0.0722 * b.blue < 0.5
    }
}

/// The palettes that ship with 7 Term.
public enum BuiltInPalettes {
    public static let defaultID = "7term"

    public static let all: [TerminalPalette] = [sevenTerm, sixBits, nightRed, dark, light]

    public static func palette(id: String) -> TerminalPalette? {
        all.first { $0.id == id }
    }

    /// The 6 Bits look in red: red-tinted near-black, red cursor and selection.
    /// Text stays warm off-white so long sessions are easy to read.
    public static let sevenTerm = make(
        id: "7term", name: "7 Term",
        background: "#0D0909", foreground: "#EBE3DB", cursor: "#FF3434", selection: "#FF3434",
        ansi: ["#1A1A1D", "#E5484D", "#5FB878", "#D9B44A", "#5B8DEF", "#C277E0", "#4FB6C9", "#CFC8C0",
               "#5C5C66", "#FF6B6B", "#7EDB98", "#F2D06B", "#82A9FF", "#DA9BF5", "#74D3E3", "#FFFFFF"]
    )

    /// 6 Bits' own colors (#34FF68 on #090D0A). Text is green; colors stay
    /// distinct so `ls --color` and prompts still read.
    public static let sixBits = make(
        id: "6bits", name: "6 Bits",
        background: "#090D0A", foreground: "#34FF68", cursor: "#34FF68", selection: "#34FF68",
        selectionOpacity: 0.28,
        ansi: ["#0F1A11", "#FF5F56", "#3DFF6E", "#E6D84A", "#4FA3FF", "#C678DD", "#3FD8C8", "#B8F5C6",
               "#3B5A40", "#FF8A80", "#8CFFA8", "#FFF07A", "#8AC4FF", "#E0A6F0", "#7FF0E4", "#E8FFEE"]
    )

    /// Everything in dim reds, to protect night vision in a dark room.
    /// Lower contrast than the others: comfortable for short checks, tiring for long reading.
    public static let nightRed = make(
        id: "night-red", name: "Night Red",
        background: "#000000", foreground: "#B3261E", cursor: "#E52929", selection: "#7A1A14",
        selectionOpacity: 0.6,
        ansi: ["#140404", "#E52929", "#9C2A1F", "#C2402C", "#7A2018", "#A3271D", "#8A251B", "#B3261E",
               "#3A0E0A", "#FF4A3D", "#C23A2C", "#E05A40", "#9E3024", "#C73A2E", "#B03526", "#D9372B"]
    )

    public static let dark = make(
        id: "dark", name: "Dark",
        background: "#1E1E1E", foreground: "#D4D4D4", cursor: "#D4D4D4", selection: "#264F78",
        selectionOpacity: 0.8,
        ansi: ["#000000", "#CD3131", "#0DBC79", "#E5E510", "#2472C8", "#BC3FBC", "#11A8CD", "#E5E5E5",
               "#666666", "#F14C4C", "#23D18B", "#F5F543", "#3B8EEA", "#D670D6", "#29B8DB", "#FFFFFF"]
    )

    public static let light = make(
        id: "light", name: "Light",
        background: "#FFFFFF", foreground: "#1F1F1F", cursor: "#C41E1E", selection: "#ADD6FF",
        selectionOpacity: 0.8,
        ansi: ["#000000", "#C41E1E", "#00803A", "#8A6D00", "#0451A5", "#A626A4", "#0A7A8A", "#555555",
               "#6E6E6E", "#E0322B", "#14A04B", "#A88600", "#1A6FD8", "#BC05BC", "#0598BC", "#A5A5A5"]
    )

    private static func make(
        id: String, name: String,
        background: String, foreground: String, cursor: String, selection: String,
        selectionOpacity: Double = 0.35,
        ansi: [String]
    ) -> TerminalPalette {
        TerminalPalette(
            id: id, name: name,
            background: RGB(hex: background), foreground: RGB(hex: foreground),
            cursor: RGB(hex: cursor), selection: RGB(hex: selection),
            selectionOpacity: selectionOpacity,
            ansi: ansi.map(RGB.init(hex:)),
            isBuiltIn: true
        )
    }
}
