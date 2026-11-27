/// The environment handed to ssh and sftp child processes.
///
/// GUI apps don't read your shell profile, and they often start without LANG,
/// which macOS ssh forwards to the remote side. So the environment is built
/// from an allowlist instead of inherited wholesale.
public enum ChildEnvironment {
    /// Variables copied from the app's own environment when present.
    public static let passthroughKeys = ["HOME", "USER", "LOGNAME", "SSH_AUTH_SOCK", "TMPDIR"]

    public static func make(from parent: [String: String]) -> [String] {
        var environment: [String: String] = [
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "LANG": nonEmpty(parent["LANG"]) ?? "en_US.UTF-8",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        for key in passthroughKeys {
            if let value = nonEmpty(parent[key]) { environment[key] = value }
        }
        return environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
    }

    /// The environment for a local login shell: the same allowlist, plus the
    /// shell's own path and the terminal's name. The login shell builds the
    /// rest of PATH itself (path_helper, then the user's profile).
    public static func makeLocal(from parent: [String: String], shell: String) -> [String] {
        (make(from: parent) + ["SHELL=\(shell)", "TERM_PROGRAM=7Term"]).sorted()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
