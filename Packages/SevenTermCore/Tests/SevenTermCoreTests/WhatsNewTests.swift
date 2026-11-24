import Foundation
import Testing
@testable import SevenTermCore

@Suite struct WhatsNewTests {
    private let entries = [
        WhatsNewEntry(version: "1.5.0", items: [.init(title: "Side by side", detail: "Two tabs.")]),
        WhatsNewEntry(version: "1.6.0", items: [.init(title: "What's New", detail: "This sheet.")]),
        WhatsNewEntry(version: "1.10.0", items: [.init(title: "Later", detail: "Not yet.")]),
    ]

    @Test func versionsCompareByNumbers() {
        #expect(WhatsNew.compare("1.10.0", "1.9.0") == .orderedDescending)
        #expect(WhatsNew.compare("1.6", "1.6.0") == .orderedSame)
        #expect(WhatsNew.compare("1.5.0", "1.6.0") == .orderedAscending)
        #expect(WhatsNew.compare("2.0.0", "1.99.99") == .orderedDescending)
    }

    @Test func freshInstallShowsNothing() {
        #expect(WhatsNew.entriesToShow(entries, lastSeen: nil, current: "1.6.0", isExistingUser: false).isEmpty)
    }

    @Test func existingUserWithNoRecordSeesEverythingUpToThisVersion() {
        let shown = WhatsNew.entriesToShow(entries, lastSeen: nil, current: "1.6.0", isExistingUser: true)
        #expect(shown.map(\.version) == ["1.6.0", "1.5.0"])
    }

    @Test func showsOnlyVersionsNewerThanTheLastSeen() {
        #expect(WhatsNew.entriesToShow(entries, lastSeen: "1.5.0", current: "1.6.0", isExistingUser: true).map(\.version) == ["1.6.0"])
        #expect(WhatsNew.entriesToShow(entries, lastSeen: "1.4.0", current: "1.6.0", isExistingUser: true).map(\.version) == ["1.6.0", "1.5.0"])
    }

    @Test func sameVersionAgainShowsNothing() {
        #expect(WhatsNew.entriesToShow(entries, lastSeen: "1.6.0", current: "1.6.0", isExistingUser: true).isEmpty)
    }

    @Test func aDowngradeShowsNothing() {
        #expect(WhatsNew.entriesToShow(entries, lastSeen: "1.10.0", current: "1.6.0", isExistingUser: true).isEmpty)
    }

    @Test func historyIsEverythingUpToThisVersionNewestFirst() {
        #expect(WhatsNew.history(entries, current: "1.6.0").map(\.version) == ["1.6.0", "1.5.0"])
    }

    @Test func decodesTheBundledFormat() throws {
        let json = #"[{"version": "1.6.0", "items": [{"title": "T", "detail": "D"}]}]"#
        let decoded = try WhatsNew.decode(Data(json.utf8))
        #expect(decoded == [WhatsNewEntry(version: "1.6.0", items: [.init(title: "T", detail: "D")])])
    }
}
