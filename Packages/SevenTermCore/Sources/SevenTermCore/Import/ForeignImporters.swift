import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Yams

// Each importer reads only what 7 Term saves: name, host, port, user,
// folders or groups (as tags) and a key path. Stored passwords are never
// read, even when the format contains them (FileZilla, some PuTTY forks).

// MARK: - SecureCRT

/// SecureCRT keeps one .ini file per session in its Sessions folder;
/// subfolders are the folders in its session manager.
///
///     S:"Hostname"=10.0.0.1
///     S:"Username"=admin
///     S:"Protocol Name"=SSH2
///     D:"[SSH2] Port"=00000016        (hexadecimal: 22)
///     S:"Identity Filename V2"=/Users/me/.ssh/id_ed25519
public enum SecureCRTImport {
    /// `files` are (path relative to the Sessions folder, contents).
    public static func parse(files: [(path: String, text: String)]) -> ForeignImportResult {
        var result = ForeignImportResult()
        for (path, text) in files.sorted(by: { $0.path < $1.path }) {
            let components = path.split(separator: "/").map(String.init)
            guard let fileName = components.last, fileName.lowercased().hasSuffix(".ini") else { continue }
            let name = String(fileName.dropLast(4))
            if name == "__FolderData__" || name == "Default" { continue }

            var values: [String: String] = [:]
            for line in text.split(whereSeparator: \.isNewline) {
                // S:"Key"=value  or  D:"Key"=0000hex
                guard line.count > 3, let quoteEnd = line.dropFirst(3).firstIndex(of: "\""),
                      line.dropFirst(2).first == "\"" else { continue }
                let type = line.first!
                let key = String(line[line.index(line.startIndex, offsetBy: 3)..<quoteEnd])
                let rest = line[line.index(after: quoteEnd)...]
                guard rest.first == "=" else { continue }
                let value = String(rest.dropFirst())
                values[key] = type == "D" ? Int(value, radix: 16).map(String.init) ?? value : value
            }

            let protocolName = values["Protocol Name"] ?? "SSH2"
            guard protocolName.uppercased().hasPrefix("SSH") else {
                result.skipped.append("\(name): \(protocolName) session")
                continue
            }
            guard let host = values["Hostname"], !host.isEmpty else {
                result.skipped.append("\(name): no hostname")
                continue
            }
            let port = Int(values["[SSH2] Port"] ?? values["[SSH1] Port"] ?? "")
            result.hosts.append(ImportedHost(
                name: name,
                host: host,
                port: port == 22 ? nil : port,
                user: values["Username"].flatMap { $0.isEmpty ? nil : $0 },
                tags: Array(components.dropLast()),
                keyFile: values["Identity Filename V2"].map { $0.components(separatedBy: "::").first ?? $0 }
            ))
        }
        return result
    }
}

// MARK: - PuTTY and KiTTY (.reg export)

/// `reg export HKCU\Software\SimonTatham\PuTTY\Sessions putty.reg`:
///
///     [HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\core%20switch]
///     "HostName"="10.0.0.1"
///     "PortNumber"=dword:00000016
///     "UserName"="admin"
///     "Protocol"="ssh"
public enum PuTTYImport {
    public static func parse(_ text: String) -> ForeignImportResult {
        var result = ForeignImportResult()
        var current: String?
        var values: [String: String] = [:]

        func finish() {
            guard let name = current else { return }
            defer { current = nil; values = [:] }
            if name == "Default Settings" { return }
            let proto = values["Protocol"]?.lowercased() ?? "ssh"
            guard proto == "ssh" else {
                result.skipped.append("\(name): \(proto) session")
                return
            }
            guard let host = values["HostName"], !host.isEmpty else {
                result.skipped.append("\(name): no hostname")
                return
            }
            let port = values["PortNumber"].flatMap { Int($0) }
            result.hosts.append(ImportedHost(
                name: name, host: host, port: port == 22 ? nil : port,
                user: values["UserName"].flatMap { $0.isEmpty ? nil : $0 },
                keyFile: values["PublicKeyFile"]
            ))
        }

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                finish()
                let key = String(line.dropFirst().dropLast())
                if let range = key.range(of: "\\Sessions\\", options: .backwards) {
                    let encoded = String(key[range.upperBound...])
                    current = encoded.removingPercentEncoding ?? encoded
                }
                continue
            }
            guard current != nil, line.hasPrefix("\""), let close = line.dropFirst().firstIndex(of: "\"") else { continue }
            let key = String(line[line.index(after: line.startIndex)..<close])
            var value = String(line[line.index(after: close)...].dropFirst()) // after '='
            if value.hasPrefix("dword:") {
                value = Int(value.dropFirst(6), radix: 16).map(String.init) ?? ""
            } else if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\\", with: "\\")
                    .replacingOccurrences(of: "\\\"", with: "\"")
            }
            values[key] = value
        }
        finish()
        return result
    }
}

