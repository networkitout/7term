import Foundation

/// One row of the sidebar tree: a folder with its children, or a host.
public enum HostTreeNode: Hashable, Sendable, Identifiable {
    case folder(HostFolder, children: [HostTreeNode])
    case host(HostEntry)

    /// The folder's or host's own id.
    public var id: String {
        switch self {
        case .folder(let folder, _): folder.id
        case .host(let entry): entry.id
        }
    }

    /// Nil for a host.
    public var children: [HostTreeNode]? {
        switch self {
        case .folder(_, let children): children
        case .host: nil
        }
    }
}

/// Turns folders and host entries into the sidebar tree.
public enum HostTree {
    /// Everything, folders first then hosts at each level.
    public static func build(folders: [HostFolder], entries: [HostEntry]) -> [HostTreeNode] {
        let parents = effectiveParents(folders)
        let folderIds = Set(folders.map(\.id))
        var subfolders: [String?: [HostFolder]] = [:]
        for folder in folders { subfolders[parents[folder.id] ?? nil, default: []].append(folder) }
        var hostsByFolder: [String?: [HostEntry]] = [:]
        for entry in entries {
            let key = entry.host.folderId.flatMap { folderIds.contains($0) ? $0 : nil }
            hostsByFolder[key, default: []].append(entry)
        }

        func nodes(under parent: String?) -> [HostTreeNode] {
            let folderNodes = (subfolders[parent] ?? [])
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { HostTreeNode.folder($0, children: nodes(under: $0.id)) }
            let hostNodes = (hostsByFolder[parent] ?? [])
                .sorted { $0.host.name.localizedCaseInsensitiveCompare($1.host.name) == .orderedAscending }
                .map { HostTreeNode.host($0) }
            return folderNodes + hostNodes
        }
        return nodes(under: nil)
    }

    /// Only hosts matching `query` and `tag`, inside their folders; folders left empty are dropped.
    public static func filtered(folders: [HostFolder], entries: [HostEntry], query: String, tag: String?) -> [HostTreeNode] {
        let byId = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let parents = effectiveParents(folders)
        func path(_ folderId: String?) -> [String] { names(of: folderId, byId: byId, parents: parents) }

        let kept = entries.filter { entry in
            guard HostFilter.matches(entry, query: query, folderPath: path(entry.host.folderId)) else { return false }
            guard let tag else { return true }
            return entry.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        return prune(build(folders: folders, entries: kept))
    }

    /// Hosts under a folder, subfolders included, in sidebar order.
    public static func hosts(in folderId: String, nodes: [HostTreeNode]) -> [HostEntry] {
        for node in nodes {
            guard case .folder(_, let children) = node else { continue }
            if node.id == folderId { return allHosts(in: children) }
            let found = hosts(in: folderId, nodes: children)
            if !found.isEmpty { return found }
        }
        return []
    }

    /// Folder names from the top level down to `folderId`; [] for nil or unknown.
    public static func path(of folderId: String?, folders: [HostFolder]) -> [String] {
        let byId = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return names(of: folderId, byId: byId, parents: effectiveParents(folders))
    }

    /// Every folder as (folder, depth), in sidebar order; for pickers and menus.
    public static func flattened(folders: [HostFolder]) -> [(folder: HostFolder, depth: Int)] {
        var result: [(folder: HostFolder, depth: Int)] = []
        func walk(_ nodes: [HostTreeNode], depth: Int) {
            for case .folder(let folder, let children) in nodes {
                result.append((folder, depth))
                walk(children, depth: depth + 1)
            }
        }
        walk(build(folders: folders, entries: []), depth: 0)
        return result
    }

    // MARK: - Helpers

    /// Each folder's parent as the tree shows it. A missing parent, or a
    /// folder that sits on a loop, counts as top level (nil).
    private static func effectiveParents(_ folders: [HostFolder]) -> [String: String?] {
        let declared = Dictionary(folders.map { ($0.id, $0.parentId) }, uniquingKeysWith: { first, _ in first })
        var result: [String: String?] = [:]
        for folder in folders {
            guard let parent = folder.parentId, declared[parent] != nil else {
                result[folder.id] = .some(nil)
                continue
            }
            var visited: Set<String> = [folder.id]
            var current: String? = parent
            var onLoop = false
            while let id = current {
                if id == folder.id { onLoop = true; break }
                guard visited.insert(id).inserted else { break }
                current = declared[id] ?? nil
            }
            result[folder.id] = .some(onLoop ? nil : parent)
        }
        return result
    }

    private static func names(of folderId: String?, byId: [String: HostFolder], parents: [String: String?]) -> [String] {
        var names: [String] = []
        var current = folderId
        var visited = Set<String>()
        while let id = current, let folder = byId[id], visited.insert(id).inserted {
            names.append(folder.name)
            current = parents[id] ?? nil
        }
        return names.reversed()
    }

    private static func prune(_ nodes: [HostTreeNode]) -> [HostTreeNode] {
        nodes.compactMap { node in
            guard case .folder(let folder, let children) = node else { return node }
            let kept = prune(children)
            return kept.isEmpty ? nil : .folder(folder, children: kept)
        }
    }

    private static func allHosts(in nodes: [HostTreeNode]) -> [HostEntry] {
        nodes.flatMap { node -> [HostEntry] in
            switch node {
            case .host(let entry): [entry]
            case .folder(_, let children): allHosts(in: children)
            }
        }
    }
}
