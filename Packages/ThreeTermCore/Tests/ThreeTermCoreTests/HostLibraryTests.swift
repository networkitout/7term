import Foundation
import Testing
@testable import ThreeTermCore

@Suite struct HostDraftTests {
    private func draft(name: String = "pve01", hostname: String = "10.0.0.21",
                       port: String = "", username: String = "", tags: String = "") -> HostDraft {
        var draft = HostDraft()
        draft.name = name
        draft.hostname = hostname
        draft.port = port
        draft.username = username
        draft.tags = tags
        return draft
    }

    @Test func minimalDraftIsValid() {
        #expect(draft().isValid)
        #expect(draft().target == SSHTarget(host: "10.0.0.21"))
    }

    @Test func fullDraftBuildsTarget() {
        let full = draft(hostname: " pve01.lab ", port: "2222", username: "root")
        #expect(full.target == SSHTarget(user: "root", host: "pve01.lab", port: 2222))
    }

    @Test func bracketedIPv6IsStoredBare() {
        #expect(draft(hostname: "[fe80::1]").target?.host == "fe80::1")
    }

    @Test func reportsEachBadField() {
        let bad = draft(name: "  ", hostname: "-oProxyCommand=x", port: "70000", username: "two words")
        #expect(bad.errors[.name] != nil)
        #expect(bad.errors[.hostname] != nil)
        #expect(bad.errors[.port] != nil)
        #expect(bad.errors[.username] != nil)
        #expect(bad.target == nil)
    }

    @Test func targetIgnoresMissingName() {
        let unnamed = draft(name: "", hostname: "pve01")
        #expect(!unnamed.isValid)
        #expect(unnamed.target == SSHTarget(host: "pve01"))
    }

    @Test func tagListTrimsAndDedupesIgnoringCase() {
        #expect(draft(tags: " proxmox, Lab ,,PROXMOX, lab ").tagList == ["proxmox", "Lab"])
    }
}

@Suite struct HostLibraryTests {
    private func draft(_ name: String, _ hostname: String, tags: String = "") -> HostDraft {
        var draft = HostDraft()
        draft.name = name
        draft.hostname = hostname
        draft.tags = tags
        return draft
    }

    @Test func savesAndListsSortedByName() throws {
        let library = try HostLibrary.inMemory()
        #expect(try library.isEmpty())
        try library.save(draft("pve02", "10.0.0.22"))
        try library.save(draft("Pve01", "10.0.0.21", tags: "proxmox"))

        let entries = try library.entries()
        #expect(entries.map(\.host.name) == ["Pve01", "pve02"])
        #expect(entries.first?.tags == ["proxmox"])
    }

    @Test func updateKeepsIdentityAndCreationDate() throws {
        let library = try HostLibrary.inMemory()
        let created = Date(timeIntervalSince1970: 1_000_000)
        let saved = try library.save(draft("pve01", "10.0.0.21"), now: created)

        var edit = HostDraft(entry: saved)
        edit.hostname = "10.0.0.99"
        let updated = try library.save(edit, id: saved.id, now: Date(timeIntervalSince1970: 2_000_000))

        #expect(updated.id == saved.id)
        let stored = try #require(try library.entries().first)
        #expect(stored.host.hostname == "10.0.0.99")
        #expect(stored.host.createdAt == created)
        #expect(try library.entries().count == 1)
    }

    @Test func tagsAreSharedIgnoringCaseAndPrunedWhenUnused() throws {
        let library = try HostLibrary.inMemory()
        let first = try library.save(draft("pve01", "10.0.0.21", tags: "Proxmox"))
        try library.save(draft("pve02", "10.0.0.22", tags: "proxmox"))
        #expect(try library.entries().allSatisfy { $0.tags == ["Proxmox"] })

        var retag = HostDraft(entry: first)
        retag.tags = "lab"
        try library.save(retag, id: first.id)
        try library.delete(id: try #require(try library.entries().first { $0.host.name == "pve02" }).id)

        #expect(try library.entries().map(\.tags) == [["lab"]])
    }

    @Test func invalidDraftThrows() throws {
        let library = try HostLibrary.inMemory()
        #expect(throws: HostLibraryError.invalidDraft) {
            try library.save(draft("", ""))
        }
    }

    @Test func duplicateCopiesTags() throws {
        let library = try HostLibrary.inMemory()
        let original = try library.save(draft("pve01", "10.0.0.21", tags: "proxmox"))
        let copy = try #require(try library.duplicate(id: original.id))
        #expect(copy.host.name == "pve01 copy")
        #expect(copy.id != original.id)
        #expect(copy.tags == ["proxmox"])
    }

    @Test func importSkipsHostnamesAlreadySaved() throws {
        let library = try HostLibrary.inMemory()
        try library.save(draft("Hypervisor", "PVE01"))
        let added = try library.importAliases([
            SSHConfigAlias(alias: "pve01"),
            SSHConfigAlias(alias: "pve02"),
        ])
        #expect(added == 1)
        #expect(try library.entries().map(\.host.hostname).sorted() == ["PVE01", "pve02"])
    }
}

@Suite struct HostFilterTests {
    private let entries = [
        HostEntry(host: SavedHost(name: "pve01", hostname: "10.0.0.21", username: "root"), tags: ["proxmox"]),
        HostEntry(host: SavedHost(name: "pve02", hostname: "10.0.0.22"), tags: ["proxmox", "lab"]),
        HostEntry(host: SavedHost(name: "k8s-1", hostname: "k8s-1.lab"), tags: []),
    ]

    @Test func emptyQueryMatchesEverything() {
        #expect(HostFilter.filter(entries, query: "  ").count == 3)
    }

    @Test func matchesTagPrefix() {
        #expect(HostFilter.filter(entries, query: "prox").map(\.host.name) == ["pve01", "pve02"])
    }

    @Test func everyWordMustMatch() {
        #expect(HostFilter.filter(entries, query: "PROX 22").map(\.host.name) == ["pve02"])
    }

    @Test func matchesUser() {
        #expect(HostFilter.filter(entries, query: "root").map(\.host.name) == ["pve01"])
    }

    @Test func sectionsPerTagThenUntagged() {
        let sections = HostFilter.sections(entries)
        #expect(sections.map(\.title) == ["lab", "proxmox", "Untagged"])
        #expect(sections[1].entries.map(\.host.name) == ["pve01", "pve02"])
        #expect(sections[2].entries.map(\.host.name) == ["k8s-1"])
    }
}
