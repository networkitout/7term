import AppKit
import Observation
import SevenTermCore

/// The open tabs, in order, and which one or two are showing.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [TerminalSession] = []
    /// Which tabs show: the focused one, and the one beside it when split.
    private(set) var layout = TabLayout<TerminalSession.ID>()
    /// The focused tab: the one commands act on and new tabs replace.
    var selectedID: TerminalSession.ID? { layout.focused }
    var isQuickConnectPresented = false

    @ObservationIgnored let appearance: Appearance

    init(appearance: Appearance) {
        self.appearance = appearance
        appearance.onChange = { [weak self] in self?.applyAppearance() }
    }

    /// Restyles every open tab after a theme, font or size change.
    private func applyAppearance() {
        for session in sessions {
            appearance.apply(to: session.terminalView)
        }
    }

    var selected: TerminalSession? {
        session(id: layout.focused)
    }

    /// The other visible tab when the window is split.
    var beside: TerminalSession? {
        session(id: layout.beside)
    }

    func session(id: TerminalSession.ID?) -> TerminalSession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    /// A tab clicked in the tab bar, or a pane clicked: the other visible tab
    /// takes the focus; a hidden tab replaces the focused side.
    func select(_ session: TerminalSession) {
        layout.select(session.id)
    }

    /// ⇧⌘] and ⇧⌘[ have somewhere to go: another tab besides the one on the
    /// other side.
    var canStep: Bool {
        sessions.count - (layout.isSplit ? 1 : 0) >= 2
    }

    /// A drag held over a hidden tab: in one pane it replaces the tab, as a
    /// click does; when split it opens beside, so the pane the drag started
    /// in stays put.
    func openForDrag(_ session: TerminalSession) {
        if layout.isSplit, session.id != layout.focused, session.id != layout.beside {
            layout.showBeside(session.id)
        } else {
            layout.select(session.id)
        }
    }

    /// Right-click a tab ▸ Show Beside.
    func showBeside(_ session: TerminalSession) {
        layout.showBeside(session.id)
    }

    /// View ▸ Show Side by Side / Show One Tab (⌥⌘S).
    var canToggleSideBySide: Bool {
        layout.canToggleSideBySide(tabs: sessions.map(\.id))
    }

    func toggleSideBySide() {
        layout.toggleSideBySide(tabs: sessions.map(\.id))
    }

    var runningCount: Int {
        sessions.filter { $0.state == .running }.count
    }

    var canReconnectSelected: Bool {
        guard let selected else { return false }
        return selected.state != .running
    }

    var canToggleLoggingSelected: Bool {
        selected?.state == .running
    }

    /// Opens one tab for each host, in order.
    func openAll(_ entries: [HostEntry]) {
        for entry in entries { open(entry, kind: .ssh) }
    }

    /// Opens a saved host as an ssh or sftp tab, or a serial entry as a
    /// serial tab whatever `kind` asks for.
    func open(_ entry: HostEntry, kind: TerminalSession.Kind) {
        if entry.host.kind == .serial {
            let details = entry.host.serial ?? SerialHostDetails()
            openSerial(
                path: SerialPortList.resolve(savedPath: entry.host.hostname, details: details),
                settings: details.settings, name: entry.host.name, logByDefault: entry.host.logByDefault
            )
            return
        }
        let keychainHost = entry.host.authMethod == .password ? (id: entry.id, name: entry.host.name) : nil
        open(
            entry.host.target, kind: kind, name: entry.host.name,
            logByDefault: entry.host.logByDefault, keychainHost: keychainHost
        )
    }

    /// Search works in terminal tabs; the file browser has no scrollback.
    var canFind: Bool {
        guard let selected else { return false }
        return selected.files == nil
    }

    /// Sends a find action (show the bar, next, previous) to the current
    /// terminal. SwiftTerm draws the find bar and does the searching.
    func find(_ action: NSTextFinder.Action) {
        guard let selected, selected.files == nil else { return }
        let item = NSMenuItem()
        item.tag = action.rawValue
        selected.terminalView.performTextFinderAction(item)
    }

    func toggleLoggingSelected() {
        selected?.toggleLogging()
    }

    /// Opens a new tab. `name` is a saved host's name; quick connections pass nil.
    func open(
        _ target: SSHTarget,
        kind: TerminalSession.Kind = .ssh,
        name: String? = nil,
        logByDefault: Bool = false,
        keychainHost: (id: String, name: String)? = nil
    ) {
        let session = TerminalSession(
            kind: kind, target: target, name: name, logByDefault: logByDefault,
            keychainHost: keychainHost, appearance: appearance
        )
        session.remoteTarget = { [weak self] browserID in
            self?.sessions.first { $0.files?.id == browserID }?.target
        }
        // A drop types into a tab, so that tab becomes the current one.
        session.didAcceptDrop = { [weak self, weak session] in
            if let session { self?.select(session) }
        }
        sessions.append(session)
        layout.select(session.id)
        session.start()
    }

    /// Opens a serial console tab. `name` is a saved host's name.
    func openSerial(path: String, settings: SerialSettings, name: String? = nil, logByDefault: Bool = false) {
        let shortName = (path as NSString).lastPathComponent.replacingOccurrences(of: "cu.", with: "")
        let session = TerminalSession(
            kind: .serial, target: SSHTarget(host: shortName), name: name,
            logByDefault: logByDefault, serial: (path, settings), appearance: appearance
        )
        sessions.append(session)
        layout.select(session.id)
        session.start()
    }

    var canSendBreakSelected: Bool { selected?.canSendBreak ?? false }

    func sendBreakSelected() {
        selected?.sendBreak()
    }

    func close(_ session: TerminalSession) {
        session.stop()
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)
        layout.closed(session.id, remaining: sessions.map(\.id), index: index)
    }

    /// ⌘W: closes the current tab, or the window when no tabs are open.
    func closeSelectedOrWindow() {
        if let selected {
            close(selected)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    func closeAll() {
        sessions.forEach { $0.stop() }
    }

    func reconnectSelected() {
        selected?.restart()
    }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    /// The focused side steps through the tabs, skipping the other side's.
    private func step(by offset: Int) {
        layout.step(by: offset, tabs: sessions.map(\.id))
    }
}
