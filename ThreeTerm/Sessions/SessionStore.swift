import AppKit
import Observation
import ThreeTermCore

/// The open tabs, in order, and which one is showing.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [TerminalSession] = []
    var selectedID: TerminalSession.ID?
    var isQuickConnectPresented = false

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

    func toggleLoggingSelected() {
        selected?.toggleLogging()
    }

    /// Opens a new tab. `name` is a saved host's name; quick connections pass nil.
    func open(_ target: SSHTarget, name: String? = nil, logByDefault: Bool = false) {
        let session = TerminalSession(target: target, name: name, logByDefault: logByDefault)
        sessions.append(session)
        selectedID = session.id
        session.start()
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
