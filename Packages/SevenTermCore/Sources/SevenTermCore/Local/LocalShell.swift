import Foundation

/// The shell a local terminal tab runs: the account's login shell, the same
/// one Terminal.app would start.
public struct LocalShell: Equatable, Sendable {
    public let path: String

    /// Used when the account's shell is missing, relative, or won't run
    /// (for example a Homebrew shell that was uninstalled).
    public static let fallbackPath = "/bin/zsh"

    public init(path: String) {
        self.path = path
    }

    /// The account's shell if it's an absolute path that runs, else zsh.
    public static func resolve(passwdShell: String?, isExecutable: (String) -> Bool) -> LocalShell {
        if let passwdShell, passwdShell.hasPrefix("/"), isExecutable(passwdShell) {
            return LocalShell(path: passwdShell)
        }
        return LocalShell(path: fallbackPath)
    }

    /// The shell from the user database (not $SHELL, which a GUI app may
    /// not have, or may have inherited from somewhere else).
    public static func current() -> LocalShell {
        let passwdShell = getpwuid(getuid()).flatMap { entry in
            entry.pointee.pw_shell.map { String(cString: $0) }
        }
        return resolve(passwdShell: passwdShell, isExecutable: FileManager.default.isExecutableFile(atPath:))
    }

    /// "zsh" for /bin/zsh.
    public var name: String {
        (path as NSString).lastPathComponent
    }

    /// argv[0] with a leading "-", which tells the shell it's a login shell,
    /// so /etc/zprofile (path_helper) and the user's profile run.
    public var loginArgv0: String {
        "-" + name
    }
}

/// The built-in This Mac entry at the top of the sidebar. It isn't a saved
/// host: nothing about it is stored, backed up or imported.
public enum LocalTerminal {
    public static let title = "This Mac"
    /// The sidebar selection id. Saved hosts and folders use UUIDs, so this
    /// can't collide with one.
    public static let sidebarID = "builtin.this-mac"

    public static func subtitle(shellName: String) -> String {
        "Local terminal (\(shellName))"
    }

    /// Whether the row stays visible for what's typed in the sidebar filter.
    public static func matches(query: String, shellName: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return [title, "local", shellName].contains { $0.localizedCaseInsensitiveContains(text) }
    }

    /// The Mac's short host name, for log file names: "mbp" for "mbp.lan".
    public static func machineName(hostName: String) -> String {
        let short = hostName.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        return short.isEmpty ? "localhost" : short
    }
}
