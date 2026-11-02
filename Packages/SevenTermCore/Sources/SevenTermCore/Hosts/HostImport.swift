import Foundation

/// What a spreadsheet column holds.
public enum HostImportColumn: String, CaseIterable, Sendable {
    case ignore, name, host, port, user, tags, keyFile

    public var title: String {
        switch self {
        case .ignore: "Ignore"
        case .name: "Name"
        case .host: "Host"
        case .port: "Port"
        case .user: "User"
        case .tags: "Tags"
        case .keyFile: "Key file"
        }
    }

    /// Header words that mean this column, lowercased with spaces, dashes
    /// and underscores removed.
    static let headerWords: [HostImportColumn: Set<String>] = [
        .name: ["name", "label", "alias", "displayname", "title", "server", "servername", "system"],
        .host: ["host", "hostname", "ip", "ipaddress", "address", "dns", "dnsname", "fqdn", "addr"],
        .port: ["port", "sshport"],
        .user: ["user", "username", "login", "account", "sshuser"],
        .tags: ["tags", "tag", "group", "groups", "folder", "folders", "category", "labels", "role", "environment", "env"],
        .keyFile: ["key", "keyfile", "identity", "identityfile", "privatekey", "sshkey"],
    ]

    /// Columns that look like secrets. They're never read, and can't be
    /// mapped to anything.
    static let secretWords: Set<String> = [
        "password", "passwd", "pass", "pwd", "secret", "passphrase", "token", "pin", "credential", "credentials",
    ]
    /// Also secret when a header starts with one of these ("Password (root)").
    static let secretPrefixes = ["password", "passwd", "passphrase", "secret", "credential"]
}

/// A pasted or opened table of hosts, before anything is saved.
///
/// Accepts CSV, semicolon-separated, or tab-separated text. Copying cells in
/// Excel or Numbers puts tab-separated text on the clipboard, so pasting
/// rows works without saving a file. A header row is recognised and used to
/// guess the columns; every guess can be changed.
public struct HostImportTable: Equatable, Sendable {
    /// The header row's cells, when the first row is a header.
    public var header: [String]?
    /// Data rows, each padded to `columnCount`.
    public var rows: [[String]]
    /// What each column holds.
    public var columns: [HostImportColumn]
    /// Columns that look like passwords: never read.
    public var secretColumns: Set<Int>
    /// The line number in the input of each data row (1-based), for messages.
    public var lineNumbers: [Int]

    public var columnCount: Int { columns.count }

