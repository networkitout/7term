import Foundation

/// What the host form edits. Text in, validated values out.
public struct HostDraft: Hashable, Sendable {
    public enum Field: Hashable, Sendable {
        case name, hostname, port, username, tags
    }

    public var name = ""
    public var hostname = ""
    public var port = ""
    public var username = ""
    /// Comma-separated, as typed.
    public var tags = ""
    public var logByDefault = false

    public init() {}

    public init(entry: HostEntry) {
        name = entry.host.name
        hostname = entry.host.hostname
        port = entry.host.port.map(String.init) ?? ""
        username = entry.host.username ?? ""
        tags = entry.tags.joined(separator: ", ")
        logByDefault = entry.host.logByDefault
    }

    /// A problem per field, empty when the draft can be saved.
    public var errors: [Field: String] {
        var errors: [Field: String] = [:]

        if trimmedName.isEmpty {
            errors[.name] = "Give the host a name."
        }

        let host = trimmed(hostname)
        if host.isEmpty {
            errors[.hostname] = "Enter an IP address, DNS name, or ssh_config alias."
        } else if !Self.isSafeToken(host) {
            errors[.hostname] = "No spaces, and it can't start with \"-\"."
        }

        let portText = trimmed(port)
        if !portText.isEmpty, Int(portText).map({ (1...65535).contains($0) }) != true {
            errors[.port] = "Port must be a number from 1 to 65535."
        }

        let user = trimmed(username)
        if !user.isEmpty, !Self.isSafeToken(user) {
            errors[.username] = "No spaces, and it can't start with \"-\"."
        }

        if tagList.contains(where: { $0.count > 40 }) {
            errors[.tags] = "Keep each tag under 40 characters."
        }
        return errors
    }

    public var isValid: Bool { errors.isEmpty }

    public var trimmedName: String { trimmed(name) }

    /// The target ssh would get from this draft, when the connection fields
    /// (host, port, user) are valid. The name and tags don't affect it, so a
    /// reachability test works before the host is named.
    public var target: SSHTarget? {
        let connectionFields: Set<Field> = [.hostname, .port, .username]
        guard errors.keys.allSatisfy({ !connectionFields.contains($0) }) else { return nil }
        return SSHTarget(
            user: nonEmpty(trimmed(username)),
            host: stripBrackets(trimmed(hostname)),
            port: Int(trimmed(port))
        )
    }

    /// Tags split on commas, trimmed, empty ones dropped, duplicates removed
    /// without regard to case (the first spelling wins).
    public var tagList: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags.split(separator: ",") {
            let tag = raw.trimmingCharacters(in: .whitespaces)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    static func isSafeToken(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasPrefix("-")
            && !value.contains(where: \.isWhitespace)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    /// Accepts "[fe80::1]" in the form but stores the bare address ssh wants.
    private func stripBrackets(_ value: String) -> String {
        guard value.hasPrefix("["), value.hasSuffix("]"), value.count > 2 else { return value }
        return String(value.dropFirst().dropLast())
    }
}