// MARK: - MobaXterm (.mxtsessions)

/// INI-style. `[Bookmarks]` and `[Bookmarks_N]` are folders; `SubRep` holds
/// the folder path ("Lab\Proxmox"). Each other line is a session:
///
///     pve1=#109#0%10.0.0.10%22%root%%-1%-1%…
///
/// Fields are split on "#", then the third on "%": type (0 is SSH, 7 is
/// SFTP), host, port, user, … and for SSH the key at position 14.
public enum MobaXtermImport {
    public static func parse(_ text: String) -> ForeignImportResult {
        var result = ForeignImportResult()
        var folder: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                folder = []
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            if key == "SubRep" {
                folder = value.split(separator: "\\").map(String.init).filter { !$0.isEmpty }
                continue
            }
            if key == "ImgNum" { continue }
            let parts = value.split(separator: "#", omittingEmptySubsequences: false)
            guard parts.count > 2 else { continue }
            let fields = parts[2].split(separator: "%", omittingEmptySubsequences: false).map(String.init)
            guard let type = fields.first else { continue }
            guard type == "0" || type == "7", fields.count > 3 else {
                result.skipped.append("\(key): \(Self.typeName(type)) session")
                continue
            }
            let host = fields[1]
            guard !host.isEmpty else {
                result.skipped.append("\(key): no hostname")
                continue
            }
            let port = Int(fields[2])
            let keyIndex = type == "0" ? 14 : 9
            result.hosts.append(ImportedHost(
                name: key, host: host, port: port == 22 ? nil : port,
                user: fields[3].isEmpty ? nil : fields[3],
                tags: folder,
                keyFile: fields.count > keyIndex ? fields[keyIndex] : nil
            ))
        }
        return result
    }

    static func typeName(_ code: String) -> String {
        switch code {
        case "1": "Telnet"
        case "4": "RDP"
        case "5": "VNC"
        case "11": "browser"
        default: "non-SSH"
        }
    }
}

// MARK: - FileZilla (sitemanager.xml or an export)

/// `<Folder>` elements nest; `<Server>` has Host, Port, Protocol (1 is SFTP),
/// User, Name and Keyfile. `<Pass>` is skipped without being read.
public enum FileZillaImport {
    public static func parse(_ text: String) throws -> ForeignImportResult {
        let delegate = Delegate()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = delegate
        guard parser.parse() else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "That isn't a FileZilla site list."])
        }
        return delegate.result
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var result = ForeignImportResult()
        private var folders: [String] = []
        private var server: [String: String]?
        private var text = ""
        private var awaitingFolderName = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "Folder":
                folders.append("")
                awaitingFolderName = true
            case "Server":
                server = [:]
                awaitingFolderName = false
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
            // A folder's name is its first text, before any child element.
            if awaitingFolderName, server == nil {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !folders.isEmpty { folders[folders.count - 1] = trimmed }
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { text = "" }
            if name == "Folder" {
                if !folders.isEmpty { folders.removeLast() }
                return
            }
            guard var current = server else { return }
            if name == "Server" {
                server = nil
                finish(current)
                return
            }
            if name != "Pass" { current[name] = value }
            server = current
        }

        private func finish(_ fields: [String: String]) {
            let name = fields["Name"].flatMap { $0.isEmpty ? nil : $0 } ?? fields["Host"] ?? "site"
            guard fields["Protocol"] == "1" else {
                result.skipped.append("\(name): FTP site (only SFTP is imported)")
                return
            }
            guard let host = fields["Host"], !host.isEmpty else {
                result.skipped.append("\(name): no host")
                return
            }
            let port = fields["Port"].flatMap { Int($0) }
            result.hosts.append(ImportedHost(
                name: name, host: host, port: port == 22 ? nil : port,
                user: fields["User"].flatMap { $0.isEmpty ? nil : $0 },
                tags: folders.filter { !$0.isEmpty },
                keyFile: fields["Keyfile"]
            ))
        }
    }
}

