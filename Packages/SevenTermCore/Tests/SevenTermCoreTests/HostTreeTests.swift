import Foundation
import Testing
@testable import SevenTermCore

@Suite struct HostTreeTests {
    private func folder(_ id: String, _ name: String, parent: String? = nil) -> HostFolder {
        HostFolder(id: id, name: name, parentId: parent)
    }

    private func entry(_ id: String, _ name: String, in folderId: String? = nil, tags: [String] = []) -> HostEntry {
        HostEntry(host: SavedHost(id: id, name: name, hostname: "x.example", folderId: folderId), tags: tags)
    }

    private func ids(_ nodes: [HostTreeNode]) -> [String] { nodes.map(\.id) }

    @Test func foldersFirstThenHostsByName() {
        let tree = HostTree.build(
            folders: [folder("w", "Work"), folder("h", "home lab")],
            entries: [entry("z", "zeta"), entry("a", "Alpha")]
        )
        #expect(ids(tree) == ["h", "w", "a", "z"])
    }

    @Test func nesting() {
        let tree = HostTree.build(
            folders: [folder("w", "Work"), folder("c", "Core", parent: "w")],
            entries: [entry("s", "sw1", in: "c")]
        )
        #expect(ids(tree) == ["w"])
        #expect(ids(tree[0].children ?? []) == ["c"])
        #expect(ids(tree[0].children?[0].children ?? []) == ["s"])
        #expect(tree[0].children?[0].children?[0].children == nil)
    }

    @Test func orphansShowAtTopLevel() {
        let tree = HostTree.build(
            folders: [folder("f", "Lost folder", parent: "gone")],
            entries: [entry("h", "lost host", in: "gone")]
        )
        #expect(ids(tree) == ["f", "h"])
    }

    @Test func loopsDoNotHang() {
        let tree = HostTree.build(
            folders: [folder("a", "A", parent: "b"), folder("b", "B", parent: "a")],
            entries: []
        )
        #expect(Set(ids(tree)) == ["a", "b"])
        #expect(tree.count == 2)
        #expect(tree.allSatisfy { ($0.children ?? []).isEmpty })
    }

    private var workAndLab: (folders: [HostFolder], entries: [HostEntry]) {
        (
            [folder("w", "Work"), folder("l", "Lab")],
            [entry("sw1", "sw1", in: "w", tags: ["prod"]), entry("fw1", "fw1", in: "w"), entry("pi", "pi", in: "l")]
        )
    }

    @Test func filteredPrunesEmptyFolders() {
        let (folders, entries) = workAndLab
        let tree = HostTree.filtered(folders: folders, entries: entries, query: "sw", tag: nil)
        #expect(ids(tree) == ["w"])
        #expect(ids(tree[0].children ?? []) == ["sw1"])
    }

    @Test func filterMatchesFolderName() {
        let (folders, entries) = workAndLab
        let tree = HostTree.filtered(folders: folders, entries: entries, query: "work", tag: nil)
        #expect(ids(tree) == ["w"])
        #expect(ids(tree[0].children ?? []) == ["fw1", "sw1"])
        #expect(HostFilter.matches(entry("s", "sw1"), query: "core sw", folderPath: ["Work", "Core"]))
        #expect(!HostFilter.matches(entry("s", "sw1"), query: "core sw"))
    }

    @Test func tagFilterStillApplies() {
        let (folders, entries) = workAndLab
        let tree = HostTree.filtered(folders: folders, entries: entries, query: "", tag: "prod")
        #expect(ids(tree) == ["w"])
        #expect(ids(tree[0].children ?? []) == ["sw1"])
    }

    @Test func hostsInFolderIncludeSubfolders() {
        let folders = [folder("w", "Work"), folder("c", "Core", parent: "w")]
        let entries = [entry("2", "sw2", in: "c"), entry("1", "sw1", in: "c"), entry("f", "fw1", in: "w")]
        let tree = HostTree.build(folders: folders, entries: entries)
        #expect(HostTree.hosts(in: "w", nodes: tree).map(\.host.name) == ["sw1", "sw2", "fw1"])
        #expect(HostTree.hosts(in: "nope", nodes: tree).isEmpty)
    }

    @Test func hostsInFolderRespectFilter() {
        let folders = [folder("w", "Work")]
        let entries = [entry("1", "sw1", in: "w")]
        let tree = HostTree.filtered(folders: folders, entries: entries, query: "zzz", tag: nil)
        #expect(HostTree.hosts(in: "w", nodes: tree).isEmpty)
    }

    @Test func pathAndFlattened() {
        let folders = [folder("w", "Work"), folder("c", "Core", parent: "w"), folder("l", "Lab")]
        #expect(HostTree.path(of: "c", folders: folders) == ["Work", "Core"])
        #expect(HostTree.path(of: nil, folders: folders) == [])
        #expect(HostTree.path(of: "unknown", folders: folders) == [])
        let flat = HostTree.flattened(folders: folders)
        #expect(flat.map(\.folder.name) == ["Lab", "Work", "Core"])
        #expect(flat.map(\.depth) == [0, 0, 1])
    }
}