    public static func parse(_ text: String) -> HostImportTable {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let delimiter = detectDelimiter(text)
        let parsed = parseRecords(text, delimiter: delimiter)
            .filter { !$0.cells.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        let width = parsed.map(\.cells.count).max() ?? 0
        var records = parsed.map { record in
            (line: record.line, cells: record.cells.map { $0.trimmingCharacters(in: .whitespaces) }
                + Array(repeating: "", count: width - record.cells.count))
        }

        var header: [String]?
        var columns = Array(repeating: HostImportColumn.ignore, count: width)
        var secrets = Set<Int>()

        if let first = records.first, looksLikeHeader(first.cells) {
            header = first.cells
            records.removeFirst()
            var used = Set<HostImportColumn>()
            for (index, cell) in first.cells.enumerated() {
                let word = normalized(cell)
                if HostImportColumn.secretWords.contains(word)
                    || HostImportColumn.secretPrefixes.contains(where: { word.hasPrefix($0) }) {
                    secrets.insert(index)
                    continue
                }
                if let match = HostImportColumn.headerWords.first(where: { $0.value.contains(word) })?.key,
                   !used.contains(match) {
                    columns[index] = match
                    used.insert(match)
                }
            }
            // A sheet with a "Name" column but no address column: the names
            // are what ssh connects to (ssh_config aliases or DNS names).
            if !used.contains(.host), let nameIndex = columns.firstIndex(of: .name) {
                columns[nameIndex] = .host
            }
        } else {
            columns = guessColumns(records.map(\.cells), width: width)
        }

        return HostImportTable(
            header: header,
            rows: records.map(\.cells),
            columns: columns,
            secretColumns: secrets,
            lineNumbers: records.map(\.line)
        )
    }

    /// The hosts these rows describe, checked against `existing`.
    /// `tag` is added to every host (for example "imported").
    public func candidates(existing: [HostEntry], tag: String? = nil) -> [HostImportCandidate] {
        var known: [String: String] = [:]
        for entry in existing {
            known[Self.identity(host: entry.host.hostname, port: entry.host.port, user: entry.host.username)] = entry.id
        }
        var seenInFile: [String: Int] = [:]

        return rows.enumerated().map { index, cells in
            let line = lineNumbers[index]
            func value(_ column: HostImportColumn) -> String {
                guard let position = columns.firstIndex(of: column), !secretColumns.contains(position) else { return "" }
                return cells[position]
            }

            var draft = HostDraft()
            var hostText = value(.host)
            var port = value(.port)
            var user = value(.user)
            // "user@host:port" in the host column fills the others if they're empty.
            if hostText.contains("@") || hostText.filter({ $0 == ":" }).count == 1 || hostText.hasPrefix("["),
               let parsed = SSHTarget.parse(hostText) {
                hostText = parsed.host
                if port.isEmpty, let parsedPort = parsed.port { port = String(parsedPort) }
                if user.isEmpty, let parsedUser = parsed.user { user = parsedUser }
            }
            draft.hostname = hostText
            draft.port = port
            draft.username = user
            draft.name = value(.name).isEmpty ? hostText : value(.name)

            var tags = value(.tags)
                .split(whereSeparator: { $0 == ";" || $0 == "," || $0 == "|" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let tag, !tag.trimmingCharacters(in: .whitespaces).isEmpty {
                tags.append(tag.trimmingCharacters(in: .whitespaces))
            }
            draft.tags = tags.filter { !$0.isEmpty }.joined(separator: ", ")

            let key = value(.keyFile)
            if !key.isEmpty {
                draft.authMethod = .keyFile
                draft.identityFile = key
            }

            var problems = draft.errors.sorted { "\($0.key)" < "\($1.key)" }.map(\.value)
            var existingID: String?
            var duplicateLine: Int?
            if problems.isEmpty, let target = draft.target {
                let identity = Self.identity(host: target.host, port: target.port, user: target.user)
                existingID = known[identity]
                if let earlier = seenInFile[identity] {
                    duplicateLine = earlier
                    problems.append("Same host as line \(earlier).")
                } else {
                    seenInFile[identity] = line
                }
            }
            return HostImportCandidate(
                line: line, draft: draft, problems: problems,
                existingID: existingID, duplicateOfLine: duplicateLine)
        }
    }

    /// Host, port and user decide whether two entries are the same machine.
    /// Port 22 and no port are the same; host and user ignore case.
    static func identity(host: String, port: Int?, user: String?) -> String {
        "\(host.lowercased())|\(port ?? 22)|\((user ?? "").lowercased())"
    }

    // MARK: Parsing

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var counts: [Character: Int] = ["\t": 0, ",": 0, ";": 0]
        var inQuotes = false
        for character in firstLine {
            if character == "\"" { inQuotes.toggle() }
            if !inQuotes, counts[character] != nil { counts[character]! += 1 }
        }
        if counts["\t"]! > 0 { return "\t" }
        return counts[";"]! > counts[","]! ? ";" : ","
    }

    /// RFC 4180: quoted fields may hold the delimiter, newlines and "" for a quote.
    static func parseRecords(_ text: String, delimiter: Character) -> [(line: Int, cells: [String])] {
        var records: [(line: Int, cells: [String])] = []
        var cells: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1
        var recordLine = 1
        var characters = Array(text)
        characters.append("\n")
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    if character.isNewline { line += 1 }
                    field.append(character)
                }
            } else if character == "\"", field.isEmpty {
                inQuotes = true
            } else if character == delimiter {
                cells.append(field)
                field = ""
            } else if character.isNewline {
                // "\r\n" is one Character in Swift, so this runs once per line.
                cells.append(field)
                field = ""
                records.append((recordLine, cells))
                cells = []
                line += 1
                recordLine = line
            } else {
                field.append(character)
            }
            index += 1
        }
        // The appended newline always closes the last record; drop a trailing
        // empty one from input that already ended with a newline.
        if let last = records.last, last.cells == [""] { records.removeLast() }
        return records
    }

    static func normalized(_ header: String) -> String {
        header.lowercased().filter { !" _-.".contains($0) }
    }

    static func looksLikeHeader(_ cells: [String]) -> Bool {
        let words = cells.map(normalized)
        let known = HostImportColumn.headerWords.values.reduce(into: Set<String>()) { $0.formUnion($1) }
            .union(HostImportColumn.secretWords)
        return words.contains { known.contains($0) }
    }

    /// No header: the column of addresses is the host, a column of small
    /// numbers is the port, and a text column before the host is the name.
    static func guessColumns(_ rows: [[String]], width: Int) -> [HostImportColumn] {
        var columns = Array(repeating: HostImportColumn.ignore, count: width)
        guard width > 0 else { return columns }
        if width == 1 { return [.host] }

        func share(_ index: Int, _ test: (String) -> Bool) -> Double {
            let values = rows.map { $0[index] }.filter { !$0.isEmpty }
            guard !values.isEmpty else { return 0 }
            return Double(values.filter(test).count) / Double(values.count)
        }
        let looksLikeAddress: (String) -> Bool = { value in
            value.contains(".") || value.contains(":") || value.contains("@")
        }
        let looksLikePort: (String) -> Bool = { value in
            Int(value).map { (1...65535).contains($0) } ?? false
        }

        let hostIndex = (0..<width).max { share($0, looksLikeAddress) < share($1, looksLikeAddress) } ?? 0
        columns[hostIndex] = .host
        if let portIndex = (0..<width).first(where: { $0 != hostIndex && share($0, looksLikePort) > 0.8 }) {
            columns[portIndex] = .port
        }
        if let nameIndex = (0..<width).first(where: { columns[$0] == .ignore }) {
            columns[nameIndex] = .name
        }
        return columns
    }
}

