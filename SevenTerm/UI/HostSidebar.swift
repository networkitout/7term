import SwiftUI
import SevenTermCore

/// Saved hosts, each listed once, with type-to-filter and a tag filter.
/// Double-click or Return opens ssh; the row's SFTP button, the right-click
/// menu and the Host menu open sftp or a file transfer app.
struct HostSidebar: View {
    @Environment(HostDirectory.self) private var hosts
    @Environment(SessionStore.self) private var sessions

    var body: some View {
        @Bindable var hosts = hosts

        List(hosts.visibleEntries, selection: $hosts.selectedHostID) { entry in
            HostRow(
                entry: entry,
                connect: { sessions.open(entry, kind: .ssh) },
                openSFTP: { sessions.open(entry, kind: .sftp) }
            )
        }
        .scrollContentBackground(.hidden)
        .background(Brand.panel)
        .contextMenu(forSelectionType: String.self) { hostIDs in
            if let entry = hostIDs.first.flatMap(hosts.entry(id:)) {
                Button("Connect with SSH") { sessions.open(entry, kind: .ssh) }
                Button("Open SFTP") { sessions.open(entry, kind: .sftp) }
                ForEach(FileTransferApp.installed) { app in
                    Button("Open in \(app.name)") {
                        Task { await app.open(entry.host.target) }
                    }
                }
                Divider()
                Button("Edit…") { hosts.editor = .edit(entry) }
                Button("Duplicate") { hosts.duplicate(entry) }
                Button("Copy Hostname") { hosts.copyHostname(entry) }
                Divider()
                Button("Delete…", role: .destructive) { hosts.pendingDelete = entry }
            } else {
                Button("New Host…") { hosts.editor = .new }
            }
        } primaryAction: { hostIDs in
            if let entry = hostIDs.first.flatMap(hosts.entry(id:)) { sessions.open(entry, kind: .ssh) }
        }
        .onDeleteCommand { hosts.pendingDelete = hosts.selectedEntry }
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
        if hosts.entries.isEmpty {
            ContentUnavailableView {
                Label("No Saved Hosts", systemImage: "server.rack")
            } description: {
                Text("Add one, or import your ~/.ssh/config aliases.")
            } actions: {
                VStack(spacing: 8) {
                    Button("New Host…") { hosts.editor = .new }
                    Button("Import from ssh_config…") { hosts.presentImport() }
                }
            }
        } else if hosts.visibleEntries.isEmpty {
            ContentUnavailableView.search(text: hosts.query)
        }
    }

}

private struct HostRow: View {
    let entry: HostEntry
    let connect: () -> Void
    let openSFTP: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.host.name)
                    .font(Brand.mono(13, weight: .medium))
                    .lineLimit(1)
                if entry.host.target.displayName != entry.host.name {
                    Text(entry.host.target.displayName)
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
            HStack(spacing: 8) {
                Button("SSH", action: connect)
                    .help("Connect with ssh (Return or double-click)")
                    .accessibilityLabel("Connect to \(entry.host.name) with ssh")
                Button("SFTP", action: openSFTP)
                    .help("Open an sftp session (⌥⌘↩)")
                    .accessibilityLabel("Open sftp to \(entry.host.name)")
            }
            .buttonStyle(.borderless)
            .font(Brand.mono(10.5, weight: .bold))
            .foregroundStyle(Brand.red)
            .opacity(isHovering ? 1 : 0)
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
