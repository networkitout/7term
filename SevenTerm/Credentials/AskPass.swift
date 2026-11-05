import AppKit
import Foundation
import SevenTermCore

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
///
/// The environment alone isn't trusted: anything can set it. A stored
/// password is only released when the helper's real parent is ssh and that
/// ssh was started by this same 7 Term binary (directly, or through sftp);
/// see AskPassCaller. When the parent is some other ssh (a jump host's, a
/// child of the outer ssh), the host id and name are ignored and a password
/// prompt goes to the dialog instead. When the parent isn't ssh at all, the
/// helper exits with status 1 and shows nothing, so other programs can't use
/// 7 Term's dialogs to ask for a password.
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
        guard AskPassCaller.parentIsSSH() else { return 1 }
        let environment = ProcessInfo.processInfo.environment
        let prompt = arguments.dropFirst().joined(separator: " ")
        let trusted = AskPassCaller.currentProcessIsTrusted()
        let hostID = trusted ? environment[hostKey] ?? "" : ""
        let hostName = trusted ? environment[hostNameKey] ?? "this host" : "this host"
        let lowered = prompt.lowercased()

        // A host with a Keychain password: Touch ID, then the stored one.
        // Without one (a file browser tab has no terminal to type into), the
        // password prompt falls through to the dialog below.
        if !hostID.isEmpty, lowered.hasSuffix("password:") || lowered.hasSuffix("password: ") {
            guard let password = PasswordVault.read(hostID: hostID, reason: "connect to \(hostName)")
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
