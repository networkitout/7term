import Foundation
import Testing
@testable import SevenTermCore

@Suite struct BackupTests {
    private func library(with names: [String]) throws -> HostLibrary {
        let library = try HostLibrary.inMemory()
        for (index, name) in names.enumerated() {
            var draft = HostDraft()
            draft.name = name
            draft.hostname = "10.0.0.\(index + 10)"
            draft.tags = "lab"
            if index == 0 {
                draft.authMethod = .keyFile
                draft.identityFile = "~/.ssh/id_lab"
            }
            // Whole seconds: backups store times to the second.
            try library.save(draft, now: Date(timeIntervalSince1970: 1_793_500_000))
        }
        return library
    }

    private func snapshot(_ library: HostLibrary, at date: Date = Date(timeIntervalSince1970: 1_793_563_200)) throws -> BackupSnapshot {
        BackupSnapshot(
            exportedAt: date,
            appVersion: "0.1.0",
            hosts: try library.entries(),
            settings: .init(paletteID: "7term", fontFamily: nil, fontSize: 14),
            importedPalettes: []
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let original = try snapshot(library(with: ["pve01", "pve02"]))
        let decoded = try BackupSnapshot.decode(original.encoded())
        #expect(decoded == original)
        #expect(decoded.hosts.first?.identityFile == "~/.ssh/id_lab")
    }

    @Test func containsNoPasswordField() throws {
        let json = try String(decoding: snapshot(library(with: ["pve01"])).encoded(), as: UTF8.self)
        #expect(!json.lowercased().contains("password\""))
    }

    @Test func restoreAddsMissingHostsOnlyAndKeepsIdentity() throws {
        let source = try library(with: ["pve01", "pve02"])
        let backup = try snapshot(source)

        let target = try library(with: ["other"])
        let firstBackedUp = try #require(backup.hosts.first)
        #expect(try target.restore(backup.hosts) == 2)
        #expect(try target.restore(backup.hosts) == 0)

        let restored = try #require(try target.entries().first { $0.id == firstBackedUp.id })
        #expect(restored.host.name == firstBackedUp.name)
        #expect(restored.tags == ["lab"])
        #expect(restored.host.createdAt == firstBackedUp.createdAt)
        #expect(try target.entries().count == 3)
    }

    @Test func rejectsOtherFilesAndNewerFormats() throws {
        #expect(throws: BackupSnapshot.ReadError.notABackup) {
            _ = try BackupSnapshot.decode(Data("{}".utf8))
        }
        var future = try snapshot(library(with: []))
        future.formatVersion = 99
        #expect(throws: BackupSnapshot.ReadError.newerFormat(99)) {
            _ = try BackupSnapshot.decode(future.encoded())
        }
    }

    @Test func storeKeepsOneCopyPerDayAndTrimsOldOnes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "7term-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
        var store = BackupStore(folder: folder)
        store.keepDays = 2
        let library = try library(with: ["pve01"])
        let day: TimeInterval = 86_400
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))

        for offset in [0.0, 0.5, 1, 2] {
            try store.write(snapshot(library, at: Date(timeIntervalSince1970: 1_793_563_200 + offset * day)), calendar: calendar)
        }
        let copies = try FileManager.default.contentsOfDirectory(atPath: store.historyFolder.path).sorted()
        #expect(copies == ["7term-backup-2026-11-02.json", "7term-backup-2026-11-03.json"])
        #expect(FileManager.default.fileExists(atPath: store.latestURL.path))
    }
}
