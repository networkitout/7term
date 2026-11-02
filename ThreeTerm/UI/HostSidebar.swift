import SwiftUI
import ThreeTermCore

/// Saved hosts, grouped by tag, with type-to-filter.
/// Double-click or Return connects; right-click for everything else.
struct HostSidebar: View {
    @Environment(HostDirectory.self) private var hosts
    @Environment(SessionStore.self) private var sessions

    var body: some View {
        @Bindable var hosts = hosts

        List(selection: $hosts.selectedRowID) {
            ForEach(hosts.sections) { section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        HostRow(entry: entry) { connect(entry) }
                            .tag(HostDirectory.rowID(section: section, entry: entry))
                    }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { rowIDs in
            if let entry = hosts.entry(forRow: rowIDs.first) {
                Button("Connect") { connect(entry) }
                Divider()
                Button("Edit…") { hosts.editor = .edit(entry) }
                Button("Duplicate") { hosts.duplicate(entry) }
                Button("Copy Hostname") { hosts.copyHostname(entry) }
                Divider()
                Button("Delete…", role: .destructive) { hosts.pendingDelete = entry }
            } else {
                Button("New Host…") { hosts.editor = .new }
            }
        } primaryAction: { rowIDs in
            if let entry = hosts.entry(forRow: rowIDs.first) { connect(entry) }
        }
        .onDeleteCommand { hosts.pendingDelete = hosts.selectedEntry }
        .searchable(text: $hosts.query, placement: .sidebar, prompt: "Filter hosts")
        .overlay { emptyState }
        .safeAreaInset(edge: .bottom) {
            if let message = hosts.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    hosts.editor = .new
                } label: {
                    Label("New Host", systemImage: "plus")
                }
                .help("New host (⌘N)")
            }
        }
        .sheet(item: $hosts.editor) { request in
            HostFormSheet(entry: request.entry) { draft in
                hosts.save(draft, id: request.entry?.id)
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
            Text("Removes it from 3 Term. ~/.ssh/config and open sessions aren't touched.")
        }
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
        } else if hosts.sections.isEmpty {
            ContentUnavailableView.search(text: hosts.query)
        }
    }

    private func connect(_ entry: HostEntry) {
        sessions.open(entry.host.target, name: entry.host.name, logByDefault: entry.host.logByDefault)
    }
}

private struct HostRow: View {
    let entry: HostEntry
    let connect: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.host.name)
                    .lineLimit(1)
                if entry.host.target.displayName != entry.host.name {
                    Text(entry.host.target.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Button("SSH", action: connect)
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .opacity(isHovering ? 1 : 0)
                .help("Connect with ssh (Return or double-click)")
                .accessibilityLabel("Connect to \(entry.host.name)")
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
