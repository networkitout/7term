import SwiftUI
import SevenTermCore

/// The one window: saved hosts on the left, tabs and the selected session's
/// terminal on the right.
struct MainView: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(HostDirectory.self) private var hosts
    @Environment(Appearance.self) private var appearance
    @Environment(WhatsNewCenter.self) private var whatsNew

    var body: some View {
        @Bindable var hosts = hosts
        @Bindable var whatsNew = whatsNew
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
        .sheet(item: $whatsNew.shown) { presentation in
            WhatsNewSheet(presentation: presentation) { whatsNew.dismiss() }
        }
        .task {
            // Before the first-run offer, which marks the app as used.
            let usedBefore = hosts.hasBeenUsedBefore
            hosts.offerImportIfFirstRun()
            // One launch sheet at a time: the import offer wins.
            if !hosts.isImportPresented { whatsNew.checkAtLaunch(isExistingUser: usedBefore) }
        }
        // Outermost, so every view and sheet in the window gets it.
        .environment(\.chrome, chrome)
    }
}

/// Tab strip over one session, or two side by side.
private struct SessionArea: View {
    @Environment(SessionStore.self) private var store
    @Environment(Appearance.self) private var appearance
    /// Where the divider sits, as a share of the width. Back to the middle
    /// each time the window splits.
    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            if !store.sessions.isEmpty {
                TabStrip()
                Divider()
            }
            ZStack {
                appearance.palette.background.swiftUIColor
                if let left = store.session(id: store.layout.left) {
                    if let right = store.session(id: store.layout.right) {
                        SplitPanes(fraction: $splitFraction) {
                            SessionPane(session: left)
                        } right: {
                            SessionPane(session: right)
                        }
                    } else {
                        SessionPane(session: left)
                    }
                } else {
                    EmptyState()
                }
            }
        }
        .onChange(of: store.layout.isSplit) { _, isSplit in
            if isSplit { splitFraction = 0.5 }
        }
        // One rule for the keyboard: the current tab's terminal has it,
        // whichever way the current tab changed (a click, a tab, a drop).
        .onChange(of: store.selectedID) { _, _ in
            guard let session = store.selected, session.files == nil else { return }
            let terminal = session.terminalView
            DispatchQueue.main.async {
                if terminal.window?.firstResponder !== terminal { terminal.window?.makeFirstResponder(terminal) }
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

/// One side of the window: a terminal or a file browser. A click anywhere in
/// it focuses that side when the window is split.
private struct SessionPane: View {
    @Environment(SessionStore.self) private var store
    let session: TerminalSession

    var body: some View {
        Group {
            if let files = session.files {
                FileBrowserView(browser: files)
            } else {
                TerminalHost(session: session, takesFocus: session.id == store.selectedID)
            }
        }
        .id(session.id)
        .background(PaneClickMonitor { store.select(session) })
    }
}

/// Two panes and a divider you can drag. Each side keeps at least 280 points
/// when the window has room for that; in a narrower window both shrink.
private struct SplitPanes<Left: View, Right: View>: View {
    @Binding var fraction: CGFloat
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right
    @State private var dragStartWidth: CGFloat?

    private static var minimumWidth: CGFloat { 280 }

    var body: some View {
        GeometryReader { geometry in
            let total = max(geometry.size.width - 1, 0)
            let minimum = min(Self.minimumWidth, total / 2)
            let leftWidth = min(max(total * fraction, minimum), total - minimum)
            HStack(spacing: 0) {
                left.frame(width: leftWidth)
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1)
                    .overlay {
                        // A wider grab area than the line itself.
                        Color.clear
                            .frame(width: 9)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { value in
                                        let start = dragStartWidth ?? leftWidth
                                        dragStartWidth = start
                                        let width = min(max(start + value.translation.width, minimum), total - minimum)
                                        if total > 0 { fraction = width / total }
                                    }
                                    .onEnded { _ in dragStartWidth = nil }
                            )
                    }
                    .zIndex(1)
                right.frame(maxWidth: .infinity)
            }
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
