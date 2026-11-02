import Foundation

/// Where an SSH session goes. Parsed from what the user types, then turned
/// into an argument list for /usr/bin/ssh (never a shell string).
public struct SSHTarget: Hashable, Sendable {
    public var user: String?
    public var host: String
    public var port: Int?
    /// A private key to use instead of whatever the agent or ssh_config offers.
    public var identityFile: String?

    public init(user: String? = nil, host: String, port: Int? = nil, identityFile: String? = nil) {
        self.user = user
        self.host = host
        self.port = port
        self.identityFile = identityFile
    }

    /// Accepts `host`, `user@host`, `host:port`, `user@host:port`, a bare IPv6
    /// address, or a bracketed one (`user@[fe80::1]:22`).
    /// Returns nil for anything that is empty, contains whitespace or control
    /// characters, or whose user or host starts with "-" (which ssh would read
    /// as an option).
    public static func parse(_ input: String) -> SSHTarget? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty,
              !text.contains(where: \.isWhitespace),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }

        var user: String?
        var rest = Substring(text)
        if let at = rest.lastIndex(of: "@") {
            let name = rest[..<at]
            guard !name.isEmpty else { return nil }
            user = String(name)
            rest = rest[rest.index(after: at)...]
        }

        let host: Substring
        var port: Int?
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { return nil }
            host = rest[rest.index(after: rest.startIndex)..<close]
            let after = rest[rest.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":"), let value = Int(after.dropFirst()) else { return nil }
                port = value
            }
        } else if rest.filter({ $0 == ":" }).count == 1, let colon = rest.firstIndex(of: ":") {
            host = rest[..<colon]
            guard let value = Int(rest[rest.index(after: colon)...]) else { return nil }
            port = value
        } else {
            // A plain hostname, an ssh_config alias, or a bare IPv6 address.
            host = rest
        }

        guard !host.isEmpty, !host.hasPrefix("-") else { return nil }
        if let user, user.hasPrefix("-") { return nil }
        if let port, !(1...65535).contains(port) { return nil }
        return SSHTarget(user: user, host: String(host), port: port)
    }

    /// Short name for a tab: `user@host`, plus `:port` when one was given.
    public var displayName: String {
        var name = user.map { "\($0)@\(host)" } ?? host
        if let port { name += ":\(port)" }
        return name
    }

    /// Arguments for /usr/bin/ssh. `--` ends option parsing, so the host can
    /// never be read as an option. Anything not given here (ProxyJump, keys,
    /// ciphers) still comes from ~/.ssh/config.
    public var sshArguments: [String] {
        var arguments = identityArguments
        if let user { arguments += ["-l", user] }
        if let port { arguments += ["-p", String(port)] }
        arguments += ["--", host]
        return arguments
    }

    /// `-i <key> -o IdentitiesOnly=yes`: use this key and no other, so a
    /// full agent can't exhaust the server's MaxAuthTries first.
    var identityArguments: [String] {
        guard let identityFile else { return [] }
        return ["-i", identityFile, "-o", "IdentitiesOnly=yes"]
    }

    /// Arguments for /usr/bin/sftp, which takes the port as -P and the user
    /// in the destination. An IPv6 address is bracketed there.
    public var sftpArguments: [String] {
        var arguments = identityArguments
        if let port { arguments += ["-P", String(port)] }
        let hostPart = host.contains(":") ? "[\(host)]" : host
        arguments += ["--", user.map { "\($0)@\(hostPart)" } ?? hostPart]
        return arguments
    }

    /// An `sftp://` URL for handing the host to a file transfer app.
    /// `host` should be a real address (resolve ssh_config aliases first).
    public static func sftpURL(host: String, port: Int?, user: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "sftp"
        components.user = user
        components.host = host.contains(":") ? "[\(host)]" : host
        if let port, port != 22 { components.port = port }
        components.path = "/"
        return components.url
    }
}
