import Foundation

/// Everything 7 Term needs to rebuild its host list and look on another Mac
/// or after a reinstall. Deliberately excluded: Keychain passwords, private
/// keys (only their paths), and session logs.
public struct BackupSnapshot: Codable, Equatable, Sendable {
    public struct Host: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var hostname: String
        public var port: Int?
        public var username: String?
        public var tags: [String]
        public var logByDefault: Bool
        public var authMethod: AuthMethod
        public var identityFile: String?
        /// Missing in backups from before serial support: those are ssh.
        public var kind: HostKind?
        public var serial: SerialHostDetails?
        public var createdAt: Date
        public var updatedAt: Date

        public init(entry: HostEntry) {
            id = entry.host.id
            name = entry.host.name
            hostname = entry.host.hostname
            port = entry.host.port
            username = entry.host.username
            tags = entry.tags
            logByDefault = entry.host.logByDefault
            authMethod = entry.host.authMethod
            identityFile = entry.host.identityFile
            kind = entry.host.kind
            serial = entry.host.serial
            createdAt = entry.host.createdAt
            updatedAt = entry.host.updatedAt
        }

        var savedHost: SavedHost {
            SavedHost(
                id: id, name: name, hostname: hostname, port: port, username: username,
                logByDefault: logByDefault, authMethod: authMethod, identityFile: identityFile,
                kind: kind ?? .ssh, serial: serial,
                createdAt: createdAt, updatedAt: updatedAt
            )
        }
    }

    public struct Settings: Codable, Equatable, Sendable {
        public var paletteID: String
        public var fontFamily: String?
        public var fontSize: Double

        public init(paletteID: String, fontFamily: String?, fontSize: Double) {
            self.paletteID = paletteID
            self.fontFamily = fontFamily
            self.fontSize = fontSize
        }
    }

    public static let currentFormat = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var appVersion: String
    public var hosts: [Host]
    public var settings: Settings
    public var importedPalettes: [TerminalPalette]

    public init(
        exportedAt: Date = Date(),
        appVersion: String,
        hosts: [HostEntry],
        settings: Settings,
        importedPalettes: [TerminalPalette]
    ) {
        formatVersion = Self.currentFormat
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.hosts = hosts.map(Host.init(entry:))
        self.settings = settings
        self.importedPalettes = importedPalettes
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public enum ReadError: Error, LocalizedError, Equatable {
        case notABackup
        case newerFormat(Int)

        public var errorDescription: String? {
            switch self {
            case .notABackup: "That file isn't a 7 Term backup."
            case .newerFormat(let version): "This backup was made by a newer 7 Term (format \(version))."
            }
        }
    }

    public static func decode(_ data: Data) throws -> BackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: BackupSnapshot
        do {
            snapshot = try decoder.decode(BackupSnapshot.self, from: data)
        } catch {
            throw ReadError.notABackup
        }
        guard snapshot.formatVersion <= currentFormat else {
            throw ReadError.newerFormat(snapshot.formatVersion)
        }
        return snapshot
    }
}

/// Where backups go and how many daily copies are kept.
public struct BackupStore: Sendable {
    public let folder: URL
    public var keepDays = 30

    public static let latestName = "7term-backup.json"

    public init(folder: URL) {
        self.folder = folder
    }

    public var latestURL: URL {
        folder.appending(path: Self.latestName, directoryHint: .notDirectory)
    }

    var historyFolder: URL {
        folder.appending(path: "History", directoryHint: .isDirectory)
    }

    /// Writes the latest backup and today's copy (replacing an earlier copy
    /// from the same day), then trims copies beyond `keepDays`.
    public func write(_ snapshot: BackupSnapshot, calendar: Calendar = .current) throws {
        let data = try snapshot.encoded()
        try FileManager.default.createDirectory(at: historyFolder, withIntermediateDirectories: true)
        try data.write(to: latestURL, options: .atomic)

        let day = calendar.dateComponents([.year, .month, .day], from: snapshot.exportedAt)
        let stamp = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        try data.write(to: historyFolder.appending(path: "7term-backup-\(stamp).json"), options: .atomic)

        let copies = (try? FileManager.default.contentsOfDirectory(at: historyFolder, includingPropertiesForKeys: nil)) ?? []
        let dated = copies
            .filter { $0.lastPathComponent.hasPrefix("7term-backup-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in dated.dropFirst(keepDays) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
