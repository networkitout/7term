import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SevenTermCore

/// File ▸ Import from Spreadsheet…: paste cells copied from Excel or Numbers,
/// or open a CSV. Shows how each column was read and what each row becomes
/// before anything is saved.
struct SpreadsheetImportSheet: View {
    @Environment(HostDirectory.self) private var hosts
    @Environment(\.chrome) private var chrome
    @Environment(\.dismiss) private var dismiss

    @State private var table: HostImportTable?
    @State private var tag = ""
    @State private var updateExisting = false
    @State private var message: String?
    @State private var isTargeted = false

    private var candidates: [HostImportCandidate] {
        table?.candidates(existing: hosts.entries, tag: tag) ?? []
    }

    private var importable: [HostImportCandidate] {
        candidates.filter { $0.isImportable && ($0.existingID == nil || updateExisting) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Hosts from a Spreadsheet")
                .font(.headline)
            if let table {
                mapping(table)
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
            }
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
