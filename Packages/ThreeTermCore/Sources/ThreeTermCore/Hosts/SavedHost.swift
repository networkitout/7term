import Foundation
import GRDB

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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var target: SSHTarget {
        SSHTarget(user: username, host: hostname, port: port)
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
