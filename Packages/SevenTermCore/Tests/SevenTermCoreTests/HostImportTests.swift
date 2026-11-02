import Foundation
import Testing
@testable import SevenTermCore

@Suite struct HostImportTests {
    @Test func csvWithHeader() {
        let table = HostImportTable.parse("""
            Name,IP Address,Port,User,Tags
            pve1,192.168.1.10,22,root,proxmox;lab
            "web, prod",10.0.0.5,2222,deploy,"prod, web"
            """)
        #expect(table.header == ["Name", "IP Address", "Port", "User", "Tags"])
        #expect(table.columns == [.name, .host, .port, .user, .tags])
        #expect(table.rows.count == 2)
        #expect(table.rows[1][0] == "web, prod")

        let candidates = table.candidates(existing: [], tag: "imported")
        #expect(candidates.allSatisfy { $0.isImportable })
        #expect(candidates[0].draft.name == "pve1")
        #expect(candidates[0].draft.tagList == ["proxmox", "lab", "imported"])
        #expect(candidates[1].draft.port == "2222")
        #expect(candidates[1].draft.tagList == ["prod", "web", "imported"])
        #expect(candidates[1].line == 3)
    }

    /// What lands on the clipboard when you copy cells in Excel or Numbers.
    @Test func pastedSpreadsheetCells() {
        let table = HostImportTable.parse("hostname\tuser\r\nvm-a.lab\tlaremy\r\nvm-b.lab\tlaremy\r\n")
        #expect(table.columns == [.host, .user])
        #expect(table.rows == [["vm-a.lab", "laremy"], ["vm-b.lab", "laremy"]])
        let candidates = table.candidates(existing: [])
        #expect(candidates.map(\.draft.name) == ["vm-a.lab", "vm-b.lab"])
    }

    @Test func semicolonsFromEuropeanExcel() {
        let table = HostImportTable.parse("Host;Port\n10.1.1.1;2200\n")
        #expect(table.columns == [.host, .port])
        #expect(table.rows == [["10.1.1.1", "2200"]])
    }

    @Test func passwordColumnsAreNeverRead() {
        let table = HostImportTable.parse("""
            host,user,Password (root),secret
            10.0.0.1,root,hunter2,abc
            """)
        #expect(table.secretColumns == [2, 3])
        #expect(table.columns[2] == .ignore && table.columns[3] == .ignore)

        var remapped = table
        remapped.columns[2] = .name // even if someone maps it
        let draft = remapped.candidates(existing: [])[0].draft
        #expect(draft.name == "10.0.0.1")
        #expect(!String(describing: draft).contains("hunter2"))
    }

    @Test func noHeaderGuessesColumns() {
        let table = HostImportTable.parse("""
            pve1,192.168.1.10,22
            pve2,192.168.1.11,22
            """)
        #expect(table.header == nil)
        #expect(table.columns == [.name, .host, .port])
    }

    @Test func singleColumnIsHosts() {
        let table = HostImportTable.parse("a.lab\nb.lab\n\n")
        #expect(table.columns == [.host])
        #expect(table.rows.count == 2)
    }

    @Test func userAtHostPortInOneCell() {
        let table = HostImportTable.parse("host\nadmin@10.0.0.9:2022\n[fe80::1]:22\n")
        let candidates = table.candidates(existing: [])
        #expect(candidates[0].draft.hostname == "10.0.0.9")
        #expect(candidates[0].draft.username == "admin")
        #expect(candidates[0].draft.port == "2022")
        #expect(candidates[1].draft.hostname == "fe80::1")
    }

    @Test func badRowsExplainThemselves() {
        let table = HostImportTable.parse("host,port\n10.0.0.1,99999\n-oProxyCommand=x,22\n,22\n")
        let candidates = table.candidates(existing: [])
        #expect(candidates.count == 3)
        #expect(!candidates[0].isImportable)
        #expect(candidates[0].problems.contains { $0.contains("Port") })
        #expect(!candidates[1].isImportable)
        #expect(!candidates[2].isImportable)
    }

    @Test func duplicatesWithinTheFile() {
        let table = HostImportTable.parse("host,port\npve1,22\nPVE1,\npve1,2222\n")
        let candidates = table.candidates(existing: [])
        #expect(candidates[0].isImportable)
        #expect(candidates[1].duplicateOfLine == 2) // port 22 and no port are the same
        #expect(candidates[2].isImportable)
    }

    @Test func quotedNewlinesAndEscapedQuotes() {
        let table = HostImportTable.parse("name,host\n\"say \"\"hi\"\"\nthere\",h1\nplain,h2\n")
        #expect(table.rows[0][0] == "say \"hi\"\nthere")
        #expect(table.lineNumbers == [2, 4])
    }

    @Test func keyFileColumnSetsAuth() {
        let draft = HostImportTable.parse("host,identityfile\nh1,~/.ssh/id_lab\n").candidates(existing: [])[0].draft
        #expect(draft.authMethod == .keyFile)
        #expect(draft.identityFile == "~/.ssh/id_lab")
    }

    @Test func importSkipsOrMergesExisting() throws {
        let library = try HostLibrary.inMemory()
        var draft = HostDraft()
        draft.name = "pve1"
        draft.hostname = "192.168.1.10"
        draft.tags = "proxmox"
        draft.logByDefault = true
        let saved = try library.save(draft)

        let table = HostImportTable.parse("""
            name,host,user,tags
            Proxmox 1,192.168.1.10,,lab
            pve2,192.168.1.11,root,lab
            """)
        let candidates = table.candidates(existing: try library.entries())
        #expect(candidates[0].existingID == saved.id)
        #expect(candidates[1].existingID == nil)

        let skipped = try library.importHosts(candidates, updateExisting: false)
        #expect(skipped.added == 1 && skipped.updated == 0)
        #expect(try library.entries().count == 2)

        let merged = try library.importHosts([candidates[0]], updateExisting: true)
        #expect(merged.updated == 1)
        let entry = try #require(try library.entries().first { $0.id == saved.id })
        #expect(entry.host.name == "Proxmox 1")
        #expect(entry.tags.sorted() == ["lab", "proxmox"])
        #expect(entry.host.logByDefault) // untouched
    }
}