// MARK: - Ansible inventory

/// INI or YAML inventories. Groups (including parent groups through
/// `:children`) become tags; `all` and `ungrouped` don't. Variables used:
/// ansible_host, ansible_port, ansible_user (or ansible_ssh_user) and
/// ansible_ssh_private_key_file, from the host line or its groups' vars.
public enum AnsibleImport {
    private struct Inventory {
        var hostVars: [String: [String: String]] = [:]
        var hostOrder: [String] = []
        var groupHosts: [String: [String]] = [:]
        var groupVars: [String: [String: String]] = [:]
        var groupChildren: [String: [String]] = [:]
        var skipped: [String] = []

        mutating func add(host: String, group: String, vars: [String: String]) {
            if hostVars[host] == nil {
                hostVars[host] = [:]
                hostOrder.append(host)
            }
            hostVars[host]!.merge(vars) { _, new in new }
            if !groupHosts[group, default: []].contains(host) { groupHosts[group, default: []].append(host) }
        }

        func result() -> ForeignImportResult {
            // Parents of each group, through :children.
            var parents: [String: Set<String>] = [:]
            for (parent, children) in groupChildren {
                for child in children { parents[child, default: []].insert(parent) }
            }
            func ancestry(_ group: String) -> [String] {
                var seen: [String] = []
                var queue = [group]
                while let next = queue.popLast() {
                    guard !seen.contains(next) else { continue }
                    seen.append(next)
                    queue += parents[next].map(Array.init) ?? []
                }
                return seen
            }

            var hosts: [ImportedHost] = []
            for name in hostOrder {
                let direct = groupHosts.filter { $0.value.contains(name) }.map(\.key).sorted()
                var groups: [String] = []
                for group in direct {
                    for g in ancestry(group) where !groups.contains(g) { groups.append(g) }
                }
                // Variables: all, then groups (parents first), then the host.
                var vars = groupVars["all"] ?? [:]
                for group in groups.reversed() { vars.merge(groupVars[group] ?? [:]) { _, new in new } }
                vars.merge(hostVars[name] ?? [:]) { _, new in new }

                let address = vars["ansible_host"] ?? vars["ansible_ssh_host"] ?? name
                let port = Int(vars["ansible_port"] ?? vars["ansible_ssh_port"] ?? "")
                hosts.append(ImportedHost(
                    name: name, host: address, port: port == 22 ? nil : port,
                    user: vars["ansible_user"] ?? vars["ansible_ssh_user"],
                    tags: groups.filter { $0 != "all" && $0 != "ungrouped" }.sorted(),
                    keyFile: vars["ansible_ssh_private_key_file"] ?? vars["ansible_private_key_file"]
                ))
            }
            return ForeignImportResult(hosts: hosts, skipped: skipped)
        }
    }

