import SwiftUI

@main
struct ThreeTermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessions = SessionStore()
    @State private var hosts = HostDirectory()

    var body: some Scene {
        Window("3 Term", id: "main") {
            MainView()
                .environment(sessions)
                .environment(hosts)
                .frame(minWidth: 820, minHeight: 440)
                .onAppear { appDelegate.store = sessions }
        }
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
            CommandMenu("Session") {
                Button("Reconnect") { sessions.reconnectSelected() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!sessions.canReconnectSelected)
                Divider()
                Button("Show Next Tab") { sessions.selectNext() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(sessions.sessions.count < 2)
                Button("Show Previous Tab") { sessions.selectPrevious() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(sessions.sessions.count < 2)
            }
        }
    }
}
