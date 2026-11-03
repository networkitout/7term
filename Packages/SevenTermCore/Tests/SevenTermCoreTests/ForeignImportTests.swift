import Foundation
import Testing
@testable import SevenTermCore

@Suite struct ForeignImportTests {
    @Test func secureCRTSessionsFolder() {
        let core = """
            S:"Protocol Name"=SSH2
            S:"Hostname"=10.0.0.1
            S:"Username"=admin
            D:"[SSH2] Port"=00000016
            S:"Identity Filename V2"=/Users/me/.ssh/id_lab::rawkey
            """
        let pve = """
            S:"Protocol Name"=SSH2
            S:"Hostname"=pve1.lab
            D:"[SSH2] Port"=000008ae
            """
        let telnet = """
            S:"Protocol Name"=Telnet
            S:"Hostname"=10.0.0.9
            """
        let result = SecureCRTImport.parse(files: [
            ("Network/Core/core-sw1.ini", core),
            ("Lab/pve1.ini", pve),
            ("Lab/__FolderData__.ini", "S:\"Folder List\"="),
            ("old-router.ini", telnet),
            ("Default.ini", core),
        ])
        #expect(result.hosts.count == 2)
        let sw = result.hosts.first { $0.name == "core-sw1" }
        #expect(sw?.host == "10.0.0.1")
        #expect(sw?.user == "admin")
        #expect(sw?.port == nil) // 22 is the default
        #expect(sw?.tags == ["Network", "Core"])
        #expect(sw?.keyFile == "/Users/me/.ssh/id_lab")
        #expect(result.hosts.first { $0.name == "pve1" }?.port == 2222)
        #expect(result.skipped == ["old-router: Telnet session"])
    }

    @Test func puttyRegistryExport() {
        let reg = """
            Windows Registry Editor Version 5.00

            [HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\Default%20Settings]
            "HostName"=""

            [HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\core%20switch]
            "HostName"="10.0.0.1"
            "PortNumber"=dword:00000016
            "UserName"="admin"
            "Protocol"="ssh"
            "PublicKeyFile"="C:\\\\Users\\\\me\\\\key.ppk"

            [HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\pi]
            "HostName"="pi@raspberrypi.local"
            "PortNumber"=dword:00000016
            "Protocol"="ssh"

            [HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\console]
            "Protocol"="serial"
            """
        let result = PuTTYImport.parse(reg)
        #expect(result.hosts.map(\.name) == ["core switch", "pi"])
        #expect(result.hosts[0].user == "admin")
        #expect(result.hosts[0].keyFile == nil) // a Windows path is no use on a Mac
        #expect(result.skipped == ["console: serial session"])

        // user@host in HostName becomes the user once checked.
        let candidates = result.table.candidates(existing: [])
        #expect(candidates[1].draft.username == "pi")
        #expect(candidates[1].draft.hostname == "raspberrypi.local")
    }

    @Test func puttyExportInUTF16() {
        let text = "Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software\\9bis.com\\KiTTY\\Sessions\\box]\r\n\"HostName\"=\"box.lab\"\r\n"
        var data = Data([0xFF, 0xFE])
        data.append(text.data(using: .utf16LittleEndian)!)
        let decoded = decodeExportText(data)
        #expect(ForeignImportFormat.detect(fileName: "kitty.reg", text: decoded) == .putty)
        #expect(PuTTYImport.parse(decoded).hosts.first?.host == "box.lab")
    }

    @Test func mobaXtermSessions() {
        let moba = """
            [Bookmarks]
            SubRep=
            ImgNum=42
            pve1=#109#0%10.0.0.10%22%root%%-1%-1%%%%%0%0%0%_CurrentDrive_:\\keys\\id%%-1%0%0%0%%1080%%0%0%1#MobaFont%10%0%0%-1%15%236,236,236#0# #-1
            [Bookmarks_1]
            SubRep=Lab\\Docker
            ImgNum=41
            dockerdev=#109#0%192.168.1.158%2222%laremy%%-1%-1%%%%%0%0%0%%%-1%0%0%0%%1080%%0%0%1#MobaFont#0# #-1
            files=#140#7%192.168.1.158%22%laremy%%%%%%%#MobaFont#0# #-1
            desktop=#91#4%192.168.1.20%3389%%-1%0#MobaFont#0# #-1
            """
        let result = MobaXtermImport.parse(moba)
        #expect(result.hosts.map(\.name) == ["pve1", "dockerdev", "files"])
        #expect(result.hosts[0].tags == [])
        #expect(result.hosts[0].keyFile == nil) // _CurrentDrive_ is Windows
        #expect(result.hosts[1].port == 2222)
        #expect(result.hosts[1].tags == ["Lab", "Docker"])
        #expect(result.skipped == ["desktop: RDP session"])
    }

