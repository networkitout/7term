import Foundation
import Testing
@testable import SevenTermCore

@Suite struct SerialHostTests {
    private func serialDraft() -> HostDraft {
        var draft = HostDraft()
        draft.kind = .serial
        draft.name = "core-sw1 console"
        draft.serialPath = "/dev/cu.usbserial-A10K3B7"
        draft.serial = SerialHostDetails(
            settings: SerialSettings(baudRate: 9600),
            usbSerialNumber: "A10K3B7", vendorID: 0x0403, productID: 0x6001)
        draft.tags = "console, lab"
        draft.logByDefault = true
        return draft
    }

    @Test func validation() {
        var draft = serialDraft()
        #expect(draft.isValid)
        #expect(draft.target == nil) // never an ssh target
        draft.serialPath = ""
        #expect(draft.errors[.serialPort] != nil)
        draft.serialPath = "usbserial"
        #expect(draft.errors[.serialPort] != nil)
        draft = serialDraft()
        draft.serial.settings.dataBits = 9
        #expect(draft.errors[.serialSettings] != nil)
    }

    @Test func savesAndLoads() throws {
        let library = try HostLibrary.inMemory()
        let saved = try library.save(serialDraft())
        let entry = try #require(try library.entries().first)
        #expect(entry.id == saved.id)
        #expect(entry.host.kind == .serial)
        #expect(entry.host.hostname == "/dev/cu.usbserial-A10K3B7")
        #expect(entry.host.serial?.usbSerialNumber == "A10K3B7")
        #expect(entry.host.serial?.settings.summary == "9600 8N1")
        #expect(entry.tags == ["console", "lab"])
        #expect(entry.host.logByDefault)

        // Round trip through the form.
        let draft = HostDraft(entry: entry)
        #expect(draft.kind == .serial)
        #expect(draft.serialPath == "/dev/cu.usbserial-A10K3B7")
        #expect(draft.serial == entry.host.serial)
    }

    @Test func switchingToSSHClearsSerialDetails() throws {
        let library = try HostLibrary.inMemory()
        let saved = try library.save(serialDraft())
        var draft = HostDraft(entry: saved)
        draft.kind = .ssh
        draft.hostname = "10.0.0.5"
        try library.save(draft, id: saved.id)
        let entry = try #require(try library.entries().first)
        #expect(entry.host.kind == .ssh)
        #expect(entry.host.serial == nil)
        #expect(entry.host.hostname == "10.0.0.5")
    }

    @Test func backupCarriesSerialAndOldBackupsStillRead() throws {
        let library = try HostLibrary.inMemory()
        try library.save(serialDraft())
        let snapshot = BackupSnapshot(
            appVersion: "test", hosts: try library.entries(),
            settings: .init(paletteID: "7term", fontFamily: nil, fontSize: 13), importedPalettes: [])
        let decoded = try BackupSnapshot.decode(snapshot.encoded())
        #expect(decoded.hosts[0].kind == .serial)
        #expect(decoded.hosts[0].serial?.usbSerialNumber == "A10K3B7")

        let restoredInto = try HostLibrary.inMemory()
        #expect(try restoredInto.restore(decoded.hosts) == 1)
        #expect(try restoredInto.entries().first?.host.serial?.settings.baudRate == 9600)

        // A backup written before serial support has no "kind": it's ssh.
        var json = try JSONSerialization.jsonObject(with: snapshot.encoded()) as! [String: Any]
        var hosts = json["hosts"] as! [[String: Any]]
        hosts[0].removeValue(forKey: "kind")
        hosts[0].removeValue(forKey: "serial")
        hosts[0]["hostname"] = "10.0.0.9"
        json["hosts"] = hosts
        let old = try BackupSnapshot.decode(JSONSerialization.data(withJSONObject: json))
        #expect(old.hosts[0].kind == nil)
        #expect(old.hosts[0].savedHost.kind == .ssh)
    }
}
