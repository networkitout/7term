import SwiftUI
import SevenTermCore

/// Saved hosts in their folders, with type-to-filter and a tag filter.
/// Double-click or Return opens ssh on a host and opens or closes a folder;
/// the row's SFTP button opens the file browser, and the right-click and
/// Host menus also offer the sftp prompt. Rows drag onto folders to move.
struct HostSidebar: View {
    @Environment(\.chrome) private var chrome
    @Environment(HostDirectory.self) private var hosts
    @Environment(SessionStore.self) private var sessions

    var body: some View {
        @Bindable var hosts = hosts

        List(selection: $hosts.selectedID) {
            HostTreeRows(nodes: hosts.tree)
        }
        .scrollContentBackground(.hidden)
        .background(chrome.panel)
        // A drop below the rows goes to the top level.
        .dropDestination(for: String.self) { itemIDs, _ in
            for id in itemIDs { hosts.move(itemID: id, toFolder: nil) }
            return !itemIDs.isEmpty
        }
        .contextMenu(forSelectionType: String.self) { itemIDs in
            if let folder = itemIDs.first.flatMap(hosts.folder(id:)) {
                Button("New Host…") { hosts.editor = .new }
                Button("New Folder…") { hosts.folderNameRequest = .new(parentId: folder.id) }
                Divider()
                Button("Rename…") { hosts.folderNameRequest = .rename(folder) }
                moveMenu(itemID: folder.id)
                Divider()
                Button("Delete…", role: .destructive) { hosts.pendingFolderDelete = folder }
            } else if let entry = itemIDs.first.flatMap(hosts.entry(id:)) {
                if entry.host.kind == .serial {
                    Button("Open Serial Console") { sessions.open(entry, kind: .ssh) }
                } else {
                    Button("Connect with SSH") { sessions.open(entry, kind: .ssh) }
                    Button("Browse Files (SFTP)") { sessions.open(entry, kind: .files) }
                    Button("SFTP Prompt") { sessions.open(entry, kind: .sftp) }
                    ForEach(FileTransferApp.installed) { app in
                        Button("Open in \(app.name)") {
                            Task { await app.open(entry.host.target) }
                        }
                    }
                }
                Divider()
                Button("Edit…") { hosts.editor = .edit(entry) }
                Button("Duplicate") { hosts.duplicate(entry) }
                moveMenu(itemID: entry.id)
                Button("Copy Hostname") { hosts.copyHostname(entry) }
                Divider()
                Button("Delete…", role: .destructive) { hosts.pendingDelete = entry }
            } else {
                Button("New Host…") { hosts.editor = .new }
                Button("New Folder…") { hosts.folderNameRequest = .new(parentId: nil) }
            }
        } primaryAction: { itemIDs in
            guard let id = itemIDs.first else { return }
            if hosts.folder(id: id) != nil {
                if !hosts.isFiltering { hosts.expandedFolderIDs.formSymmetricDifference([id]) }
            } else if let entry = hosts.entry(id: id) {
                sessions.open(entry, kind: .ssh)
            }
        }
        .onDeleteCommand {
            if let folder = hosts.selectedFolder {
                hosts.pendingFolderDelete = folder
            } else {
                hosts.pendingDelete = hosts.selectedEntry
            }
        }
        .searchable(text: $hosts.query, placement: .sidebar, prompt: "Filter hosts")
        .overlay { emptyState }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let message = hosts.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !hosts.allTags.isEmpty {
                    Picker("Tag", selection: $hosts.tagFilter) {
                        Text("All Hosts").tag(String?.none)
                        Divider()
                        ForEach(hosts.allTags, id: \.self) { tag in
                            Text(tag).tag(String?.some(tag))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help("Show only hosts with this tag")
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem { newHostButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem { newHostButton }
            }
        }
        .sheet(item: $hosts.editor) { request in
            HostFormSheet(entry: request.entry) { draft, password in
                hosts.save(draft, id: request.entry?.id, password: password)
            }
        }
        .confirmationDialog(
            "Delete \(hosts.pendingDelete?.host.name ?? "host")?",
            isPresented: Binding(
                get: { hosts.pendingDelete != nil },
                set: { if !$0 { hosts.pendingDelete = nil } }
            ),
            presenting: hosts.pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { hosts.delete(entry) }
        } message: { _ in
            Text("Removes it from 7 Term. ~/.ssh/config and open sessions aren't touched.")
        }
        .sheet(item: $hosts.folderNameRequest) { request in
            FolderNameSheet(request: request) { name in
                switch request {
                case .new(let parentId): hosts.createFolder(name: name, parentId: parentId)
                case .rename(let folder): hosts.renameFolder(folder, to: name)
                }
            }
        }
        .confirmationDialog(
            "Delete the folder \"\(hosts.pendingFolderDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { hosts.pendingFolderDelete != nil },
                set: { if !$0 { hosts.pendingFolderDelete = nil } }
            ),
            presenting: hosts.pendingFolderDelete
        ) { folder in
            Button("Delete Folder", role: .destructive) { hosts.deleteFolder(folder) }
        } message: { _ in
            Text("Its hosts and folders move up one level. Nothing else is removed.")
        }
    }

    /// Move to ▸ Top Level, then every folder indented by depth. A folder
    /// can't go into itself or its own subfolders, so those are left out.
    private func moveMenu(itemID: String) -> some View {
        Menu("Move to") {
            Button("Top Level") { hosts.move(itemID: itemID, toFolder: nil) }
            Divider()
            ForEach(moveTargets(for: itemID), id: \.folder.id) { target in
                Button(String(repeating: "\u{2003}", count: target.depth) + target.folder.name) {
                    hosts.move(itemID: itemID, toFolder: target.folder.id)
                }
            }
        }
    }

    private func moveTargets(for itemID: String) -> [(folder: HostFolder, depth: Int)] {
        var targets: [(folder: HostFolder, depth: Int)] = []
        // Flattened is depth-first, so a folder's subtree is the run of
        // deeper rows right after it.
        var skippingBelow: Int?
        for target in HostTree.flattened(folders: hosts.folders) {
            if let depth = skippingBelow {
                if target.depth > depth { continue }
                skippingBelow = nil
            }
            if target.folder.id == itemID {
                skippingBelow = target.depth
                continue
            }
            targets.append(target)
        }
        return targets
    }

    private var newHostButton: some View {
        Button {
            hosts.editor = .new
        } label: {
            Label("New Host", systemImage: "plus")
        }
        .help("New host (⌘N)")
    }

    @ViewBuilder private var emptyState: some View {
        if hosts.entries.isEmpty && hosts.folders.isEmpty {
            ContentUnavailableView {
                Label("No Saved Hosts", systemImage: "server.rack")
            } description: {
                Text("Add one, or import your ~/.ssh/config aliases.")
            } actions: {
                VStack(spacing: 8) {
                    Button("New Host…") { hosts.editor = .new }
                    Button("Import from ssh_config…") { hosts.presentImport() }
                    Button("Import from a Spreadsheet or App…") { hosts.isSpreadsheetImportPresented = true }
                }
            }
        } else if hosts.tree.isEmpty && !hosts.entries.isEmpty {
            ContentUnavailableView.search(text: hosts.query)
        }
    }

}

/// One level of the tree; folders recurse into their children.
private struct HostTreeRows: View {
    @Environment(HostDirectory.self) private var hosts
    @Environment(SessionStore.self) private var sessions
    let nodes: [HostTreeNode]

