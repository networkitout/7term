import Foundation

/// The text on a tab, worked out from what the tab knows about itself.
///
/// A name the user gives the tab wins over everything, including the title
/// the remote shell sets, and is shown exactly as typed (no "· sftp" suffix).
/// Clearing it brings back the default label, which follows the remote
/// title again from then on.
public struct TabLabel: Equatable, Sendable {
    /// Mirrors the app's tab kinds, which decide the default label's suffix.
    public enum Kind: String, Sendable, CaseIterable {
        case ssh, sftp, files, serial
    }

    /// Longest custom name kept; the tab truncates long labels anyway.
    public static let maxCustomTitleLength = 60

    public var kind: Kind
    /// The saved host's name, when the tab came from the host list.
    public var savedName: String?
    /// What the remote shell set with an escape sequence. Used for quick ssh
    /// connections only: a saved host keeps its name.
    public var remoteTitle: String?
    /// user@host, or the serial port, when there's nothing better.
    public var destination: String
    /// Shown after an unsaved serial port's name.
    public var baudRate: Int?
    /// The user's own name for the tab; see `normalizedCustomTitle(_:)`.
    public var customTitle: String?

    public init(
        kind: Kind,
        savedName: String? = nil,
        remoteTitle: String? = nil,
        destination: String,
        baudRate: Int? = nil,
        customTitle: String? = nil
    ) {
        self.kind = kind
        self.savedName = savedName
        self.remoteTitle = remoteTitle
        self.destination = destination
        self.baudRate = baudRate
        self.customTitle = customTitle
    }

    /// What the tab shows.
    public var title: String {
        Self.normalizedCustomTitle(customTitle) ?? defaultTitle
    }

    /// Whether the user has renamed the tab.
    public var isCustom: Bool {
        Self.normalizedCustomTitle(customTitle) != nil
    }

    /// The label without the user's name: a saved host keeps its name; a
    /// quick ssh connection shows the remote title, falling back to user@host.
    public var defaultTitle: String {
        let base: String
        if let savedName, !savedName.isEmpty {
            base = savedName
        } else if let remoteTitle, !remoteTitle.isEmpty, kind == .ssh {
            base = remoteTitle
        } else {
            base = destination
        }
        switch kind {
        case .ssh: return base
        case .sftp: return base + " · sftp"
        case .files: return base + " · files"
        case .serial: return savedName == nil ? base + " · \(baudRate ?? 9600)" : base
        }
    }

    /// Cleans up a typed or pasted name: control characters and line breaks
    /// become spaces, runs of spaces collapse, the ends are trimmed, and it's
    /// cut to `maxCustomTitleLength`. Returns nil when nothing is left, which
    /// means "use the default label".
    public static func normalizedCustomTitle(_ text: String?) -> String? {
        guard let text else { return nil }
        var cleaned = ""
        var lastWasSpace = true
        for scalar in text.unicodeScalars {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
            if isSpace {
                if !lastWasSpace { cleaned.unicodeScalars.append(" ") }
                lastWasSpace = true
            } else {
                cleaned.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxCustomTitleLength else { return trimmed }
        return String(trimmed.prefix(maxCustomTitleLength)).trimmingCharacters(in: .whitespaces)
    }
}

/// A colour the user gives a tab, so several tabs to the same host can be
/// told apart. The raw values are stable, so they can be saved later
/// (for example as a saved host's default tab colour).
public enum TabColor: String, CaseIterable, Codable, Sendable {
    case none, red, orange, yellow, green, blue, purple, pink

    public var displayName: String {
        switch self {
        case .none: "None"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        }
    }

    /// Bright enough to stand out on the tab strip, which is always one of
    /// two near-black panels (7 Term red or 6 Bits green) whatever the
    /// terminal theme. Nil for `.none`.
    public var rgb: RGB? {
        switch self {
        case .none: nil
        case .red: RGB(hex: "#FF5C5C")
        case .orange: RGB(hex: "#FF9F40")
        case .yellow: RGB(hex: "#FFD84A")
        case .green: RGB(hex: "#4CD964")
        case .blue: RGB(hex: "#4AA8FF")
        case .purple: RGB(hex: "#B48CFF")
        case .pink: RGB(hex: "#FF7AC8")
        }
    }
}

extension RGB {
    /// WCAG relative luminance, 0 (black) to 1 (white).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1 to 21.
    public func contrastRatio(with other: RGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
