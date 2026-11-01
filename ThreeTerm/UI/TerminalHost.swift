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
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        Task { @MainActor in
            terminal.window?.makeFirstResponder(terminal)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
