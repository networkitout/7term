import Foundation

/// A host read from another app's export, before it's checked or saved.
public struct ImportedHost: Equatable, Sendable {
    public var name: String
    public var host: String
    public var port: Int?
    public var user: String?
    /// Folders or groups in the other app, outermost first.
    public var tags: [String]
    /// Only kept when it's a Mac path (a Windows path is no use here).
    public var keyFile: String?

    public init(name: String, host: String, port: Int? = nil, user: String? = nil, tags: [String] = [], keyFile: String? = nil) {
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.tags = tags
        self.keyFile = Self.usableKeyPath(keyFile)
    }

    /// "C:\Users\me\key.ppk" and the like aren't files on this Mac.
    static func usableKeyPath(_ path: String?) -> String? {
        guard var path = path?.trimmingCharacters(in: .whitespaces), !path.isEmpty else { return nil }
        if path.hasPrefix("file://") { path = String(path.dropFirst(7)) }
        guard path.hasPrefix("/") || path.hasPrefix("~") else { return nil }
        return path
    }
}

/// What came out of a file: the hosts, and what was left out and why
/// (RDP and telnet sessions, FTP sites, and so on).
public struct ForeignImportResult: Equatable, Sendable {
    public var hosts: [ImportedHost]
    public var skipped: [String]

    public init(hosts: [ImportedHost] = [], skipped: [String] = []) {
        self.hosts = hosts
        self.skipped = skipped
    }

    /// A table the spreadsheet import's preview, checks and duplicate
    /// detection can use as-is. Passwords were never read, so there's no
    /// column for them.
    public var table: HostImportTable {
        HostImportTable(
            header: ["Name", "Host", "Port", "User", "Tags", "Key file"],
            rows: hosts.map { host in
                [host.name, host.host, host.port.map(String.init) ?? "", host.user ?? "",
                 host.tags.joined(separator: ";"), host.keyFile ?? ""]
            },
            columns: [.name, .host, .port, .user, .tags, .keyFile],
            secretColumns: [],
            lineNumbers: Array(stride(from: 1, through: hosts.count, by: 1))
        )
    }
}

/// The other apps 7 Term can import from.
public enum ForeignImportFormat: String, CaseIterable, Sendable {
    case royalTS, secureCRT, putty, mobaXterm, fileZilla, ansibleINI, ansibleYAML, tabby

    public var title: String {
        switch self {
        case .royalTS: "Royal TSX"
        case .secureCRT: "SecureCRT"
        case .putty: "PuTTY / KiTTY"
        case .mobaXterm: "MobaXterm"
        case .fileZilla: "FileZilla"
        case .ansibleINI, .ansibleYAML: "Ansible inventory"
        case .tabby: "Tabby"
        }
    }

    /// Where to find the file to choose, shown in the import sheet.
    public var hint: String {
        switch self {
        case .royalTS:
            "Your Royal TSX document (.rtsz). SSH connections are imported; folders become tags."
        case .secureCRT:
            "Choose SecureCRT's Sessions folder: ~/Library/Application Support/VanDyke/SecureCRT/Config/Sessions (or Config/Sessions on Windows)."
        case .putty:
            "On Windows, export the sessions: reg export HKCU\\Software\\SimonTatham\\PuTTY\\Sessions putty.reg (KiTTY: HKCU\\Software\\9bis.com\\KiTTY\\Sessions)."
        case .mobaXterm:
            "In MobaXterm, right-click User sessions ▸ Export all sessions to file (.mxtsessions)."
        case .fileZilla:
            "File ▸ Export… in FileZilla, or sitemanager.xml from ~/.config/filezilla. Only SFTP sites are imported."
        case .ansibleINI, .ansibleYAML:
            "Your inventory file (INI or YAML). Groups become tags."
        case .tabby:
            "Tabby's config.yaml: ~/Library/Application Support/tabby/config.yaml."
        }
    }

    /// Guesses the format from a file's name and its first few KB.
    public static func detect(fileName: String, text: String) -> ForeignImportFormat? {
        let name = fileName.lowercased()
        let head = String(text.prefix(4096))
        if name.hasSuffix(".rtsz") || name.hasSuffix(".rtsx") || head.contains("<RTSZDocument") { return .royalTS }
        if name.hasSuffix(".reg") || head.contains("\\SimonTatham\\PuTTY\\Sessions") || head.contains("\\KiTTY\\Sessions") {
            return .putty
        }
        if name.hasSuffix(".mxtsessions") || head.contains("[Bookmarks") { return .mobaXterm }
        if head.contains("<FileZilla3") || name == "sitemanager.xml" { return .fileZilla }
        if head.contains("S:\"Hostname\"=") { return .secureCRT }
        if name.hasSuffix(".yaml") || name.hasSuffix(".yml") {
            if head.range(of: #"(?m)^profiles\s*:"#, options: .regularExpression) != nil { return .tabby }
            return .ansibleYAML
        }
        if head.contains("ansible_host") || head.contains("ansible_") || name == "hosts" || name.hasSuffix(".ini")
            || name.contains("inventory") {
            return .ansibleINI
        }
        return nil
    }

    /// Reads the exported text. SecureCRT, which is a folder of files,
    /// uses `parseSecureCRT(files:)` instead.
    public func parse(_ text: String) throws -> ForeignImportResult {
        switch self {
        case .royalTS: return try RoyalTSImport.parse(text)
        case .secureCRT: return SecureCRTImport.parse(files: [("Session.ini", text)])
        case .putty: return PuTTYImport.parse(text)
        case .mobaXterm: return MobaXtermImport.parse(text)
        case .fileZilla: return try FileZillaImport.parse(text)
        case .ansibleINI: return AnsibleImport.parseINI(text)
        case .ansibleYAML: return try AnsibleImport.parseYAML(text)
        case .tabby: return try TabbyImport.parse(text)
        }
    }
}

/// Text from a file in whatever encoding Windows tools wrote it in:
/// UTF-16 with a byte order mark (regedit), UTF-8, or Windows-1252
/// (MobaXterm).
public func decodeExportText(_ data: Data) -> String {
    if data.starts(with: [0xFF, 0xFE]) { return String(data: data, encoding: .utf16LittleEndian).map(dropBOM) ?? "" }
    if data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16BigEndian).map(dropBOM) ?? "" }
    if let text = String(data: data, encoding: .utf8) { return dropBOM(text) }
    return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
}

private func dropBOM(_ text: String) -> String {
    text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
}
