import AppKit
import Foundation
import Observation
import SwiftTerm
import SevenTermCore

/// Theme, font and size, shared by every tab. Changing any of them updates
/// all open terminals at once (zoom is global, not per tab).
/// Stored in UserDefaults; imported themes are JSON files in
/// ~/Library/Application Support/7 Term/Themes/.
@MainActor
@Observable
final class Appearance {
    private(set) var importedPalettes: [TerminalPalette] = []

    var paletteID: String {
        didSet { defaults.set(paletteID, forKey: Keys.palette); changed() }
    }

    /// A font family name, or nil for the system monospaced font (SF Mono).
    var fontFamily: String? {
        didSet { defaults.set(fontFamily, forKey: Keys.fontFamily); changed() }
    }

    /// Points. Callers keep it within FontSizeSteps.range.
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize); changed() }
    }

    /// Called after any change; SessionStore uses it to restyle open tabs.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let store = PaletteStore(
        folder: URL.applicationSupportDirectory.appending(path: "7 Term/Themes", directoryHint: .isDirectory)
    )

    private enum Keys {
        static let palette = "terminalPalette"
        static let fontFamily = "terminalFontFamily"
        static let fontSize = "terminalFontSize"
    }

    init() {
        paletteID = UserDefaults.standard.string(forKey: Keys.palette) ?? BuiltInPalettes.defaultID
        fontFamily = UserDefaults.standard.string(forKey: Keys.fontFamily)
        let savedSize = UserDefaults.standard.double(forKey: Keys.fontSize)
        fontSize = savedSize > 0 ? FontSizeSteps.clamped(savedSize) : FontSizeSteps.defaultSize
        importedPalettes = store.load()
    }

    var palettes: [TerminalPalette] {
        BuiltInPalettes.all + importedPalettes
    }

    var palette: TerminalPalette {
        palettes.first { $0.id == paletteID } ?? BuiltInPalettes.sevenTerm
    }

    var font: NSFont {
        let size = CGFloat(fontSize)
        if let fontFamily, let font = NSFont(name: fontFamily, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func apply(to view: TerminalView) {
        view.font = font
        palette.apply(to: view)
    }

    // MARK: Zoom (⌘+ / ⌘- / ⌘0)

    func makeBigger() { fontSize = FontSizeSteps.bigger(fontSize) }
    func makeSmaller() { fontSize = FontSizeSteps.smaller(fontSize) }
    func resetSize() { fontSize = FontSizeSteps.defaultSize }

    var canMakeBigger: Bool { fontSize < FontSizeSteps.range.upperBound }
    var canMakeSmaller: Bool { fontSize > FontSizeSteps.range.lowerBound }

    // MARK: Imported themes

    /// Imports an .itermcolors file and switches to it.
    func importITermColors(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let palette = try ITermColorsImporter.palette(from: data, name: url.deletingPathExtension().lastPathComponent)
        try store.save(palette)
        importedPalettes = store.load()
        paletteID = palette.id
    }

    func removeImported(id: String) throws {
        try store.delete(id: id)
        importedPalettes = store.load()
        if paletteID == id { paletteID = BuiltInPalettes.defaultID }
    }

    /// Monospaced font families installed on this Mac.
    static func monospacedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            NSFont(name: family, size: 12)?.isFixedPitch == true
        }
    }

    private func changed() {
        onChange?()
    }
}
