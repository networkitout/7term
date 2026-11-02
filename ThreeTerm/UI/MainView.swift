import SwiftUI
import ThreeTermCore

/// The one window: saved hosts on the left, tabs and the selected session's
/// terminal on the right.
struct MainView: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(HostDirectory.self) private var hosts

    var body: some View {
        @Bindable var hosts = hosts

        NavigationSplitView {
            HostSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            SessionArea()
        }
        .sheet(isPresented: $hosts.isImportPresented) {
            ImportSheet(
                aliases: hosts.importCandidates,
                savedHostnames: hosts.savedHostnames,
                onImport: { aliases, tag in hosts.finishImport(aliases, tag: tag) },
                onSkip: { hosts.skipImport() }
            )
        }
        .task { hosts.offerImportIfFirstRun() }
    }
}

/// Tab strip over the selected terminal.
private struct SessionArea: View {
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
            Text("Double-click a host, or press ⌘T for a quick connection.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
            Button("Quick Connect…") { store.isQuickConnectPresented = true }
        }
        .padding()
    }
}
