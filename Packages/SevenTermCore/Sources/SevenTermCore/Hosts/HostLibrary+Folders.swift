import Foundation
import GRDB

extension HostLibrary {
    /// Every folder, sorted by name without regard to case.
    public func folders() throws -> [HostFolder] {
        try database.read { db in
            try HostFolder.fetchAll(db).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    @discardableResult
    public func createFolder(name: String, parentId: String?, now: Date = Date()) throws -> HostFolder {
        guard let clean = HostFolder.cleanName(name) else { throw HostLibraryError.invalidFolderName }
        return try database.write { db in
            try Self.requireFolder(parentId, in: db)
            try Self.requireNoSibling(named: clean, in: parentId, excluding: nil, db: db)
            let folder = HostFolder(name: clean, parentId: parentId, createdAt: now, updatedAt: now)
            try folder.insert(db)
            return folder
        }
    }

    public func renameFolder(id: String, to name: String, now: Date = Date()) throws {
        guard let clean = HostFolder.cleanName(name) else { throw HostLibraryError.invalidFolderName }
        try database.write { db in
            guard var folder = try HostFolder.fetchOne(db, key: id) else { throw HostLibraryError.folderNotFound }
            try Self.requireNoSibling(named: clean, in: folder.parentId, excluding: id, db: db)
            folder.name = clean
            folder.updatedAt = now
            try folder.update(db)
        }
    }

    public func moveFolder(id: String, toParent parentId: String?, now: Date = Date()) throws {
        try database.write { db in
            guard var folder = try HostFolder.fetchOne(db, key: id) else { throw HostLibraryError.folderNotFound }
            try Self.requireFolder(parentId, in: db)
            // Walk up from the destination; meeting the moved folder is a cycle.
            // An id seen twice means the destination already sits on a loop that
            // doesn't include the moved folder, so the move adds no new cycle.
            var cursor = parentId
            var visited: Set<String> = []
            while let current = cursor, visited.insert(current).inserted {
                if current == id { throw HostLibraryError.folderCycle }
                cursor = try HostFolder.fetchOne(db, key: current)?.parentId
            }
            try Self.requireNoSibling(named: folder.name, in: parentId, excluding: id, db: db)
            folder.parentId = parentId
            folder.updatedAt = now
            try folder.update(db)
        }
    }

    public func moveHost(id: String, toFolder folderId: String?, now: Date = Date()) throws {
        try database.write { db in
            try Self.requireFolder(folderId, in: db)
            guard var host = try SavedHost.fetchOne(db, key: id) else { return }
            host.folderId = folderId
            host.updatedAt = now
            try host.update(db)
        }
    }

    /// Deletes the folder. Its subfolders and hosts move up to its parent;
    /// a subfolder whose name is taken there gets " 2", " 3", ... added.
    public func deleteFolder(id: String, now: Date = Date()) throws {
        try database.write { db in
            guard let folder = try HostFolder.fetchOne(db, key: id) else { throw HostLibraryError.folderNotFound }
            let destination = folder.parentId
            let children = try HostFolder.filter(Column("parentId") == id).fetchAll(db)
            for var child in children {
                var candidate = child.name
                var suffix = 2
                while try Self.hasSibling(named: candidate, in: destination, excluding: child.id, db: db) {
                    let tail = " \(suffix)"
                    candidate = String(child.name.prefix(60 - tail.count)) + tail
                    suffix += 1
                }
                child.name = candidate
                child.parentId = destination
                child.updatedAt = now
                try child.update(db)
            }
            try db.execute(sql: "UPDATE host SET folderId = ? WHERE folderId = ?", arguments: [destination, id])
            _ = try HostFolder.deleteOne(db, key: id)
        }
    }

    /// Finds or creates each level (names matched ignoring case). Empty path returns nil.
    @discardableResult
    public func ensureFolder(path: [String], now: Date = Date()) throws -> String? {
        guard !path.isEmpty else { return nil }
        let names = try path.map { raw -> String in
            guard let clean = HostFolder.cleanName(raw) else { throw HostLibraryError.invalidFolderName }
            return clean
        }
        return try database.write { db in
            var parentId: String?
            for name in names {
                if let existing = try Self.sibling(named: name, in: parentId, excluding: nil, db: db) {
                    parentId = existing.id
                } else {
                    let folder = HostFolder(name: name, parentId: parentId, createdAt: now, updatedAt: now)
                    try folder.insert(db)
                    parentId = folder.id
                }
            }
            return parentId
        }
    }

    // MARK: Checks

    private static func requireFolder(_ id: String?, in db: Database) throws {
        guard let id else { return }
        guard try HostFolder.fetchOne(db, key: id) != nil else { throw HostLibraryError.folderNotFound }
    }

    private static func sibling(named name: String, in parentId: String?, excluding id: String?, db: Database) throws -> HostFolder? {
        try HostFolder
            .filter(Column("parentId") == parentId)
            .filter(Column("name").collating(.nocase) == name)
            .filter(Column("id") != id)
            .fetchOne(db)
    }

    private static func hasSibling(named name: String, in parentId: String?, excluding id: String?, db: Database) throws -> Bool {
        try sibling(named: name, in: parentId, excluding: id, db: db) != nil
    }

    private static func requireNoSibling(named name: String, in parentId: String?, excluding id: String?, db: Database) throws {
        if try hasSibling(named: name, in: parentId, excluding: id, db: db) {
            throw HostLibraryError.duplicateFolderName
        }
    }
}