    var body: some View {
        ForEach(nodes) { node in
            switch node {
            case .folder(let folder, let children):
                DisclosureGroup(isExpanded: expansion(of: folder.id)) {
                    HostTreeRows(nodes: children)
                } label: {
                    FolderRow(folder: folder)
                }
            case .host(let entry):
                HostRow(
                    entry: entry,
                    connect: { sessions.open(entry, kind: .ssh) },
                    openSFTP: { sessions.open(entry, kind: .files) },
                    edit: { hosts.editor = .edit(entry) }
                )
                .draggable(entry.id)
                // Dropping on a host means "next to it": into its folder.
                .dropDestination(for: String.self) { itemIDs, _ in
                    for id in itemIDs where id != entry.id {
                        hosts.move(itemID: id, toFolder: entry.host.folderId)
                    }
                    return !itemIDs.isEmpty
                }
            }
        }
    }

    /// Stored on the directory, so it survives relaunch. While filtering
    /// every folder is open and clicking the triangle changes nothing.
    private func expansion(of folderID: String) -> Binding<Bool> {
        Binding {
            hosts.isExpanded(folderID)
        } set: { isOpen in
            guard !hosts.isFiltering else { return }
            if isOpen {
                hosts.expandedFolderIDs.insert(folderID)
            } else {
                hosts.expandedFolderIDs.remove(folderID)
            }
        }
    }
}

/// A folder's row: icon and name. Drop a host or folder on it to move it in.
private struct FolderRow: View {
    @Environment(\.chrome) private var chrome
    @Environment(HostDirectory.self) private var hosts
    let folder: HostFolder
    @State private var isTargeted = false

