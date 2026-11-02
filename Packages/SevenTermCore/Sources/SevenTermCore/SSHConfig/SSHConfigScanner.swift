import Foundation

/// A concrete `Host` alias found in ssh_config, with the values ssh would use
/// from that block (first value wins, as in ssh). Used to offer an import and
/// to show where an alias points; ssh still reads the config itself.
public struct SSHConfigAlias: Hashable, Sendable, Identifiable {
    public var alias: String
    public var hostName: String?
    public var user: String?
    public var port: Int?

    public var id: String { alias }

    public init(alias: String, hostName: String? = nil, user: String? = nil, port: Int? = nil) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
    }
}

/// Finds Host aliases in ssh_config text. It reads only what an import needs:
/// Host, HostName, User, Port, Match and Include. Wildcard and negated
/// patterns are skipped because they aren't hosts you can connect to.
public struct SSHConfigScanner: Sendable {
    /// Reads a file's text, or nil when it can't.
    public var readFile: @Sendable (String) -> String?
    /// Expands an absolute path that may contain glob characters.
    public var expandGlob: @Sendable (String) -> [String]
    public var homeDirectory: String
    public var maximumIncludeDepth = 8

    public init(
        homeDirectory: String,
        readFile: @escaping @Sendable (String) -> String?,
        expandGlob: @escaping @Sendable (String) -> [String]
    ) {
        self.homeDirectory = homeDirectory
        self.readFile = readFile
        self.expandGlob = expandGlob
    }

    /// Aliases in the user's config at `path` (normally ~/.ssh/config) and
    /// the files it includes, in file order, without duplicates.
    public func aliases(inFileAt path: String) -> [SSHConfigAlias] {
        var found: [SSHConfigAlias] = []
        var seenAliases = Set<String>()
        var visitedFiles = Set<String>()
        scan(path: path, depth: 0, found: &found, seenAliases: &seenAliases, visitedFiles: &visitedFiles)
        return found
    }

    /// Aliases in one piece of config text, ignoring Include lines.
    public static func aliases(in text: String) -> [SSHConfigAlias] {
        var found: [SSHConfigAlias] = []
        var seen = Set<String>()
        for item in parse(text) {
            if case .block(let aliases) = item {
                for alias in aliases where seen.insert(alias.alias.lowercased()).inserted {
                    found.append(alias)
                }
            }
        }
        return found
    }

    // MARK: Private

    private enum Item {
        case block([SSHConfigAlias])
        case include([String])
    }

    private func scan(
        path: String,
        depth: Int,
        found: inout [SSHConfigAlias],
        seenAliases: inout Set<String>,
        visitedFiles: inout Set<String>
    ) {
        let path = (path as NSString).standardizingPath
        guard depth <= maximumIncludeDepth,
              visitedFiles.insert(path).inserted,
              let text = readFile(path)
        else { return }

        for item in Self.parse(text) {
            switch item {
            case .block(let aliases):
                for alias in aliases where seenAliases.insert(alias.alias.lowercased()).inserted {
                    found.append(alias)
                }
            case .include(let patterns):
                for pattern in patterns {
                    for file in expandGlob(resolveIncludePath(pattern)).sorted() {
                        scan(path: file, depth: depth + 1, found: &found,
                             seenAliases: &seenAliases, visitedFiles: &visitedFiles)
                    }
                }
            }
        }
    }

    /// In a user config, relative Include paths are relative to ~/.ssh.
    private func resolveIncludePath(_ pattern: String) -> String {
        if pattern.hasPrefix("~/") {
            return homeDirectory + String(pattern.dropFirst(1))
        }
        if pattern.hasPrefix("/") {
            return pattern
        }
        return homeDirectory + "/.ssh/" + pattern
    }

    private static func parse(_ text: String) -> [Item] {
        var items: [Item] = []
        var current: [SSHConfigAlias] = []

        func closeBlock() {
            if !current.isEmpty { items.append(.block(current)) }
            current = []
        }

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            guard let parsed = splitLine(String(rawLine)) else { continue }
            let (keyword, arguments) = parsed
            switch keyword {
            case "host":
                closeBlock()
                current = arguments
                    .filter(isConcreteAlias)
                    .map { SSHConfigAlias(alias: $0) }
            case "match":
                closeBlock()
            case "include":
                closeBlock()
                items.append(.include(arguments))
            case "hostname":
                guard let value = arguments.first else { continue }
                for index in current.indices where current[index].hostName == nil {
                    current[index].hostName = value
                }
            case "user":
                guard let value = arguments.first else { continue }
                for index in current.indices where current[index].user == nil {
                    current[index].user = value
                }
            case "port":
                guard let value = arguments.first.flatMap(Int.init) else { continue }
                for index in current.indices where current[index].port == nil {
                    current[index].port = value
                }
            default:
                continue
            }
        }
        closeBlock()
        return items
    }

    /// Splits "Keyword value", "Keyword=value" or "Keyword = value" into a
    /// lowercased keyword and its arguments. Double quotes group words.
    /// Returns nil for blank lines and comments.
    static func splitLine(_ line: String) -> (String, [String])? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        guard let end = trimmed.firstIndex(where: { $0.isWhitespace || $0 == "=" }) else {
            return (trimmed.lowercased(), [])
        }
        let keyword = trimmed[..<end].lowercased()
        var rest = trimmed[end...].drop(while: \.isWhitespace)
        if rest.first == "=" { rest = rest.dropFirst().drop(while: \.isWhitespace) }
        return (keyword, tokenize(rest))
    }

    private static func tokenize(_ text: Substring) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var hasToken = false
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
                hasToken = true
            } else if character.isWhitespace && !inQuotes {
                if hasToken { tokens.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }

    private static func isConcreteAlias(_ pattern: String) -> Bool {
        !pattern.isEmpty
            && !pattern.contains("*")
            && !pattern.contains("?")
            && !pattern.hasPrefix("!")
            && HostDraft.isSafeToken(pattern)
    }
}
