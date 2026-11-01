import SwiftUI
import ThreeTermCore

/// The one window: a tab strip over the selected session's terminal.
/// Milestone 2 adds the host list as a sidebar.
struct MainView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if !store.sessions.isEmpty {
                TabStrip()
                Divider()
            }
            ZStack {
                Color(nsColor: TerminalTheme.threeTerm.background)
                if let session = store.selected {
                    TerminalHost(session: session)
                        .id(session.id)
                } else {
                    EmptyState()
                }
            }
        }
        .tint(Brand.red)
        .sheet(isPresented: $store.isQuickConnectPresented) {
            QuickConnectSheet { target in store.open(target) }
        }
    }
}

private struct EmptyState: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            Text("3")
                .font(.system(size: 64, weight: .heavy, design: .monospaced))
                .foregroundStyle(Brand.red)
                .accessibilityHidden(true)
            Text("No open sessions")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            Button("New Connection") { store.isQuickConnectPresented = true }
                .keyboardShortcut(.defaultAction)
            Text("⌘T")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