    public static func parseINI(_ text: String) -> ForeignImportResult {
        var inventory = Inventory()
        var section = "ungrouped"
        var mode = "hosts"
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(where: { $0 == "#" || $0 == ";" }), hash == line.startIndex { continue }
            if let comment = line.range(of: " #") { line = String(line[..<comment.lowerBound]) }
            guard !line.isEmpty else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                let header = String(line.dropFirst().dropLast())
                let parts = header.split(separator: ":", maxSplits: 1).map(String.init)
                section = parts[0]
                mode = parts.count > 1 ? parts[1] : "hosts"
                continue
            }
            let tokens = splitTokens(line)
            guard let first = tokens.first else { continue }
            switch mode {
            case "children":
                inventory.groupChildren[section, default: []].append(first)
            case "vars":
                let pair = keyValue(line)
                if let (key, value) = pair { inventory.groupVars[section, default: [:]][key] = value }
            default:
                if first.contains("[") && first.contains(":") && first.contains("]") {
                    inventory.skipped.append("\(first): host ranges aren't expanded")
                    continue
                }
                var vars: [String: String] = [:]
                for token in tokens.dropFirst() {
                    if let (key, value) = keyValue(token) { vars[key] = value }
                }
                inventory.add(host: first, group: section, vars: vars)
            }
        }
        return inventory.result()
    }

    public static func parseYAML(_ text: String) throws -> ForeignImportResult {
        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "That isn't an Ansible inventory."])
        }
        var inventory = Inventory()
        func visit(group: String, _ body: [String: Any]) {
            if let hosts = body["hosts"] as? [String: Any] {
                for (host, value) in hosts.sorted(by: { $0.key < $1.key }) {
                    inventory.add(host: host, group: group, vars: strings(value as? [String: Any]))
                }
            }
            if let vars = body["vars"] as? [String: Any] {
                inventory.groupVars[group, default: [:]].merge(strings(vars)) { _, new in new }
            }
            if let children = body["children"] as? [String: Any] {
                for (child, value) in children.sorted(by: { $0.key < $1.key }) {
                    inventory.groupChildren[group, default: []].append(child)
                    visit(group: child, value as? [String: Any] ?? [:])
                }
            }
        }
        for (group, value) in root.sorted(by: { $0.key < $1.key }) {
            visit(group: group, value as? [String: Any] ?? [:])
        }
        return inventory.result()
    }

    private static func strings(_ map: [String: Any]?) -> [String: String] {
        (map ?? [:]).compactMapValues { value in
            switch value {
            case let string as String: string
            case let number as Int: String(number)
            default: nil
            }
        }
    }

    /// Splits on spaces outside quotes.
    private static func splitTokens(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func keyValue(_ text: String) -> (String, String)? {
        guard let equals = text.firstIndex(of: "=") else { return nil }
        let key = text[..<equals].trimmingCharacters(in: .whitespaces)
        var value = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        return key.isEmpty ? nil : (key, value)
    }
}

// MARK: - Tabby (config.yaml)

/// `profiles:` is a list; SSH ones have `type: ssh` and an `options` map
/// with host, port, user and privateKeys. `group` is a group id (newer
/// versions, names in `groups:`) or the group's name (older ones).
public enum TabbyImport {
    public static func parse(_ text: String) throws -> ForeignImportResult {
        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "That isn't a Tabby config.yaml."])
        }
        var groupNames: [String: String] = [:]
        for group in root["groups"] as? [[String: Any]] ?? [] {
            if let id = group["id"] as? String, let name = group["name"] as? String { groupNames[id] = name }
        }
        var result = ForeignImportResult()
        for profile in root["profiles"] as? [[String: Any]] ?? [] {
            let name = profile["name"] as? String ?? "profile"
            let type = profile["type"] as? String ?? ""
            guard type == "ssh" else {
                result.skipped.append("\(name): \(type.isEmpty ? "unknown" : type) profile")
                continue
            }
            let options = profile["options"] as? [String: Any] ?? [:]
            guard let host = options["host"] as? String, !host.isEmpty else {
                result.skipped.append("\(name): no host")
                continue
            }
            let port = options["port"] as? Int
            let group = (profile["group"] as? String).map { groupNames[$0] ?? $0 }
            result.hosts.append(ImportedHost(
                name: name, host: host, port: port == 22 ? nil : port,
                user: options["user"] as? String,
                tags: group.map { [$0] } ?? [],
                keyFile: (options["privateKeys"] as? [String])?.first
            ))
        }
        return result
    }
}
