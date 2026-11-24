import AppKit
import SwiftTerm
import SwiftUI

/// Shows a session's terminal view. The view itself lives on the session, so
/// switching tabs moves it between containers instead of recreating it, and
/// scrollback survives.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession
    /// Only the current tab's terminal takes the keyboard when it appears;
    /// with two tabs showing, the other side's must not steal it.
    var takesFocus = true

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
        // After any sheet that opened this tab has finished closing, which
        // would otherwise hand focus back to the host list.
        if takesFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
