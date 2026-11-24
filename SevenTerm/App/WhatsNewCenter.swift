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

    /// At launch: shows what changed since the last version shown. This
    /// version is remembered once the sheet closes (straight away when there's
    /// nothing to show), and the remembered version never goes down.
    /// `isExistingUser` must be worked out before anything first-run marks the
    /// app as used.
    func checkAtLaunch(isExistingUser: Bool) {
        let all = Self.bundledEntries
        // Unreadable notes: remember nothing, so a fixed file in the next
        // release still shows them.
        guard !all.isEmpty else { return }
        let lastSeen = UserDefaults.standard.string(forKey: Self.lastSeenKey)
        let entries = WhatsNew.entriesToShow(all, lastSeen: lastSeen, current: Self.currentVersion, isExistingUser: isExistingUser)
        guard !entries.isEmpty else {
            rememberCurrentVersion()
            return
        }
        shown = Presentation(title: "What's New in 7 Term \(Self.currentVersion)", entries: entries)
    }

    /// The launch sheet closed.
    func dismiss() {
        shown = nil
        rememberCurrentVersion()
    }

    private func rememberCurrentVersion() {
        let defaults = UserDefaults.standard
        let version = WhatsNew.versionToRemember(lastSeen: defaults.string(forKey: Self.lastSeenKey), current: Self.currentVersion)
        defaults.set(version, forKey: Self.lastSeenKey)
    }

    /// Help ▸ What's New: every version's notes up to this one. A local build
    /// (whose version predates every entry) shows them all.
    static var history: [WhatsNewEntry] {
        let all = bundledEntries
        let entries = WhatsNew.history(all, current: currentVersion)
        return entries.isEmpty ? WhatsNew.history(all, current: "999") : entries
    }
}
