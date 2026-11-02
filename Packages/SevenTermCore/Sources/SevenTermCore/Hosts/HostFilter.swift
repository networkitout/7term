import Foundation

/// Type-to-filter and the tag filter for the sidebar.
public enum HostFilter {
    /// Every whitespace-separated word must appear (ignoring case and
    /// accents) in the host's name, hostname, user, or one of its tags.
    /// So "prox" finds the hypervisors and "prox 21" narrows to one.
    public static func matches(_ entry: HostEntry, query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let fields = [entry.host.name, entry.host.hostname, entry.host.username ?? ""] + entry.tags
        return words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    public static func filter(_ entries: [HostEntry], query: String) -> [HostEntry] {
        entries.filter { matches($0, query: query) }
    }

    /// Every tag in use, once, in name order (first spelling wins).
    public static func tags(in entries: [HostEntry]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in entries.flatMap(\.tags) where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Hosts carrying `tag` (ignoring case) that also match `query`.
    /// A nil tag means every host. Each host appears once.
    public static func filter(_ entries: [HostEntry], query: String, tag: String?) -> [HostEntry] {
        filter(entries, query: query).filter { entry in
            guard let tag else { return true }
            return entry.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }
}
