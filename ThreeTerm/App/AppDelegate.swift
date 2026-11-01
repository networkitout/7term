import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: SessionStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Asks once before quitting with live sessions, then closes every one.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.runningCount > 0 else { return .terminateNow }

        let count = store.runningCount
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Quit with 1 open session?" : "Quit with \(count) open sessions?"
        alert.informativeText = "Each SSH connection will be closed."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        store.closeAll()
        return .terminateNow
    }
}
