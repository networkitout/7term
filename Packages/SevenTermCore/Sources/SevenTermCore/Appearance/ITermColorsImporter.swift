import Foundation

/// Reads iTerm2 `.itermcolors` files: a property list with one dictionary per
/// color ("Ansi 0 Color" … "Ansi 15 Color", "Background Color",
/// "Foreground Color", and optionally "Cursor Color" and "Selection Color"),
/// each holding "Red Component", "Green Component" and "Blue Component" from 0 to 1.
public enum ITermColorsImporter {
    public enum ImportError: Error, Equatable, LocalizedError {
        case notAPropertyList
        case missingColor(String)

        public var errorDescription: String? {
            switch self {
            case .notAPropertyList: "That file isn't an .itermcolors color scheme."
            case .missingColor(let key): "The scheme has no \"\(key)\"."
            }
        }
    }

    public static func palette(from data: Data, name: String) throws -> TerminalPalette {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any]
        else { throw ImportError.notAPropertyList }

        func color(_ key: String) -> RGB? {
            guard let entry = root[key] as? [String: Any],
                  let red = number(entry["Red Component"]),
                  let green = number(entry["Green Component"]),
                  let blue = number(entry["Blue Component"])
            else { return nil }
            return RGB(red: red, green: green, blue: blue)
        }

        func required(_ key: String) throws -> RGB {
            guard let value = color(key) else { throw ImportError.missingColor(key) }
            return value
        }

        let ansi = try (0..<16).map { try required("Ansi \($0) Color") }
        let background = try required("Background Color")
        let foreground = try required("Foreground Color")

        return TerminalPalette(
            id: "imported-" + LogNaming.safeComponent(name.lowercased()) + "-" + String(UUID().uuidString.prefix(8)),
            name: name,
            background: background,
            foreground: foreground,
            cursor: color("Cursor Color") ?? foreground,
            selection: color("Selection Color") ?? foreground,
            selectionOpacity: color("Selection Color") == nil ? 0.3 : 0.8,
            ansi: ansi,
            isBuiltIn: false
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let number as NSNumber: number.doubleValue
        default: nil
        }
    }
}

/// Imported palettes, one JSON file each in a folder
/// (~/Library/Application Support/7 Term/Themes/).
public struct PaletteStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func load() -> [TerminalPalette] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(TerminalPalette.self, from: Data(contentsOf: $0)) }
            .filter { !$0.isBuiltIn && $0.ansi.count == 16 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func save(_ palette: TerminalPalette) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(palette).write(to: url(for: palette.id), options: .atomic)
    }

    public func delete(id: String) throws {
        let url = url(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func url(for id: String) -> URL {
        folder.appending(path: LogNaming.safeComponent(id) + ".json", directoryHint: .notDirectory)
    }
}

/// Font sizes for ⌘+ and ⌘-.
public enum FontSizeSteps {
    public static let defaultSize = 13.0
    public static let range = 9.0...36.0

    public static func bigger(_ size: Double) -> Double { min(range.upperBound, size.rounded() + 1) }
    public static func smaller(_ size: Double) -> Double { max(range.lowerBound, size.rounded() - 1) }
    public static func clamped(_ size: Double) -> Double { min(range.upperBound, max(range.lowerBound, size)) }
}