    @Test func fileZillaSitesNeverReadPasswords() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <FileZilla3 version="3.66.0">
              <Servers>
                <Folder expanded="1">Lab
                  <Server>
                    <Host>10.0.0.10</Host><Port>22</Port><Protocol>1</Protocol><Type>0</Type>
                    <User>root</User><Pass encoding="base64">aHVudGVyMg==</Pass>
                    <Name>pve1</Name><Keyfile>/Users/me/.ssh/id_lab</Keyfile>
                  </Server>
                  <Folder>Old
                    <Server><Host>ftp.example.com</Host><Port>21</Port><Protocol>0</Protocol><Name>web ftp</Name></Server>
                  </Folder>
                </Folder>
                <Server><Host>nas.lab</Host><Port>2200</Port><Protocol>1</Protocol><User>admin</User><Name>NAS</Name></Server>
              </Servers>
            </FileZilla3>
            """
        #expect(ForeignImportFormat.detect(fileName: "sitemanager.xml", text: xml) == .fileZilla)
        let result = try FileZillaImport.parse(xml)
        #expect(result.hosts.count == 2)
        #expect(result.hosts[0] == ImportedHost(name: "pve1", host: "10.0.0.10", user: "root", tags: ["Lab"], keyFile: "/Users/me/.ssh/id_lab"))
        #expect(result.hosts[1] == ImportedHost(name: "NAS", host: "nas.lab", port: 2200, user: "admin"))
        #expect(result.skipped == ["web ftp: FTP site (only SFTP is imported)"])
        #expect(!String(describing: result).contains("hunter2"))
        #expect(!String(describing: result).contains("aHVudGVyMg"))
    }

    @Test func ansibleINI() {
        let inventory = """
            # homelab
            [proxmox]
            pve1 ansible_host=10.0.0.10
            pve2 ansible_host=10.0.0.11 ansible_port=2222

            [docker]
            dockerdev ansible_host=192.168.1.158 ansible_user=laremy
            web[01:05].lab

            [lab:children]
            proxmox
            docker

            [proxmox:vars]
            ansible_user=root
            ansible_ssh_private_key_file=~/.ssh/id_pve

            [all:vars]
            ansible_user=admin
            """
        #expect(ForeignImportFormat.detect(fileName: "hosts", text: inventory) == .ansibleINI)
        let result = AnsibleImport.parseINI(inventory)
        #expect(result.hosts.map(\.name) == ["pve1", "pve2", "dockerdev"])
        let pve2 = result.hosts[1]
        #expect(pve2.host == "10.0.0.11" && pve2.port == 2222)
        #expect(pve2.user == "root") // group vars beat all:vars
        #expect(pve2.keyFile == "~/.ssh/id_pve")
        #expect(pve2.tags == ["lab", "proxmox"])
        #expect(result.hosts[2].user == "laremy") // host vars beat group vars
        #expect(result.hosts[2].tags == ["docker", "lab"])
        #expect(result.skipped == ["web[01:05].lab: host ranges aren't expanded"])
    }

    @Test func ansibleYAML() throws {
        let inventory = """
            all:
              vars:
                ansible_user: admin
              children:
                proxmox:
                  hosts:
                    pve1:
                      ansible_host: 10.0.0.10
                    pve2:
                      ansible_host: 10.0.0.11
                      ansible_port: 2222
                  vars:
                    ansible_user: root
                media:
                  hosts:
                    servarr:
                      ansible_host: 192.168.1.50
            """
        #expect(ForeignImportFormat.detect(fileName: "inventory.yml", text: inventory) == .ansibleYAML)
        let result = try AnsibleImport.parseYAML(inventory)
        #expect(result.hosts.map(\.name).sorted() == ["pve1", "pve2", "servarr"])
        let pve2 = try #require(result.hosts.first { $0.name == "pve2" })
        #expect(pve2.port == 2222 && pve2.user == "root" && pve2.tags == ["proxmox"])
        #expect(result.hosts.first { $0.name == "servarr" }?.user == "admin")
    }

    @Test func tabbyProfiles() throws {
        let config = """
            version: 3
            groups:
              - id: 8f2e
                name: Lab
            profiles:
              - type: ssh
                name: pve1
                group: 8f2e
                options:
                  host: 10.0.0.10
                  user: root
                  privateKeys:
                    - file:///Users/me/.ssh/id_lab
              - type: ssh
                name: nas
                group: Storage
                options:
                  host: nas.lab
                  port: 2200
                  user: admin
                  password: should-not-matter
              - type: local
                name: zsh
            """
        #expect(ForeignImportFormat.detect(fileName: "config.yaml", text: config) == .tabby)
        let result = try TabbyImport.parse(config)
        #expect(result.hosts == [
            ImportedHost(name: "pve1", host: "10.0.0.10", user: "root", tags: ["Lab"], keyFile: "/Users/me/.ssh/id_lab"),
            ImportedHost(name: "nas", host: "nas.lab", port: 2200, user: "admin", tags: ["Storage"]),
        ])
        #expect(result.skipped == ["zsh: local profile"])
    }

    @Test func resultsGoThroughTheUsualChecks() throws {
        let library = try HostLibrary.inMemory()
        var draft = HostDraft()
        draft.name = "pve1"
        draft.hostname = "10.0.0.10"
        try library.save(draft)

        let result = ForeignImportResult(hosts: [
            ImportedHost(name: "pve1", host: "10.0.0.10", tags: ["Lab"]),
            ImportedHost(name: "bad", host: "-oProxyCommand=x"),
            ImportedHost(name: "new", host: "10.0.0.20", port: 2222, user: "root", tags: ["Lab", "New"]),
        ])
        let candidates = result.table.candidates(existing: try library.entries(), tag: "imported")
        #expect(candidates[0].existingID != nil)
        #expect(!candidates[1].isImportable)
        #expect(candidates[2].isImportable)
        #expect(candidates[2].draft.tagList == ["Lab", "New", "imported"])
        #expect(ForeignImportResult().table.rows.isEmpty)
    }
}
