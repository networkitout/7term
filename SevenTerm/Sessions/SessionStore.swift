import AppKit
import Observation
import SevenTermCore

/// The open tabs, in order, and which one is showing.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [TerminalSession] = []
    var selectedID: TerminalSession.ID?
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
        sessions.first { $0.id == selectedID }
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
        sessions.append(session)
        selectedID = session.id
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
        selectedID = session.id
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
        if selectedID == session.id {
            selectedID = sessions.isEmpty ? nil : sessions[min(index, sessions.count - 1)].id
        }
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

    private func step(by offset: Int) {
        guard !sessions.isEmpty,
              let current = sessions.firstIndex(where: { $0.id == selectedID })
        else { return }
        let next = (current + offset + sessions.count) % sessions.count
        selectedID = sessions[next].id
    }
}
