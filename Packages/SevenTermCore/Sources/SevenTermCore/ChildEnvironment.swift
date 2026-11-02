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

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
