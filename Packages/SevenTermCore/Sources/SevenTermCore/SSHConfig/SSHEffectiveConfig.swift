/// Reads the output of `ssh -G <destination>`, which prints the settings ssh
/// would use after applying ~/.ssh/config, without connecting.
public struct SSHEffectiveConfig: Hashable, Sendable {
    public var hostname: String
    public var port: Int
    public var user: String?

    public init(hostname: String, port: Int, user: String? = nil) {
        self.hostname = hostname
        self.port = port
        self.user = user
    }

    /// Nil when the output lacks a hostname or a valid port.
    public static func parse(_ output: String) -> SSHEffectiveConfig? {
        var hostname: String?
        var port: Int?
        var user: String?
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch parts[0].lowercased() {
            case "hostname" where hostname == nil: hostname = value
            case "port" where port == nil: port = Int(value)
            case "user" where user == nil: user = value
            default: continue
            }
        }
        guard let hostname, !hostname.isEmpty, let port, (1...65535).contains(port) else { return nil }
        return SSHEffectiveConfig(hostname: hostname, port: port, user: user)
    }

    /// Arguments for `/usr/bin/ssh -G` that mirror a real connection to `target`.
    public static func arguments(for target: SSHTarget) -> [String] {
        ["-G"] + target.sshArguments
    }
}
