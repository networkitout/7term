import Foundation
import GRDB

/// The saved hosts and their tags, in SQLite through GRDB.
/// Secrets never go in here; milestone 6 adds credential *references* only.
public final class HostLibrary: Sendable {
    private let database: any DatabaseWriter

    public init(_ database: any DatabaseWriter) throws {
        self.database = database
        try Self.migrator.migrate(database)
    }

    /// The library file at `url`, creating its folder if needed.
    public static func onDisk(at url: URL) throws -> HostLibrary {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try HostLibrary(DatabaseQueue(path: url.path))
    }

    /// An empty library in memory, for tests and previews.
    public static func inMemory() throws -> HostLibrary {
        try HostLibrary(DatabaseQueue())
    }

    // MARK: Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-hosts-and-tags") { db in
            try db.create(table: "host") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("hostname", .text).notNull()
                t.column("port", .integer)
                t.column("username", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "tag") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique().collate(.nocase)
            }
            try db.create(table: "hostTag") { t in
                t.column("hostId", .text).notNull().indexed()
                    .references("host", onDelete: .cascade)
                t.column("tagId", .text).notNull().indexed()
                    .references("tag", onDelete: .cascade)
                t.primaryKey(["hostId", "tagId"])
            }
        }
        return migrator
    }

    // MARK: Reading

    /// Every host with its tags, sorted by name without regard to case.
    public func entries() throws -> [HostEntry] {
        try database.read { db in
            let hosts = try SavedHost.fetchAll(db)
            let tags = try TagRecord.fetchAll(db)
            let links = try HostTagRecord.fetchAll(db)

            let tagNames = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
            var tagsByHost: [String: [String]] = [:]
            for link in links {
                if let name = tagNames[link.tagId] {
                    tagsByHost[link.hostId, default: []].append(name)
                }
            }

            return hosts
                .map { host in
                    let names = (tagsByHost[host.id] ?? [])
                        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    return HostEntry(host: host, tags: names)
                }
                .sorted {
                    $0.host.name.localizedCaseInsensitiveCompare($1.host.name) == .orderedAscending
                }
        }
    }

    public func isEmpty() throws -> Bool {
        try database.read { db in try SavedHost.fetchCount(db) == 0 }
    }

    // MARK: Writing

    /// Saves a valid draft as a new host (`id` nil) or over an existing one.
    /// Returns the saved entry. Throws `HostLibraryError.invalidDraft` otherwise.
    @discardableResult
    public func save(_ draft: HostDraft, id: String? = nil, now: Date = Date()) throws -> HostEntry {
        guard draft.isValid, let target = draft.target else { throw HostLibraryError.invalidDraft }
        let tagNames = draft.tagList

        return try database.write { db in
            var host: SavedHost
            if let id, let existing = try SavedHost.fetchOne(db, key: id) {
                host = existing
                host.updatedAt = now
            } else {
                host = SavedHost(id: id ?? UUID().uuidString, name: "", hostname: "", createdAt: now, updatedAt: now)
            }
            host.name = draft.trimmedName
            host.hostname = target.host
            host.port = target.port
            host.username = target.user
            try host.save(db)

            try Self.replaceTags(of: host.id, with: tagNames, in: db)
            try Self.deleteUnusedTags(in: db)
            return HostEntry(host: host, tags: tagNames.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            })
        }
    }

    public func delete(id: String) throws {
        try database.write { db in
            _ = try SavedHost.deleteOne(db, key: id)
            try Self.deleteUnusedTags(in: db)
        }
    }

    /// Copies a host and its tags, named "<name> copy".
    @discardableResult
    public func duplicate(id: String, now: Date = Date()) throws -> HostEntry? {
        guard let original = try entries().first(where: { $0.id == id }) else { return nil }
        var draft = HostDraft(entry: original)
        draft.name = original.host.name + " copy"
        return try save(draft, now: now)
    }

    /// Adds the aliases not already saved (matched by hostname, ignoring
    /// case). Each is saved with the alias as both name and hostname, so ssh
    /// keeps applying the ssh_config block. Returns how many were added.
    @discardableResult
    public func importAliases(_ aliases: [SSHConfigAlias], tag: String? = nil, now: Date = Date()) throws -> Int {
        let existing = try Set(entries().map { $0.host.hostname.lowercased() })
        var added = 0
        for alias in aliases where !existing.contains(alias.alias.lowercased()) {
            var draft = HostDraft()
            draft.name = alias.alias
            draft.hostname = alias.alias
            draft.tags = tag ?? ""
            guard draft.isValid else { continue }
            try save(draft, now: now)
            added += 1
        }
        return added
    }

    // MARK: Tags

    private static func replaceTags(of hostId: String, with names: [String], in db: Database) throws {
        try HostTagRecord.filter(Column("hostId") == hostId).deleteAll(db)
        for name in names {
            let tag: TagRecord
            if let found = try TagRecord.filter(Column("name").collating(.nocase) == name).fetchOne(db) {
                tag = found
            } else {
                tag = TagRecord(id: UUID().uuidString, name: name)
                try tag.insert(db)
            }
            try HostTagRecord(hostId: hostId, tagId: tag.id).insert(db)
        }
    }

    private static func deleteUnusedTags(in db: Database) throws {
        try db.execute(sql: "DELETE FROM tag WHERE id NOT IN (SELECT tagId FROM hostTag)")
    }
}

public enum HostLibraryError: Error, Equatable {
    case invalidDraft
}