    var body: some View {
        Label {
            Text(folder.name)
                .font(Brand.mono(13, weight: .medium))
                .lineLimit(1)
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(chrome.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isTargeted ? chrome.accent.opacity(0.2) : .clear)
        )
        .draggable(folder.id)
        // Dropping a folder on itself or its own subfolder is refused by
        // the library, and the reason shows under the list.
        .dropDestination(for: String.self) { itemIDs, _ in
            for id in itemIDs { hosts.move(itemID: id, toFolder: folder.id) }
            return !itemIDs.isEmpty
        } isTargeted: { isTargeted = $0 }
    }
}

private struct HostRow: View {
    @Environment(\.chrome) private var chrome
    let entry: HostEntry
    let connect: () -> Void
    let openSFTP: () -> Void
    let edit: () -> Void
    @State private var isHovering = false

    /// user@host:port for ssh; port and settings for serial.
    private var subtitle: String {
        guard entry.host.kind == .serial else { return entry.host.target.displayName }
        let port = (entry.host.hostname as NSString).lastPathComponent.replacingOccurrences(of: "cu.", with: "")
        return "\(port) · \(entry.host.serial?.settings.summary ?? "9600 8N1")"
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.host.name)
                    .font(Brand.mono(13, weight: .medium))
                    .lineLimit(1)
                if subtitle != entry.host.name {
                    Text(subtitle)
                        .font(Brand.mono(10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !entry.tags.isEmpty {
                    TagChips(tags: entry.tags)
                }
            }
            Spacer(minLength: 4)
            // Shown only on hover, so they don't take room from the name otherwise.
            if isHovering {
                HStack(spacing: 8) {
                    if entry.host.kind == .serial {
                        Button("OPEN", action: connect)
                            .help("Open the serial console (Return or double-click)")
                            .accessibilityLabel("Open the serial console \(entry.host.name)")
                    } else {
                        Button("SSH", action: connect)
                            .help("Connect with ssh (Return or double-click)")
                            .accessibilityLabel("Connect to \(entry.host.name) with ssh")
                        Button("SFTP", action: openSFTP)
                            .help("Browse files over SFTP (⌥⌘↩)")
                            .accessibilityLabel("Browse files on \(entry.host.name)")
                    }
                }
                .buttonStyle(.borderless)
                .font(Brand.mono(10.5, weight: .bold))
                .foregroundStyle(chrome.accent)
            }
            // Always visible, so settings don't depend on knowing to right-click.
            Button(action: edit) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isHovering ? chrome.accent : Color.secondary.opacity(0.6))
            .help("Edit host settings (⌘E)")
            .accessibilityLabel("Edit \(entry.host.name)")
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// A host's tags as small labels; more than three collapse into "+n".
private struct TagChips: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                chip(tag)
            }
            if tags.count > 3 {
                chip("+\(tags.count - 3)")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tags: " + tags.joined(separator: ", "))
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(Brand.mono(9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08)))
    }
}
