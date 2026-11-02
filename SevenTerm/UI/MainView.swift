import SwiftUI
import SevenTermCore

/// The one window: saved hosts on the left, tabs and the selected session's
/// terminal on the right.
struct MainView: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(HostDirectory.self) private var hosts
    @Environment(Appearance.self) private var appearance

    var body: some View {
        @Bindable var hosts = hosts
        let chrome = Chrome.forPalette(id: appearance.paletteID)

        NavigationSplitView {
            HostSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            SessionArea()
        }
        .toolbar {
            if #available(macOS 26.0, *) {
                // No glass capsule: the wordmark sits on the bar, as in 6 Bits.
                ToolbarItem(placement: .navigation) {
                    Wordmark().padding(.horizontal, 6)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .navigation) {
                    Wordmark().padding(.horizontal, 6)
                }
            }
        }
        .toolbarBackground(chrome.background, for: .windowToolbar)
        .background(chrome.background)
        .tint(chrome.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $hosts.isImportPresented) {
            ImportSheet(
                aliases: hosts.importCandidates,
                savedHostnames: hosts.savedHostnames,
                onImport: { aliases, tag in hosts.finishImport(aliases, tag: tag) },
                onSkip: { hosts.skipImport() }
            )
        }
        .sheet(isPresented: $hosts.isSpreadsheetImportPresented) {
            SpreadsheetImportSheet()
        }
        .task { hosts.offerImportIfFirstRun() }
        // Outermost, so every view and sheet in the window gets it.
        .environment(\.chrome, chrome)
    }
}

/// Tab strip over the selected terminal.
private struct SessionArea: View {
    @Environment(SessionStore.self) private var store
    @Environment(Appearance.self) private var appearance

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if !store.sessions.isEmpty {
                TabStrip()
                Divider()
            }
            ZStack {
                appearance.palette.background.swiftUIColor
                if let session = store.selected, let files = session.files {
                    FileBrowserView(browser: files)
                        .id(session.id)
                } else if let session = store.selected {
                    TerminalHost(session: session)
                        .id(session.id)
                } else {
                    EmptyState()
                }
            }
        }
        .sheet(isPresented: $store.isQuickConnectPresented) {
            QuickConnectSheet(
                connect: { target, kind in store.open(target, kind: kind) },
                openSerial: { path, settings in store.openSerial(path: path, settings: settings) }
            )
        }
    }
}

private struct EmptyState: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(spacing: 22) {
            PixelGlyph(rows: PixelGlyph.seven, dot: 9)
            PromptLine(text: "double-click a host")
            Button("Quick Connect…") { store.isQuickConnectPresented = true }
                .font(Brand.mono(12))
                .help("Connect to any host (⌘T)")
        }
        .padding()
    }
}
