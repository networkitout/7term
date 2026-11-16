import Foundation
import GRDB
import Testing
@testable import SevenTermCore

@Suite struct HostFolderTests {
    private func savedHost(_ library: HostLibrary, _ name: String) throws -> String {
        var draft = HostDraft()
        draft.name = name
        draft.hostname = "\(name).lab"
        return try library.save(draft).id
    }

    @Test func cleanNameRules() {
        #expect(HostFolder.cleanName("  Lab ") == "Lab")
        #expect(HostFolder.cleanName("") == nil)
        #expect(HostFolder.cleanName("   ") == nil)
        #expect(HostFolder.cleanName("a/b") == nil)
        #expect(HostFolder.cleanName(String(repeating: "x", count: 61)) == nil)
        #expect(HostFolder.cleanName(String(repeating: "x", count: 60)) != nil)
    }

    @Test func createAndList() throws {
        let library = try HostLibrary.inMemory()
        let work = try library.createFolder(name: "Work", parentId: nil)
        let core = try library.createFolder(name: "Core", parentId: work.id)
        let folders = try library.folders()
        #expect(folders.count == 2)
        #expect(folders.first { $0.id == core.id }?.parentId == work.id)
    }

    @Test func siblingNamesAreUniqueIgnoringCase() throws {
        let library = try HostLibrary.inMemory()
        let work = try library.createFolder(name: "Work", parentId: nil)
        #expect(throws: HostLibraryError.duplicateFolderName) {
            try library.createFolder(name: "work", parentId: nil)
        }
        try library.createFolder(name: "Lab", parentId: work.id)
        #expect(throws: HostLibraryError.duplicateFolderName) {
            try library.createFolder(name: "LAB", parentId: work.id)
        }
        try library.createFolder(name: "Work", parentId: work.id)
    }

    @Test func createInMissingParentThrows() throws {
        let library = try HostLibrary.inMemory()
        #expect(throws: HostLibraryError.folderNotFound) {
            try library.createFolder(name: "X", parentId: "nope")
        }
    }

    @Test func renameChecksNameAndSiblings() throws {
        let library = try HostLibrary.inMemory()
        let work = try library.createFolder(name: "Work", parentId: nil)
        try library.createFolder(name: "Home", parentId: nil)
        #expect(throws: HostLibraryError.invalidFolderName) {
            try library.renameFolder(id: work.id, to: "a/b")
        }
        #expect(throws: HostLibraryError.duplicateFolderName) {
            try library.renameFolder(id: work.id, to: "home")
        }
        try library.renameFolder(id: work.id, to: "WORK")
        #expect(try library.folders().contains { $0.name == "WORK" })
    }

    @Test func moveFolderRejectsCycles() throws {
        let library = try HostLibrary.inMemory()
        let a = try library.createFolder(name: "A", parentId: nil)
        let b = try library.createFolder(name: "B", parentId: a.id)
        let c = try library.createFolder(name: "C", parentId: b.id)
        for target in [a.id, b.id, c.id] {
            #expect(throws: HostLibraryError.folderCycle) {
                try library.moveFolder(id: a.id, toParent: target)
            }
        }
        try library.moveFolder(id: c.id, toParent: nil)
        #expect(try library.folders().first { $0.id == c.id }?.parentId == nil)
    }

    @Test func moveFolderIntoLoopedDestinationReturns() throws {
        let library = try HostLibrary.inMemory()
        let a = try library.createFolder(name: "A", parentId: nil)
        let b = try library.createFolder(name: "B", parentId: nil)
        let c = try library.createFolder(name: "C", parentId: nil)
        try library.database.write { db in
            try db.execute(sql: "UPDATE folder SET parentId = ? WHERE id = ?", arguments: [b.id, a.id])
            try db.execute(sql: "UPDATE folder SET parentId = ? WHERE id = ?", arguments: [a.id, b.id])
        }
        try library.moveFolder(id: c.id, toParent: a.id)
        #expect(try library.folders().first { $0.id == c.id }?.parentId == a.id)
    }

    @Test func moveFolderIntoSiblingNameClashThrows() throws {
        let library = try HostLibrary.inMemory()
        let parent = try library.createFolder(name: "Parent", parentId: nil)
        try library.createFolder(name: "lab", parentId: parent.id)
        let lab = try library.createFolder(name: "Lab", parentId: nil)
        #expect(throws: HostLibraryError.duplicateFolderName) {
            try library.moveFolder(id: lab.id, toParent: parent.id)
        }
    }

    @Test func moveHost() throws {
        let library = try HostLibrary.inMemory()
        let folder = try library.createFolder(name: "Work", parentId: nil)
        let id = try savedHost(library, "h1")
        try library.moveHost(id: id, toFolder: folder.id)
        #expect(try library.entries().first?.host.folderId == folder.id)
        try library.moveHost(id: id, toFolder: nil)
        #expect(try library.entries().first?.host.folderId == nil)
        #expect(throws: HostLibraryError.folderNotFound) {
            try library.moveHost(id: id, toFolder: "nope")
        }
    }

    @Test func deleteMovesContentsUp() throws {
        let library = try HostLibrary.inMemory()
        let work = try library.createFolder(name: "Work", parentId: nil)
        let core = try library.createFolder(name: "Core", parentId: work.id)
        let h1 = try savedHost(library, "h1")
        let h2 = try savedHost(library, "h2")
        try library.moveHost(id: h1, toFolder: work.id)
        try library.moveHost(id: h2, toFolder: core.id)
        try library.deleteFolder(id: work.id)
        let folders = try library.folders()
        #expect(folders.count == 1)
        #expect(folders.first { $0.id == core.id }?.parentId == nil)
        let entries = try library.entries()
        #expect(entries.count == 2)
        #expect(entries.first { $0.id == h1 }?.host.folderId == nil)
        #expect(entries.first { $0.id == h2 }?.host.folderId == core.id)
    }

    @Test func deleteRenamesOnNameClash() throws {
        let library = try HostLibrary.inMemory()
        try library.createFolder(name: "Lab", parentId: nil)
        let work = try library.createFolder(name: "Work", parentId: nil)
        try library.createFolder(name: "Lab", parentId: work.id)
        try library.deleteFolder(id: work.id)
        let folders = try library.folders()
        #expect(folders.map(\.name) == ["Lab", "Lab 2"])
        #expect(folders.allSatisfy { $0.parentId == nil })
    }

    @Test func deleteClashSuffixStaysWithinSixtyCharacters() throws {
        let library = try HostLibrary.inMemory()
        let name = String(repeating: "n", count: 60)
        let top = try library.createFolder(name: name, parentId: nil)
        let work = try library.createFolder(name: "Work", parentId: nil)
        let inner = try library.createFolder(name: name, parentId: work.id)
        try library.deleteFolder(id: work.id)
        let folders = try library.folders()
        #expect(folders.count == 2)
        #expect(folders.first { $0.id == top.id }?.name == name)
        let moved = try #require(folders.first { $0.id == inner.id })
        #expect(moved.parentId == nil)
        #expect(moved.name.hasSuffix(" 2"))
        #expect(moved.name.count == 60)
    }

    @Test func ensureFolderReusesAndCreates() throws {
        let library = try HostLibrary.inMemory()
        let first = try library.ensureFolder(path: ["Work", "Core"])
        let second = try library.ensureFolder(path: ["Work", "Core"])
        #expect(first != nil)
        #expect(first == second)
        #expect(try library.folders().count == 2)
        #expect(try library.ensureFolder(path: ["work", "CORE"]) == first)
        #expect(try library.ensureFolder(path: []) == nil)
    }

    @Test func hostsStartAtTopLevel() throws {
        let library = try HostLibrary.inMemory()
        _ = try savedHost(library, "a")
        _ = try savedHost(library, "b")
        let entries = try library.entries()
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.host.folderId == nil })
        #expect(try library.folders().isEmpty)
    }

    @Test func reopeningKeepsFolders() throws {
        let queue = try DatabaseQueue()
        let first = try HostLibrary(queue)
        let folder = try first.createFolder(name: "Work", parentId: nil)
        let id = try savedHost(first, "h1")
        try first.moveHost(id: id, toFolder: folder.id)
        let second = try HostLibrary(queue)
        let reopened = try second.folders()
        // Dates are stored to the millisecond, so compare the identifying fields.
        #expect(reopened.map(\.id) == [folder.id])
        #expect(reopened.map(\.name) == ["Work"])
        #expect(reopened.map(\.parentId) == [nil])
        #expect(try second.entries().first?.host.folderId == folder.id)
    }

    @Test func saveKeepsFolder() throws {
        let library = try HostLibrary.inMemory()
        let folder = try library.createFolder(name: "Work", parentId: nil)
        var draft = HostDraft()
        draft.name = "h1"
        draft.hostname = "h1.lab"
        draft.folderId = folder.id
        let saved = try library.save(draft)
        #expect(saved.host.folderId == folder.id)

        var edit = HostDraft(entry: saved)
        #expect(edit.folderId == folder.id)
        edit.name = "h1 renamed"
        let edited = try library.save(edit, id: saved.id)
        #expect(edited.host.folderId == folder.id)
        #expect(try library.entries().first?.host.folderId == folder.id)
    }

    @Test func savingExistingHostWithNilFolderMovesItToTopLevel() throws {
        let library = try HostLibrary.inMemory()
        let folder = try library.createFolder(name: "Work", parentId: nil)
        var draft = HostDraft()
        draft.name = "h1"
        draft.hostname = "h1.lab"
        draft.folderId = folder.id
        let saved = try library.save(draft)
        #expect(saved.host.folderId == folder.id)

        var edit = HostDraft(entry: saved)
        edit.folderId = nil
        let edited = try library.save(edit, id: saved.id)
        #expect(edited.host.folderId == nil)
        #expect(try library.entries().first { $0.id == saved.id }?.host.folderId == nil)
    }

    @Test func saveSerialKeepsFolder() throws {
        let library = try HostLibrary.inMemory()
        let folder = try library.createFolder(name: "Work", parentId: nil)
        var draft = HostDraft()
        draft.name = "console"
        draft.kind = .serial
        draft.serialPath = "/dev/cu.usbserial-1"
        draft.folderId = folder.id
        let saved = try library.save(draft)
        #expect(saved.host.folderId == folder.id)

        var edit = HostDraft(entry: saved)
        edit.name = "console 2"
        let edited = try library.save(edit, id: saved.id)
        #expect(edited.host.folderId == folder.id)
    }

    @Test func saveWithUnknownFolderGoesToTopLevel() throws {
        let library = try HostLibrary.inMemory()
        var draft = HostDraft()
        draft.name = "h1"
        draft.hostname = "h1.lab"
        draft.folderId = "nope"
        let saved = try library.save(draft)
        #expect(saved.host.folderId == nil)
    }

    @Test func duplicateStaysInFolder() throws {
        let library = try HostLibrary.inMemory()
        let folder = try library.createFolder(name: "Work", parentId: nil)
        let id = try savedHost(library, "h1")
        try library.moveHost(id: id, toFolder: folder.id)
        let copy = try #require(try library.duplicate(id: id))
        #expect(copy.host.folderId == folder.id)
    }
}
