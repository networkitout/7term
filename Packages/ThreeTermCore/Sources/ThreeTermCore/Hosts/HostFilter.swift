import Foundation

/// Type-to-filter and tag grouping for the sidebar.
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

    public struct Section: Hashable, Sendable, Identifiable {
        /// The tag, or nil for hosts without tags.
        public var tag: String?
        public var entries: [HostEntry]
        public var id: String { tag.map { "tag:" + $0.lowercased() } ?? "untagged" }
        public var title: String { tag ?? "Untagged" }
    }

    /// One section per tag in name order, then "Untagged". A host with two
    /// tags appears in both sections.
    public static func sections(_ entries: [HostEntry]) -> [Section] {
        var byTag: [String: (title: String, entries: [HostEntry])] = [:]
        var untagged: [HostEntry] = []
        for entry in entries {
            if entry.tags.isEmpty {
                untagged.append(entry)
            }
            for tag in entry.tags {
                byTag[tag.lowercased(), default: (tag, [])].entries.append(entry)
            }
        }
        var sections = byTag.values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { Section(tag: $0.title, entries: $0.entries) }
        if !untagged.isEmpty {
            sections.append(Section(tag: nil, entries: untagged))
        }
        return sections
    }
}
