import Foundation

/// What a terminal tab types when files are dropped on it: each path escaped
/// for a shell the way Terminal does, separated by spaces, with a space after
/// the last so the next word can follow. Return is never part of it.
public enum DroppedPaths {
    /// Nil when any path holds a control character: typed into a terminal,
    /// those act as they arrive (^U erases the line, CR submits it), whatever
    /// quoting surrounds them, so a crafted file name could run a command.
    public static func typedText(for paths: [String]) -> String? {
        guard !paths.contains(where: hasControlCharacter) else { return nil }
        return paths.map(escape).map { $0 + " " }.joined()
    }

    /// C0 controls, DEL and C1 controls. Format characters such as the
    /// zero-width joiner inside some emoji are fine.
    static func hasControlCharacter(_ path: String) -> Bool {
        path.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }
    }

    /// A backslash before anything a shell treats specially.
    static func escape(_ path: String) -> String {
        var result = ""
        for scalar in path.unicodeScalars {
            if !isSafe(scalar) { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private static let safeASCII = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./,:+@%=^".unicodeScalars)

    /// ASCII letters, digits and a few harmless marks; anything beyond ASCII
    /// except spaces (Terminal leaves letters like é and emoji alone).
    private static func isSafe(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII { return safeASCII.contains(scalar) }
        return !scalar.properties.isWhitespace
    }
}

/// What a row dragged from the file browser's host pane carries: the browser
/// it came from and the path on the server.
public enum RemoteDragPayload {
    static let prefix = "7term-remote:"

    public static func make(browserID: UUID, path: String) -> String {
        "\(prefix)\(browserID.uuidString):\(path)"
    }

    /// Nil for anything that isn't a payload with a browser id and a path.
    public static func parse(_ text: String) -> (browserID: UUID, path: String)? {
        guard text.hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        guard let colon = rest.firstIndex(of: ":"),
              let id = UUID(uuidString: String(rest[..<colon])) else { return nil }
        let path = String(rest[rest.index(after: colon)...])
        return path.isEmpty ? nil : (id, path)
    }
}

extension SSHTarget {
    /// Whether two targets reach the same account on the same machine: host and
    /// user compared without regard to case, no port meaning 22. The key file
    /// doesn't matter.
    public func isSameMachine(as other: SSHTarget) -> Bool {
        host.caseInsensitiveCompare(other.host) == .orderedSame
            && (user?.lowercased() == other.user?.lowercased())
            && (port ?? 22) == (other.port ?? 22)
    }
}
