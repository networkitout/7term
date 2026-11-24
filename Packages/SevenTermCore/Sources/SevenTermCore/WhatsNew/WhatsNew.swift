import Foundation

/// One release's notes for the What's New sheet: a few features, each a
/// title and a sentence or two, written for people using the app.
public struct WhatsNewEntry: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var title: String
        public var detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public var version: String
    public var items: [Item]

    public init(version: String, items: [Item]) {
        self.version = version
        self.items = items
    }
}

/// Which release notes to show, and when.
public enum WhatsNew {
    public static func decode(_ data: Data) throws -> [WhatsNewEntry] {
        try JSONDecoder().decode([WhatsNewEntry].self, from: data)
    }

    /// The notes to show at launch, newest first: every version after the
    /// last one shown, up to and including the running one. A fresh install
    /// shows nothing. An existing user with no record (updated from a version
    /// before this sheet existed) sees every entry up to the running version.
    public static func entriesToShow(
        _ entries: [WhatsNewEntry], lastSeen: String?, current: String, isExistingUser: Bool
    ) -> [WhatsNewEntry] {
        if lastSeen == nil && !isExistingUser { return [] }
        return history(entries, current: current).filter { entry in
            guard let lastSeen else { return true }
            return compare(entry.version, lastSeen) == .orderedDescending
        }
    }

    /// Help ▸ What's New: every entry up to the running version, newest first.
    public static func history(_ entries: [WhatsNewEntry], current: String) -> [WhatsNewEntry] {
        entries
            .filter { compare($0.version, current) != .orderedDescending }
            .sorted { compare($0.version, $1.version) == .orderedDescending }
    }

    /// Versions compared number by number, so 1.10 comes after 1.9 and a
    /// missing part counts as 0 (1.6 = 1.6.0).
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let left = parts(a), right = parts(b)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
