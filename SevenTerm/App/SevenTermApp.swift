import AppKit
import SwiftUI

/// The process entry point. When ssh runs this binary as its password
/// helper (see AskPass), answer and exit without starting the app.
@main
enum Launcher {
    @MainActor
    static func main() {
        if AskPass.isRequested {
            exit(AskPass.run(arguments: CommandLine.arguments))
        }
        SevenTermApp.main()
    }
}

struct SevenTermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appearance: Appearance
    @State private var sessions: SessionStore
    @State private var hosts: HostDirectory
    @State private var backup: BackupManager

    init() {
        // Before anything reads settings or the host library.
        LegacyMigration.run()
        let appearance = Appearance()
        _appearance = State(initialValue: appearance)
        _sessions = State(initialValue: SessionStore(appearance: appearance))
        let hosts = HostDirectory()
        _hosts = State(initialValue: hosts)

        let backup = BackupManager(hosts: hosts, appearance: appearance)
        _backup = State(initialValue: backup)
        hosts.onChange = { [weak backup] in backup?.scheduleBackup() }
        appearance.onSettingsChange = { [weak backup] in backup?.scheduleBackup() }
        backup.scheduleBackup()
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
                    appearance.updateDockIcon()
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
                Button("Import from Spreadsheet…") { hosts.isSpreadsheetImportPresented = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Restore from Backup…") { backup.chooseAndRestore() }
            }
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
            // Edit ▸ Find: SwiftTerm's find bar over the current terminal tab.
            CommandGroup(after: .pasteboard) {
                Divider()
                Menu("Find") {
                    Button("Find…") { sessions.find(.showFindInterface) }
                        .keyboardShortcut("f", modifiers: .command)
                    Button("Find Next") { sessions.find(.nextMatch) }
                        .keyboardShortcut("g", modifiers: .command)
                    Button("Find Previous") { sessions.find(.previousMatch) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                    Button("Use Selection for Find") { sessions.find(.setSearchString) }
                }
                .disabled(!sessions.canFind)
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
                Button("Browse Files (SFTP)") {
                    if let entry = hosts.selectedEntry { sessions.open(entry, kind: .files) }
                }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(hosts.selectedEntry == nil)
                Button("SFTP Prompt") {
                    if let entry = hosts.selectedEntry { sessions.open(entry, kind: .sftp) }
                }
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

        Window("7 Term Help", id: "help") {
            HelpView()
                .environment(appearance)
        }
        .defaultSize(width: 900, height: 680)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            TabView {
                AppearanceSettings()
                    .tabItem { Label("Appearance", systemImage: "paintpalette") }
                BackupSettings()
                    .tabItem { Label("Backup", systemImage: "icloud") }
            }
            .environment(appearance)
            .environment(backup)
            .environment(\.chrome, Chrome.forPalette(id: appearance.paletteID))
            .tint(Chrome.forPalette(id: appearance.paletteID).accent)
        }
    }
}

/// Help ▸ 7 Term Help (⌘?). A view, so it can open the help window.
private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("7 Term Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
