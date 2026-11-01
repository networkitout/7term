import SwiftUI

@main
struct ThreeTermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SessionStore()

    var body: some Scene {
        Window("3 Term", id: "main") {
            MainView()
                .environment(store)
                .frame(minWidth: 640, minHeight: 400)
                .onAppear { appDelegate.store = store }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") { store.isQuickConnectPresented = true }
                    .keyboardShortcut("t", modifiers: .command)
            }
            // Replaces the default Close item so ⌘W closes a tab, not the window.
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { store.closeSelectedOrWindow() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Session") {
                Button("Reconnect") { store.reconnectSelected() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!store.canReconnectSelected)
                Divider()
                Button("Show Next Tab") { store.selectNext() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(store.sessions.count < 2)
                Button("Show Previous Tab") { store.selectPrevious() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(store.sessions.count < 2)
            }
        }
    }
}
