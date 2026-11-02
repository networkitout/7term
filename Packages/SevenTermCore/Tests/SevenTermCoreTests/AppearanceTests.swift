import Foundation
import Testing
@testable import SevenTermCore

@Suite struct PaletteTests {
    @Test func everyBuiltInHasSixteenColorsAndAUniqueID() {
        #expect(BuiltInPalettes.all.allSatisfy { $0.ansi.count == 16 && $0.isBuiltIn })
        #expect(Set(BuiltInPalettes.all.map(\.id)).count == BuiltInPalettes.all.count)
        #expect(BuiltInPalettes.palette(id: BuiltInPalettes.defaultID)?.name == "7 Term")
    }

    @Test func hexRoundTrips() {
        #expect(RGB(hex: "#E52929").hex == "#E52929")
        #expect(RGB(hex: "0e0e10").hex == "#0E0E10")
    }

    @Test func darknessFollowsBackground() {
        #expect(BuiltInPalettes.sevenTerm.isDark)
        #expect(!BuiltInPalettes.light.isDark)
    }

    @Test func fontSizeSteps() {
        #expect(FontSizeSteps.bigger(13) == 14)
        #expect(FontSizeSteps.smaller(9) == 9)
        #expect(FontSizeSteps.bigger(36) == 36)
        #expect(FontSizeSteps.clamped(100) == 36)
    }
}

@Suite struct ITermColorsImporterTests {
    private func component(_ red: Double, _ green: Double, _ blue: Double) -> [String: Any] {
        ["Red Component": red, "Green Component": green, "Blue Component": blue, "Color Space": "sRGB"]
    }

    private func scheme(includeCursor: Bool = true, dropAnsi: Int? = nil) throws -> Data {
        var root: [String: Any] = [
            "Background Color": component(0, 0, 0),
            "Foreground Color": component(1, 1, 1),
        ]
        for index in 0..<16 where index != dropAnsi {
            root["Ansi \(index) Color"] = component(Double(index) / 15, 0, 0)
        }
        if includeCursor { root["Cursor Color"] = component(0, 1, 0) }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    @Test func importsAllColors() throws {
        let palette = try ITermColorsImporter.palette(from: scheme(), name: "Test Scheme")
        #expect(palette.name == "Test Scheme")
        #expect(palette.ansi.count == 16)
        #expect(palette.ansi[15] == RGB(red: 1, green: 0, blue: 0))
        #expect(palette.cursor == RGB(red: 0, green: 1, blue: 0))
        #expect(!palette.isBuiltIn)
        #expect(palette.id.hasPrefix("imported-test_scheme-"))
    }

    @Test func cursorDefaultsToForeground() throws {
        let palette = try ITermColorsImporter.palette(from: scheme(includeCursor: false), name: "x")
        #expect(palette.cursor == palette.foreground)
    }

    @Test func missingAnsiColorIsReported() throws {
        #expect(throws: ITermColorsImporter.ImportError.missingColor("Ansi 7 Color")) {
            _ = try ITermColorsImporter.palette(from: scheme(dropAnsi: 7), name: "x")
        }
    }

    @Test func rejectsNonPlist() {
        #expect(throws: ITermColorsImporter.ImportError.notAPropertyList) {
            _ = try ITermColorsImporter.palette(from: Data("hello".utf8), name: "x")
        }
    }
}

@Suite struct PaletteStoreTests {
    @Test func savesLoadsAndDeletes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "7term-themes-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = PaletteStore(folder: folder)
        #expect(store.load().isEmpty)

        var palette = BuiltInPalettes.dark
        palette.id = "imported-mine"
        palette.name = "Mine"
        palette.isBuiltIn = false
        try store.save(palette)
        #expect(store.load() == [palette])

        try store.delete(id: palette.id)
        #expect(store.load().isEmpty)
    }
}
