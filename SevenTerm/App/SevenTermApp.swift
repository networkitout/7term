import SwiftUI

@main
struct SevenTermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appearance: Appearance
    @State private var sessions: SessionStore
    @State private var hosts: HostDirectory

    init() {
        // Before anything reads settings or the host library.
        LegacyMigration.run()
        let appearance = Appearance()
        _appearance = State(initialValue: appearance)
        _sessions = State(initialValue: SessionStore(appearance: appearance))
        _hosts = State(initialValue: HostDirectory())
    }

    var body: some Scene {
        Window("7 Term", id: "main") {
            MainView()
                .environment(sessions)
                .environment(hosts)
                .environment(appearance)
                .frame(minWidth: 820, minHeight: 440)
                .onAppear {
                    appDelegate.store = sessions
                    appDelegate.appearance = appearance
                }
        }
        // The wordmark replaces the plain window title, as in 6 Bits.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Host…") { hosts.editor = .new }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Quick Connect…") { sessions.isQuickConnectPresented = true }
                    .keyboardShortcut("t", modifiers: .command)
                Divider()
                Button("Import from ~/.ssh/config…") { hosts.presentImport() }
            }
            // Replaces the default Close item so ⌘W closes a tab, not the window.
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { sessions.closeSelectedOrWindow() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            // View menu: global text size and theme, like ⌘+ in Safari or the Claude app.
            CommandGroup(before: .toolbar) {
                Button("Make Text Bigger") { appearance.makeBigger() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!appearance.canMakeBigger)
                Button("Make Text Smaller") { appearance.makeSmaller() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!appearance.canMakeSmaller)
                Button("Actual Size") { appearance.resetSize() }
                    .keyboardShortcut("0", modifiers: .command)
                Picker("Theme", selection: Binding(
                    get: { appearance.paletteID },
                    set: { appearance.paletteID = $0 }
                )) {
                    ForEach(appearance.palettes) { palette in
                        Text(palette.name).tag(palette.id)
                    }
                }
                Divider()
            }
            CommandMenu("Host") {
                Button("Connect with SSH") {
                    if let entry = hosts.selectedEntry { sessions.open(entry, kind: .ssh) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(hosts.selectedEntry == nil)
                Button("Open SFTP") {
                    if let entry = hosts.selectedEntry { sessions.open(entry, kind: .sftp) }
                }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(hosts.selectedEntry == nil)
                ForEach(FileTransferApp.installed) { app in
                    Button("Open in \(app.name)") {
                        if let entry = hosts.selectedEntry {
                            Task { await app.open(entry.host.target) }
                        }
                    }
                    .disabled(hosts.selectedEntry == nil)
                }
                Divider()
                Button("Edit Host…") {
                    if let entry = hosts.selectedEntry { hosts.editor = .edit(entry) }
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(hosts.selectedEntry == nil)
                Button("Duplicate Host") {
                    if let entry = hosts.selectedEntry { hosts.duplicate(entry) }
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(hosts.selectedEntry == nil)
                Button("Copy Hostname") {
                    if let entry = hosts.selectedEntry { hosts.copyHostname(entry) }
                }
                .disabled(hosts.selectedEntry == nil)
                Divider()
                Button("Delete Host…") { hosts.pendingDelete = hosts.selectedEntry }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(hosts.selectedEntry == nil)
            }
            CommandMenu("Session") {
                Button("Reconnect") { sessions.reconnectSelected() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!sessions.canReconnectSelected)
                Divider()
                Button(sessions.selected?.isLogging == true ? "Stop Logging" : "Start Logging") {
                    sessions.toggleLoggingSelected()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!sessions.canToggleLoggingSelected)
                Button("Show Log in Finder") { LogLocation.reveal(sessions.selected?.lastLogURL) }
                Divider()
                Button("Show Next Tab") { sessions.selectNext() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(sessions.sessions.count < 2)
                Button("Show Previous Tab") { sessions.selectPrevious() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(sessions.sessions.count < 2)
            }
        }

        Settings {
            AppearanceSettings()
                .environment(appearance)
        }
    }
}
