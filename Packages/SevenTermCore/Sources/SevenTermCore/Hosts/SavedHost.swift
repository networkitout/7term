import Foundation
import GRDB

/// How a saved host authenticates.
public enum AuthMethod: String, Codable, CaseIterable, Sendable {
    /// Whatever ssh would do on its own: agent keys (1Password, Secretive,
    /// ssh-agent), ~/.ssh/config, then a password typed in the terminal.
    case automatic
    /// One private key file, passed with -i.
    case keyFile
    /// A password kept in the login Keychain, handed to ssh after Touch ID.
    case password
}

/// What a saved entry connects to.
public enum HostKind: String, Codable, CaseIterable, Sendable {
    case ssh
    /// A serial console. `hostname` holds the port's /dev/cu.* path.
    case serial
}

/// A saved serial port: its settings, and enough about the adapter to find
/// it again if macOS gives it a different /dev name (adapters without a
/// serial number are named after the USB socket they're in).
public struct SerialHostDetails: Codable, Hashable, Sendable {
    public var settings: SerialSettings
    public var usbSerialNumber: String?
    public var vendorID: Int?
    public var productID: Int?

    public init(settings: SerialSettings = SerialSettings(), usbSerialNumber: String? = nil, vendorID: Int? = nil, productID: Int? = nil) {
        self.settings = settings
        self.usbSerialNumber = usbSerialNumber
        self.vendorID = vendorID
        self.productID = productID
    }
}

/// A host the user saved. `hostname` may be an IP, a DNS name, or an alias
/// from ~/.ssh/config; ssh resolves it either way.
public struct SavedHost: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var hostname: String
    public var port: Int?
    public var username: String?
    public var sortOrder: Int
    /// Start logging as soon as a session to this host opens.
    public var logByDefault: Bool
    public var authMethod: AuthMethod
    /// The private key for `.keyFile`; ignored otherwise.
    public var identityFile: String?
    public var kind: HostKind
    /// Set for serial entries.
    public var serial: SerialHostDetails?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        hostname: String,
        port: Int? = nil,
        username: String? = nil,
        sortOrder: Int = 0,
        logByDefault: Bool = false,
        authMethod: AuthMethod = .automatic,
        identityFile: String? = nil,
        kind: HostKind = .ssh,
        serial: SerialHostDetails? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.sortOrder = sortOrder
        self.logByDefault = logByDefault
        self.authMethod = authMethod
        self.identityFile = identityFile
        self.kind = kind
        self.serial = serial
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var target: SSHTarget {
        SSHTarget(
            user: username,
            host: hostname,
            port: port,
            identityFile: authMethod == .keyFile ? identityFile : nil
        )
    }
}

extension SavedHost: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "host"
}

/// A tag name, unique without regard to case.
struct TagRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tag"
    var id: String
    var name: String
}

struct HostTagRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hostTag"
    var hostId: String
    var tagId: String
}

/// A saved host with its tag names, sorted.
public struct HostEntry: Hashable, Sendable, Identifiable {
    public var host: SavedHost
    public var tags: [String]

    public var id: String { host.id }

    public init(host: SavedHost, tags: [String]) {
        self.host = host
        self.tags = tags
    }
}
