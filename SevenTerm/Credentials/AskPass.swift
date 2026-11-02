import AppKit
import Foundation

/// 7 Term's own binary doubles as ssh's password helper (SSH_ASKPASS).
///
/// For a host set to "Password (Keychain)", 7 Term starts ssh with
/// SSH_ASKPASS pointing at its own executable, SSH_ASKPASS_REQUIRE=force,
/// and the host's id in SEVENTERM_HOST_ID. ssh then runs a second copy of
/// 7 Term with the prompt text as its argument; that copy never opens a
/// window, answers on stdout, and exits:
/// - "…password:" → Touch ID, then the Keychain password for that host
/// - a yes/no question (an unknown host key) → a native dialog showing ssh's
///   exact text; only "Continue" answers yes
/// - anything else (a key passphrase, a one-time code) → a native dialog with
///   a secure text field
/// Cancelling any of them exits with status 1, so ssh stops.
/// Nothing is typed into the terminal, so a remote host can't fake a prompt
/// and collect the password.
enum AskPass {
    static let modeKey = "SEVENTERM_ASKPASS"
    static let hostKey = "SEVENTERM_HOST_ID"
    static let hostNameKey = "SEVENTERM_HOST_NAME"

    /// Environment entries that turn on askpass for one ssh or sftp process.
    static func environment(hostID: String, hostName: String) -> [String] {
        guard let executable = Bundle.main.executablePath else { return [] }
        return [
            "SSH_ASKPASS=\(executable)",
            "SSH_ASKPASS_REQUIRE=force",
            "\(modeKey)=1",
            "\(hostKey)=\(hostID)",
            "\(hostNameKey)=\(hostName)",
        ]
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[modeKey] == "1"
    }

    /// Runs the helper and returns the process exit status.
    @MainActor
    static func run(arguments: [String]) -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let prompt = arguments.dropFirst().joined(separator: " ")
        let hostID = environment[hostKey] ?? ""
        let hostName = environment[hostNameKey] ?? "this host"
        let lowered = prompt.lowercased()

        if lowered.hasSuffix("password:") || lowered.hasSuffix("password: ") {
            guard !hostID.isEmpty,
                  let password = PasswordVault.read(hostID: hostID, reason: "connect to \(hostName)")
            else { return 1 }
            return answer(password)
        }

        if lowered.contains("(yes/no") {
            return confirm(prompt, hostName: hostName) ? answer("yes") : 1
        }

        guard let typed = ask(prompt, hostName: hostName) else { return 1 }
        return answer(typed)
    }

    private static func answer(_ text: String) -> Int32 {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        return 0
    }

    @MainActor
    private static func prepareApp() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate()
    }

    @MainActor
    private static func confirm(_ prompt: String, hostName: String) -> Bool {
        prepareApp()
        let alert = NSAlert()
        alert.messageText = "ssh asks about \(hostName)"
        alert.informativeText = prompt
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Continue")
        return alert.runModal() == .alertSecondButtonReturn
    }

    @MainActor
    private static func ask(_ prompt: String, hostName: String) -> String? {
        prepareApp()
        let alert = NSAlert()
        alert.messageText = "ssh needs input for \(hostName)"
        alert.informativeText = prompt
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
