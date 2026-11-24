import Foundation
import Observation
import SevenTermCore

/// Decides when the What's New sheet appears and what it lists. The notes
/// are in WhatsNew.json in the app; the last version shown is remembered in
/// the app's settings.
@MainActor
@Observable
final class WhatsNewCenter {
    /// Set to show the sheet; nil when it's closed.
    var shown: Presentation?

    struct Presentation: Identifiable {
        let id = UUID()
        let title: String
        let entries: [WhatsNewEntry]
    }

    private static let lastSeenKey = "whatsNewLastSeenVersion"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The notes in the app, or none if the file is missing or unreadable.
    static var bundledEntries: [WhatsNewEntry] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? WhatsNew.decode(data)
        else { return [] }
        return entries
    }

    /// At launch: shows what changed since the last version shown, then
    /// remembers this version. `isExistingUser` must be worked out before
    /// anything first-run marks the app as used.
    func checkAtLaunch(isExistingUser: Bool) {
        let defaults = UserDefaults.standard
        let current = Self.currentVersion
        let entries = WhatsNew.entriesToShow(
            Self.bundledEntries,
            lastSeen: defaults.string(forKey: Self.lastSeenKey),
            current: current,
            isExistingUser: isExistingUser
        )
        defaults.set(current, forKey: Self.lastSeenKey)
        guard !entries.isEmpty else { return }
        shown = Presentation(title: "What's New in 7 Term \(current)", entries: entries)
    }

    /// Help ▸ What's New: every version's notes up to this one. A local build
    /// (whose version predates every entry) shows them all.
    func showHistory() {
        let all = Self.bundledEntries
        var entries = WhatsNew.history(all, current: Self.currentVersion)
        if entries.isEmpty { entries = WhatsNew.history(all, current: "999") }
        shown = Presentation(title: "What's New in 7 Term", entries: entries)
    }
}
