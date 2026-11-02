import AppKit
import SwiftUI
import SevenTermCore

/// A file browser tab: this Mac on the left, the host on the right, the
/// transfer queue underneath. Drag between the panes (or from Finder onto
/// the right) to copy.
struct FileBrowserView: View {
    let browser: FileBrowser
    @Environment(\.chrome) private var chrome

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                FilePaneView(pane: browser.local, browser: browser)
                    .frame(minWidth: 280)
                FilePaneView(pane: browser.remote, browser: browser)
                    .frame(minWidth: 280)
            }
            if !browser.transfers.isEmpty {
                Divider()
                TransferList(browser: browser)
                    .frame(height: 150)
            }
            Divider()
            StatusBar(browser: browser)
        }
        .background(chrome.background)
    }
}

private struct FilePaneView: View {
    @Bindable var pane: FilePane
    let browser: FileBrowser
    @Environment(\.chrome) private var chrome
    @State private var pathText = ""
    @State private var isTargeted = false

    private var isRemote: Bool { pane.side == .remote }
    private var isUsable: Bool { !isRemote || browser.connection == .connected }

    var body: some View {
        VStack(spacing: 0) {
            header
            pathBar
            Divider()
            table
                .overlay {
                    if isRemote, browser.connection == .connecting {
                        ProgressView().controlSize(.small)
                    }
                }
                .overlay {
                    if isTargeted {
                        Rectangle().strokeBorder(chrome.accent, lineWidth: 2)
                    }
                }
            if let error = pane.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .background(chrome.panel)
        .onAppear { pathText = pane.path }
        .onChange(of: pane.path) { pathText = pane.path }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: isRemote ? "server.rack" : "laptopcomputer")
                .foregroundStyle(chrome.accent)
            Text(isRemote ? browser.hostLabel.uppercased() : "THIS MAC")
                .font(Brand.mono(11, weight: .bold))
                .foregroundStyle(chrome.accent)
                .lineLimit(1)
            Spacer()
            if isRemote {
                Button {
                    browser.downloadSelection()
                } label: {
                    Label("Download", systemImage: "arrow.left")
                }
                .disabled(pane.selection.isEmpty || !isUsable)
                .help("Copy the selected items to the folder on the left")
            } else {
                Button {
                    browser.uploadSelection()
                } label: {
                    Label("Upload", systemImage: "arrow.right")
                }
                .disabled(pane.selection.isEmpty || browser.connection != .connected)
                .help("Copy the selected items to the folder on the right")
            }
        }
        .font(Brand.mono(11))
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Button {
                browser.goUp(pane.side)
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Enclosing folder")
            .disabled(pane.path == "/" || !isUsable)

            TextField("Path", text: $pathText)
                .textFieldStyle(.plain)
                .font(Brand.mono(11.5))
                .autocorrectionDisabled()
                .onSubmit { browser.go(pane.side, to: pathText) }
                .disabled(!isUsable)

            Button {
                browser.refresh(pane.side)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(!isUsable)

            Button {
                browser.newFolder(in: pane.side)
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New folder")
            .disabled(!isUsable)

            Toggle(isOn: $pane.showHidden) {
                Image(systemName: pane.showHidden ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
            .help(pane.showHidden ? "Hide dotfiles" : "Show dotfiles")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var table: some View {
        Table(of: FileRow.self, selection: $pane.selection, sortOrder: $pane.sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    Image(systemName: row.icon)
                        .foregroundStyle(row.isDirectory ? chrome.accent : .secondary)
                        .frame(width: 16)
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(row.mode.isEmpty ? row.name : "\(row.mode)  \(row.name)")
            }
            TableColumn("Size", value: \.size) { row in
                Text(row.sizeText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 75, max: 100)
            TableColumn("Modified", value: \.modified) { row in
                Text(row.modified == .distantPast ? "" : row.modified.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 140, max: 180)
        } rows: {
            ForEach(pane.sortedRows) { row in
                TableRow(row)
                    .itemProvider { itemProvider(for: row) }
            }
        }
        .font(Brand.mono(12))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: FileRow.ID.self) { ids in
            contextMenu(ids)
        } primaryAction: { ids in
            browser.open(ids, in: pane.side)
        }
        .onDeleteCommand { browser.delete(pane.selection, in: pane.side) }
        .modifier(DropTarget(pane: pane, browser: browser, isTargeted: $isTargeted))
        .disabled(!isUsable)
    }

    /// Local rows drag as file URLs (so Finder and the right pane accept
    /// them); remote rows carry a payload only this browser's left pane reads.
    private func itemProvider(for row: FileRow) -> NSItemProvider? {
        switch pane.side {
        case .local:
            return NSItemProvider(contentsOf: URL(fileURLWithPath: pane.fullPath(row)))
        case .remote:
            return NSItemProvider(object: browser.dragPayload(for: row) as NSString)
        }
    }

    @ViewBuilder
    private func contextMenu(_ ids: Set<FileRow.ID>) -> some View {
        if ids.isEmpty {
            Button("New Folder…") { browser.newFolder(in: pane.side) }
            Button("Refresh") { browser.refresh(pane.side) }
        } else {
            Button("Open") { browser.open(ids, in: pane.side) }
            if isRemote {
                Button("Download") { browser.download(paths: rowPaths(ids)) }
            } else {
                Button("Upload") { browser.upload(urls: rowPaths(ids).map { URL(fileURLWithPath: $0) }) }
                    .disabled(browser.connection != .connected)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(rowPaths(ids).map { URL(fileURLWithPath: $0) })
                }
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rowPaths(ids).joined(separator: "\n"), forType: .string)
            }
            if ids.count == 1, let id = ids.first {
                Button("Rename…") { browser.rename(id, in: pane.side) }
            }
            Divider()
            Button(isRemote ? "Delete…" : "Move to Trash", role: .destructive) {
                browser.delete(ids, in: pane.side)
            }
        }
    }

    private func rowPaths(_ ids: Set<FileRow.ID>) -> [String] {
        pane.rows.filter { ids.contains($0.id) }.map(pane.fullPath)
    }
}

/// The right pane takes file URLs (from the left pane or Finder) and
/// uploads them; the left pane takes rows dragged from the right.
private struct DropTarget: ViewModifier {
    let pane: FilePane
    let browser: FileBrowser
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        switch pane.side {
        case .remote:
            content.dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty, browser.connection == .connected else { return false }
                browser.upload(urls: files)
                return true
            } isTargeted: { isTargeted = $0 }
        case .local:
            content.dropDestination(for: String.self) { items, _ in
                let paths = browser.remotePaths(fromDrop: items)
                guard !paths.isEmpty else { return false }
                browser.download(paths: paths)
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}

private struct TransferList: View {
    let browser: FileBrowser
    @Environment(\.chrome) private var chrome

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TRANSFERS")
                    .font(Brand.mono(10.5, weight: .bold))
                    .foregroundStyle(chrome.accent)
                Text(summary)
                    .font(Brand.mono(10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Finished") { browser.clearFinished() }
                    .buttonStyle(.borderless)
                    .font(Brand.mono(10.5))
                    .disabled(!browser.transfers.contains(where: \.isFinished))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            List(browser.transfers.reversed()) { transfer in
                TransferRow(transfer: transfer)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(chrome.panel)
    }

    private var summary: String {
        let active = browser.transfers.filter { !$0.isFinished }.count
        return active == 0 ? "" : "· \(active) to go"
    }
}

private struct TransferRow: View {
    let transfer: Transfer
    @Environment(\.chrome) private var chrome

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: transfer.direction == .upload ? "arrow.right" : "arrow.left")
                .foregroundStyle(chrome.accent)
                .frame(width: 14)
                .accessibilityLabel(transfer.direction == .upload ? "Upload" : "Download")
            Text(transfer.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 120, alignment: .leading)
                .help(transfer.direction == .upload ? transfer.remotePath : transfer.localURL.path)
            Spacer(minLength: 8)
            detail
            if !transfer.isFinished {
                Button {
                    transfer.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            }
        }
        .font(Brand.mono(11.5))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var detail: some View {
        switch transfer.state {
        case .queued:
            Text("waiting").foregroundStyle(.secondary)
        case .running:
            if let fraction = transfer.fraction {
                ProgressView(value: fraction)
                    .frame(width: 140)
                    .tint(chrome.accent)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(ByteCountFormatter.string(fromByteCount: Int64(transfer.transferred), countStyle: .file))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        case .done:
            if let sha = transfer.sha256 {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sha, forType: .string)
                } label: {
                    Text("sha256 \(sha.prefix(12))…")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("SHA-256 of the bytes copied. Click to copy all of it.\n\(sha)")
            }
            Text(ByteCountFormatter.string(fromByteCount: Int64(transfer.transferred), countStyle: .file))
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark").foregroundStyle(.green)
                .accessibilityLabel("Done")
        case .skipped:
            Text("skipped").foregroundStyle(.secondary)
        case .cancelled:
            Text("cancelled").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(1)
                .help(message)
        }
    }
}

private struct StatusBar: View {
    let browser: FileBrowser

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(browser.status ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            if case .closed = browser.connection {
                Text("⇧⌘R to reconnect").foregroundStyle(.secondary)
            }
        }
        .font(Brand.mono(10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var dotColor: Color {
        switch browser.connection {
        case .connected: .green
        case .connecting: .yellow
        case .idle, .closed: .gray
        }
    }
}
