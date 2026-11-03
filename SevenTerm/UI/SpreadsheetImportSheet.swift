import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SevenTermCore

/// File ▸ Import Hosts…: paste cells copied from Excel or Numbers, open a
/// CSV, or open another app's export (Royal TSX, SecureCRT, PuTTY/KiTTY, MobaXterm,
/// FileZilla, Ansible, Tabby). Shows what each row becomes before anything
/// is saved. Passwords are never read from any of them.
struct SpreadsheetImportSheet: View {
    @Environment(HostDirectory.self) private var hosts
    @Environment(\.chrome) private var chrome
    @Environment(\.dismiss) private var dismiss

    @State private var table: HostImportTable?
    @State private var tag = ""
    @State private var updateExisting = false
    @State private var message: String?
    @State private var isTargeted = false
    /// Set when the rows came from another app's export.
    @State private var appSource: ForeignImportFormat?
    @State private var skipped: [String] = []

    private var candidates: [HostImportCandidate] {
        table?.candidates(existing: hosts.entries, tag: tag) ?? []
    }

    private var importable: [HostImportCandidate] {
        candidates.filter { $0.isImportable && ($0.existingID == nil || updateExisting) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Hosts")
                .font(.headline)
            if let table {
                if let appSource {
                    appSummary(appSource, count: table.rows.count)
                } else {
                    mapping(table)
                }
                preview
                options
            } else {
                start
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(20)
        .frame(width: 760, height: table == nil ? 330 : 560)
    }

    // MARK: Step 1: get the rows

    private var start: some View {
        VStack(spacing: 14) {
            Image(systemName: "tablecells")
                .font(.system(size: 34))
                .foregroundStyle(chrome.accent)
            Text("Copy the cells in Excel or Numbers and paste them here, or open a CSV.")
                .multilineTextAlignment(.center)
            Text("A header row (Name, Host or IP, Port, User, Tags, Key) helps 7 Term match the columns. Columns that look like passwords are never read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Paste Rows") { pasteRows() }
                    .keyboardShortcut("v", modifiers: .command)
                Button("Open CSV…") { chooseFile() }
                Button("From Another App…") { chooseAppExport() }
                    .help(ForeignImportFormat.allCases.map(\.hint).uniqued().joined(separator: "\n\n"))
            }
            Text("From another app: Royal TSX, SecureCRT, PuTTY or KiTTY, MobaXterm, FileZilla, an Ansible inventory, or Tabby. Hover the button for where each keeps its sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(isTargeted ? chrome.accent : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5, 4]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func pasteRows() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            message = "The clipboard has no text. Copy the cells first."
            return
        }
        use(text, source: "the clipboard")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
            + [UTType("org.openxmlformats.spreadsheetml.sheet"), UTType("com.apple.iwork.numbers.sheet")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        if url.hasDirectoryPath || ["reg", "mxtsessions", "xml", "yaml", "yml", "ini", "rtsz", "rtsx"].contains(url.pathExtension.lowercased()) {
            loadAppExport(url)
            return
        }
        if ["xlsx", "xls", "numbers"].contains(url.pathExtension.lowercased()) {
            message = "7 Term reads CSV, not .\(url.pathExtension) files. In Excel or Numbers, select the cells and copy them, then click Paste Rows. Or export as CSV."
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            message = "Couldn't read \(url.lastPathComponent)."
            return
        }
        // Excel on a Mac saves "CSV UTF-8" or Windows Latin 1.
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
        use(text, source: url.lastPathComponent)
    }

    private func use(_ text: String, source: String) {
        let parsed = HostImportTable.parse(text)
        guard !parsed.rows.isEmpty, parsed.columns.contains(.host) else {
            message = "No rows found in \(source)."
            return
        }
        table = parsed
        var notes = ["Read \(parsed.rows.count) row\(parsed.rows.count == 1 ? "" : "s") from \(source)."]
        if parsed.header == nil { notes.append("No header row, so the columns are a guess. Check them below.") }
        if !parsed.secretColumns.isEmpty { notes.append("Password columns are ignored.") }
        message = notes.joined(separator: " ")
    }

    // MARK: Another app's export

    private func chooseAppExport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose an export file, or SecureCRT's Sessions folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadAppExport(url)
    }

    private func loadAppExport(_ url: URL) {
        let result: ForeignImportResult
        let format: ForeignImportFormat
        do {
            if url.hasDirectoryPath {
                format = .secureCRT
                result = SecureCRTImport.parse(files: try Self.sessionFiles(in: url))
            } else {
                let text = decodeExportText(try Data(contentsOf: url))
                guard let detected = ForeignImportFormat.detect(fileName: url.lastPathComponent, text: text) else {
                    message = "Couldn't tell which app \(url.lastPathComponent) came from."
                    return
                }
                format = detected
                result = try detected.parse(text)
            }
        } catch {
            message = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            return
        }
        guard !result.hosts.isEmpty else {
            message = "No SSH hosts found in \(url.lastPathComponent)"
                + (result.skipped.isEmpty ? "." : " (\(result.skipped.count) other sessions skipped).")
            return
        }
        appSource = format
        skipped = result.skipped
        table = result.table
        message = "Read \(result.hosts.count) host\(result.hosts.count == 1 ? "" : "s") from \(format.title). Passwords aren't imported."
    }

    /// SecureCRT's Sessions folder: every .ini below it, with its path.
    private static func sessionFiles(in folder: URL) throws -> [(path: String, text: String)] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        let base = folder.standardizedFileURL.pathComponents.count
        var files: [(path: String, text: String)] = []
        while let item = walker.nextObject() as? URL, files.count < 5000 {
            guard item.pathExtension.lowercased() == "ini",
                  (try? item.resourceValues(forKeys: Set(keys)))?.isRegularFile == true
            else { continue }
            let relative = item.standardizedFileURL.pathComponents.dropFirst(base).joined(separator: "/")
            files.append((relative, decodeExportText(try Data(contentsOf: item))))
        }
        return files
    }

    private func appSummary(_ format: ForeignImportFormat, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(format.title): \(count) SSH host\(count == 1 ? "" : "s")", systemImage: "square.and.arrow.down")
                .foregroundStyle(chrome.accent)
            if !skipped.isEmpty {
                DisclosureGroup("\(skipped.count) left out (not SSH, or no host)") {
                    ScrollView {
                        Text(skipped.joined(separator: "\n"))
                            .font(Brand.mono(10.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 70)
                }
                .font(.caption)
            }
        }
    }

    // MARK: Step 2: check the columns and rows

    private func mapping(_ table: HostImportTable) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<table.columnCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(table.header?[index] ?? "Column \(index + 1)")
                            .font(Brand.mono(10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if table.secretColumns.contains(index) {
                            Label("Ignored", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Looks like a password column. 7 Term never imports passwords.")
                        } else {
                            Picker("Column \(index + 1)", selection: binding(for: index)) {
                                ForEach(HostImportColumn.allCases, id: \.self) { column in
                                    Text(column.title).tag(column)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Text(table.rows.first?[index] ?? "")
                            .font(Brand.mono(10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 110, alignment: .leading)
                }
            }
            .padding(.bottom, 4)
        }
    }

    /// Choosing a column's meaning takes it away from any other column.
    private func binding(for index: Int) -> Binding<HostImportColumn> {
        Binding {
            table?.columns[index] ?? .ignore
        } set: { column in
            guard var updated = table else { return }
            if column != .ignore {
                for other in updated.columns.indices where updated.columns[other] == column {
                    updated.columns[other] = .ignore
                }
            }
            updated.columns[index] = column
            table = updated
        }
    }

    private var preview: some View {
        List(candidates) { candidate in
            HStack(spacing: 8) {
                statusIcon(candidate)
                    .frame(width: 16)
                Text("\(candidate.line)")
                    .font(Brand.mono(10.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
                Text(candidate.draft.name.isEmpty ? "—" : candidate.draft.name)
                    .font(Brand.mono(12, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 170, alignment: .leading)
                Text(candidate.draft.target?.displayName ?? candidate.draft.hostname)
                    .font(Brand.mono(11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)
                Text(detail(candidate))
                    .font(.caption)
                    .foregroundStyle(candidate.isImportable ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .help(detail(candidate))
            }
        }
        .listStyle(.bordered)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func statusIcon(_ candidate: HostImportCandidate) -> some View {
        if !candidate.isImportable {
            Image(systemName: "xmark.circle").foregroundStyle(.red)
                .accessibilityLabel("Can't import")
        } else if candidate.existingID != nil {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                .accessibilityLabel("Already saved")
        } else {
            Image(systemName: "plus.circle").foregroundStyle(chrome.accent)
                .accessibilityLabel("New")
        }
    }

    private func detail(_ candidate: HostImportCandidate) -> String {
        if !candidate.isImportable { return candidate.problems.joined(separator: " ") }
        let tags = candidate.draft.tagList.joined(separator: ", ")
        if candidate.existingID != nil {
            return updateExisting ? "updates the saved host" + (tags.isEmpty ? "" : " · adds \(tags)") : "already saved, skipped"
        }
        return tags
    }

    private var options: some View {
        HStack(spacing: 16) {
            TextField("Add a tag to all", text: $tag, prompt: Text("Tag for every host (optional)"))
                .frame(width: 240)
            Toggle("Update hosts that are already saved", isOn: $updateExisting)
                .help("Fills in name, port, user and key from the sheet and adds its tags. Passwords and logging settings are kept.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if table != nil {
                Button("Start Over") {
                    table = nil
                    appSource = nil
                    skipped = []
                    message = nil
                }
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if table != nil {
                Button(importTitle) { runImport() }
                    .keyboardShortcut(.defaultAction)
                    .tint(chrome.accent)
                    .disabled(importable.isEmpty)
            }
        }
    }

    private var importTitle: String {
        let count = importable.count
        return count == 1 ? "Import 1 Host" : "Import \(count) Hosts"
    }

    private func runImport() {
        do {
            _ = try hosts.importSpreadsheet(importable, updateExisting: updateExisting)
            dismiss()
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
