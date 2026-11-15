import Foundation
import GRDB

/// A folder that groups saved hosts. Folders nest; a host is in one folder
/// or at the top level.
public struct HostFolder: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "folder"

    public var id: String
    public var name: String
    /// The folder this one sits in; nil is the top level.
    public var parentId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, name: String, parentId: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Trimmed name, or nil if empty, over 60 characters, or containing "/".
    public static func cleanName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !name.contains("/") else { return nil }
        return name
    }
}