/// One row turned into a host.
public struct HostImportCandidate: Identifiable, Equatable, Sendable {
    public var id: Int { line }
    public var line: Int
    public var draft: HostDraft
    /// Why the row can't be imported; empty when it can.
    public var problems: [String]
    /// The saved host with the same host, port and user, if any.
    public var existingID: String?
    public var duplicateOfLine: Int?

    public var isImportable: Bool { problems.isEmpty }
}

extension HostLibrary {
    /// Saves the importable candidates. Rows matching a saved host are
    /// skipped, or with `updateExisting` merged into it: the row's non-empty
    /// fields win and tags are added, never removed. Auth settings that
    /// aren't in the row (a Keychain password, logging) stay as they were.
    public func importHosts(
        _ candidates: [HostImportCandidate],
        updateExisting: Bool,
        now: Date = Date()
    ) throws -> (added: Int, updated: Int) {
        let current = Dictionary(uniqueKeysWithValues: try entries().map { ($0.id, $0) })
        var added = 0, updated = 0
        for candidate in candidates where candidate.isImportable {
            if let id = candidate.existingID {
                guard updateExisting, let entry = current[id] else { continue }
                var merged = HostDraft(entry: entry)
                let row = candidate.draft
                if !row.trimmedName.isEmpty, row.name != row.hostname { merged.name = row.name }
                if !row.port.isEmpty { merged.port = row.port }
                if !row.username.isEmpty { merged.username = row.username }
                if row.authMethod == .keyFile {
                    merged.authMethod = .keyFile
                    merged.identityFile = row.identityFile
                }
                merged.tags = (merged.tagList + row.tagList).joined(separator: ", ")
                _ = try save(merged, id: id, now: now)
                updated += 1
            } else {
                _ = try save(candidate.draft, now: now)
                added += 1
            }
        }
        return (added, updated)
    }
}
