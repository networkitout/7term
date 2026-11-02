import AppKit
import SwiftTerm
import SwiftUI

/// Shows a session's terminal view. The view itself lives on the session, so
/// switching tabs moves it between containers instead of recreating it, and
/// scrollback survives.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let terminal = session.terminalView
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        Task { @MainActor in
            terminal.window?.makeFirstResponder(terminal)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
