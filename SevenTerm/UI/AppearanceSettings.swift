import SwiftUI
import SevenTermCore
import UniformTypeIdentifiers

/// 7 Term ▸ Settings… (⌘,): theme, font and size.
struct AppearanceSettings: View {
    @Environment(Appearance.self) private var appearance
    @State private var isImporting = false
    @State private var importError: String?
    @State private var families: [String] = []

    var body: some View {
        @Bindable var appearance = appearance

        Form {
            Section("Theme") {
                Picker("Theme", selection: $appearance.paletteID) {
                    ForEach(BuiltInPalettes.all) { palette in
                        Text(palette.name).tag(palette.id)
                    }
                    if !appearance.importedPalettes.isEmpty {
                        Divider()
                        ForEach(appearance.importedPalettes) { palette in
                            Text(palette.name).tag(palette.id)
                        }
                    }
                }

                PalettePreview(palette: appearance.palette, font: appearance.font)

                HStack {
                    Button("Import .itermcolors…") { isImporting = true }
                    if !appearance.palette.isBuiltIn {
                        Button("Remove \"\(appearance.palette.name)\"", role: .destructive) {
                            try? appearance.removeImported(id: appearance.paletteID)
                        }
                    }
                }
                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Text") {
                Picker("Font", selection: $appearance.fontFamily) {
                    Text("SF Mono (system)").tag(String?.none)
                    Divider()
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(String?.some(family))
                    }
                }
                Stepper(value: $appearance.fontSize, in: FontSizeSteps.range, step: 1) {
                    LabeledContent("Size", value: "\(Int(appearance.fontSize)) pt")
                }
                Text("⌘+ and ⌘- change the size in every tab; ⌘0 resets it to \(Int(FontSizeSteps.defaultSize)) pt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { families = Appearance.monospacedFamilies() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "itermcolors") ?? .propertyList]
        ) { result in
            do {
                try appearance.importITermColors(from: result.get())
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

/// A few lines drawn in the palette's colors, plus its 16 ANSI swatches.
private struct PalettePreview: View {
    let palette: TerminalPalette
    let font: NSFont

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                (Text("root@pve01").foregroundStyle(palette.ansi[10].swiftUIColor)
                    + Text(":").foregroundStyle(palette.foreground.swiftUIColor)
                    + Text("~").foregroundStyle(palette.ansi[12].swiftUIColor)
                    + Text("# ls").foregroundStyle(palette.foreground.swiftUIColor))
                (Text("backups  ").foregroundStyle(palette.ansi[12].swiftUIColor)
                    + Text("notes.txt  ").foregroundStyle(palette.foreground.swiftUIColor)
                    + Text("run.sh").foregroundStyle(palette.ansi[10].swiftUIColor))
                Text("error: disk 92% full").foregroundStyle(palette.ansi[9].swiftUIColor)
            }
            .font(.custom(font.fontName, size: 12))

            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.ansi[index].swiftUIColor)
                        .frame(width: 18, height: 12)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.background.swiftUIColor))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(palette.name) theme")
    }
}
