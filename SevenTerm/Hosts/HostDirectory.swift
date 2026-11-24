import AppKit
import Foundation
import Observation
import SevenTermCore

/// What the host sheet is editing.
enum HostEditorRequest: Identifiable {
    case new(folderID: String?)
    case edit(HostEntry)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let entry): entry.id
        }
    }

    var entry: HostEntry? {
        switch self {
        case .new: nil
        case .edit(let entry): entry
        }
    }

    /// The folder a new host starts in; nil for the top level or an edit.
    var folderID: String? {
        switch self {
        case .new(let folderID): folderID
        case .edit: nil
        }
    }
}

/// What the folder name sheet is for.
enum FolderNameRequest: Identifiable {
    case new(parentId: String?)
    case rename(HostFolder)

    var id: String {
        switch self {
        case .new(let parentId): "new-\(parentId ?? "")"
        case .rename(let folder): "rename-\(folder.id)"
        }
    }
}

/// The app's view of the saved host library: the entries, the filter text,
/// and which sheets are open.
@MainActor
@Observable
final class HostDirectory {
    private(set) var entries: [HostEntry] = []
    private(set) var folders: [HostFolder] = []
    private(set) var errorMessage: String?
    var query = ""
    var editor: HostEditorRequest?
    /// The selected row in the sidebar: a host's or a folder's id.
    var selectedID: String?
    /// Show only hosts with this tag; nil shows all.
    var tagFilter: String?
    /// A host waiting for the delete confirmation.
    var pendingDelete: HostEntry?
    /// The folder name sheet, when open.
    var folderNameRequest: FolderNameRequest?
    /// A folder waiting for the delete confirmation.
    var pendingFolderDelete: HostFolder?
    /// Hosts waiting for the Open All confirmation, and the folder they came from.
    var pendingOpenAll: [HostEntry]?
    var pendingOpenAllFolderName: String?
    /// Opening more tabs than this at once asks first.
    static let openAllConfirmThreshold = 10
    /// Open folders in the sidebar. Kept on this Mac only.
    var expandedFolderIDs: Set<String> {
        didSet {
            guard expandedFolderIDs != oldValue else { return }
            UserDefaults.standard.set(Array(expandedFolderIDs).sorted(), forKey: Self.expandedFoldersKey)
        }
    }
    var isImportPresented = false
    /// The spreadsheet (CSV or pasted cells) import sheet.
    var isSpreadsheetImportPresented = false
    private(set) var importCandidates: [SSHConfigAlias] = []

    private let library: HostLibrary?
    /// Called after the host list changes; the backup uses it.
    @ObservationIgnored var onChange: (() -> Void)?
    private static let didOfferImportKey = "didOfferSSHConfigImport"

    /// Whether 7 Term was used before this launch: hosts saved, or the
    /// first-run import already offered. Read it before the offer runs.
    var hasBeenUsedBefore: Bool {
        !entries.isEmpty || UserDefaults.standard.bool(forKey: Self.didOfferImportKey)
    }
    private static let expandedFoldersKey = "expandedFolders"

    init() {
        expandedFolderIDs = Set(UserDefaults.standard.stringArray(forKey: Self.expandedFoldersKey) ?? [])
        do {
            library = try HostLibrary.onDisk(at: Self.libraryURL)
        } catch {
            library = nil
            errorMessage = "Couldn't open the host library: \(error.localizedDescription)"
        }
        reload()
    }

    /// ~/Library/Application Support/7 Term/hosts.sqlite
    static var libraryURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "7 Term", directoryHint: .isDirectory)
            .appending(path: "hosts.sqlite", directoryHint: .notDirectory)
    }

    /// True while the filter text or a tag narrows the sidebar.
    var isFiltering: Bool {
        !query.isEmpty || tagFilter != nil
    }

    /// What the sidebar shows: folders first, then hosts, at each level.
    /// While filtering, only matching hosts and the folders that hold them.
    var tree: [HostTreeNode] {
        if isFiltering {
            HostTree.filtered(folders: folders, entries: entries, query: query, tag: tagFilter)
        } else {
            HostTree.build(folders: folders, entries: entries)
        }
    }

    /// Every folder is open while filtering, so matches are never hidden.
    func isExpanded(_ folderID: String) -> Bool {
        isFiltering || expandedFolderIDs.contains(folderID)
    }

    func folder(id: String) -> HostFolder? {
        folders.first { $0.id == id }
    }

    var selectedFolder: HostFolder? {
        selectedID.flatMap(folder(id:))
    }

    /// Where a new folder (or host) goes: the selected folder, or the
    /// folder of the selected host.
    var folderForNewItems: String? {
        selectedFolder?.id ?? selectedEntry?.host.folderId
    }

    /// Hosts under a folder, subfolders included, as the sidebar shows them.
    func hosts(in folder: HostFolder) -> [HostEntry] {
        HostTree.hosts(in: folder.id, nodes: tree)
    }

    /// Opens every host under a folder, or asks first when there are many.
    func requestOpenAll(in folder: HostFolder, open: ([HostEntry]) -> Void) {
        let entries = hosts(in: folder)
        guard !entries.isEmpty else { return }
        if entries.count > Self.openAllConfirmThreshold {
            pendingOpenAll = entries
            pendingOpenAllFolderName = folder.name
        } else {
            open(entries)
        }
    }

    var allTags: [String] {
        HostFilter.tags(in: entries)
    }

    func entry(id: String) -> HostEntry? {
        entries.first { $0.id == id }
    }

    var selectedEntry: HostEntry? {
        selectedID.flatMap(entry(id:))
    }

    func reload() {
        guard let library else { return }
        do {
            entries = try library.entries()
            folders = try library.folders()
            let folderIDs = Set(folders.map(\.id))
            if !expandedFolderIDs.isSubset(of: folderIDs) {
                expandedFolderIDs.formIntersection(folderIDs)
            }
            // Drop a tag filter whose last host was deleted or retagged.
            if let tagFilter, !allTags.contains(where: { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }) {
                self.tagFilter = nil
            }
            onChange?()
        } catch {
            errorMessage = "Couldn't read saved hosts: \(error.localizedDescription)"
        }
    }

    /// Saves the rows chosen in the spreadsheet import. Returns a summary
    /// for the sheet, or throws.
    func importSpreadsheet(_ candidates: [HostImportCandidate], updateExisting: Bool) throws -> (added: Int, updated: Int) {
        guard let library else { throw CocoaError(.fileReadUnknown) }
        let result = try library.importHosts(candidates, updateExisting: updateExisting)
        reload()
        return result
    }

    // MARK: Editing

    /// Adds backed-up hosts and folders that aren't here yet. Returns how
    /// many hosts were added.
    func restore(_ backup: [BackupSnapshot.Host], folders: [BackupSnapshot.Folder]) throws -> Int {
        guard let library else { return 0 }
        let added = try library.restore(backup, folders: folders)
        reload()
        return added
    }

    /// Saves the draft. `password` replaces the stored Keychain password
    /// when given; nil keeps it. Switching away from password auth removes
    /// it. Returns an error message, or nil on success.
    func save(_ draft: HostDraft, id: String?, password: String?) -> String? {
        guard let library else { return errorMessage ?? "The host library isn't available." }
        do {
            let entry = try library.save(draft, id: id)
            if draft.authMethod == .password {
                if let password, !password.isEmpty {
                    try PasswordVault.save(password, hostID: entry.id, label: entry.host.name)
                }
            } else {
                PasswordVault.delete(hostID: entry.id)
            }
            reload()
            return nil
        } catch {
            reload()
            return "Couldn't save: \(error.localizedDescription)"
        }
    }

    func duplicate(_ entry: HostEntry) {
        perform("duplicate") { try $0.duplicate(id: entry.id) }
    }

    func delete(_ entry: HostEntry) {
        perform("delete") { try $0.delete(id: entry.id) }
        PasswordVault.delete(hostID: entry.id)
    }

    // MARK: Folders

    /// Creates a folder and opens its parent so it shows. Returns an error
    /// message for the sheet, or nil on success.
    func createFolder(name: String, parentId: String?) -> String? {
        guard let library else { return errorMessage ?? "The host library isn't available." }
        do {
            try library.createFolder(name: name, parentId: parentId)
            errorMessage = nil
            if let parentId { expandedFolderIDs.insert(parentId) }
            reload()
            return nil
        } catch {
            reload()
            return error.localizedDescription
        }
    }

    /// Returns an error message for the sheet, or nil on success.
    func renameFolder(_ folder: HostFolder, to name: String) -> String? {
        guard let library else { return errorMessage ?? "The host library isn't available." }
        do {
            try library.renameFolder(id: folder.id, to: name)
            errorMessage = nil
            reload()
            return nil
        } catch {
            reload()
            return error.localizedDescription
        }
    }

    /// Its hosts and subfolders move up one level.
    func deleteFolder(_ folder: HostFolder) {
        perform("delete the folder") { try $0.deleteFolder(id: folder.id) }
        if selectedID == folder.id { selectedID = nil }
    }

    /// Moves a host or a folder, by id, into a folder or (nil) the top level.
    /// Dropping an item where it already is, or a folder onto itself, does nothing.
    func move(itemID: String, toFolder folderID: String?) {
        if let moving = folder(id: itemID) {
            guard itemID != folderID, moving.parentId != folderID else { return }
            perform("move the folder") { try $0.moveFolder(id: itemID, toParent: folderID) }
        } else if let moving = entry(id: itemID) {
            guard moving.host.folderId != folderID else { return }
            perform("move the host") { try $0.moveHost(id: itemID, toFolder: folderID) }
        }
    }

    func copyHostname(_ entry: HostEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.host.hostname, forType: .string)
    }

    // MARK: Import from ~/.ssh/config

    /// On first launch with an empty library, offer the import once.
    func offerImportIfFirstRun() {
        let defaults = UserDefaults.standard
        guard entries.isEmpty, library != nil, !defaults.bool(forKey: Self.didOfferImportKey) else { return }
        importCandidates = SSHConfigFile.aliases()
        if importCandidates.isEmpty {
            defaults.set(true, forKey: Self.didOfferImportKey)
        } else {
            isImportPresented = true
        }
    }

    /// File ▸ Import from ~/.ssh/config…
    func presentImport() {
        importCandidates = SSHConfigFile.aliases()
        isImportPresented = true
    }

    var savedHostnames: Set<String> {
        Set(entries.map { $0.host.hostname.lowercased() })
    }

    func finishImport(_ aliases: [SSHConfigAlias], tag: String) {
        UserDefaults.standard.set(true, forKey: Self.didOfferImportKey)
        isImportPresented = false
        guard !aliases.isEmpty else { return }
        let trimmedTag = tag.trimmingCharacters(in: .whitespaces)
        perform("import") { try $0.importAliases(aliases, tag: trimmedTag.isEmpty ? nil : trimmedTag) }
    }

    func skipImport() {
        UserDefaults.standard.set(true, forKey: Self.didOfferImportKey)
        isImportPresented = false
    }

    // MARK: Private

    private func perform(_ action: String, _ work: (HostLibrary) throws -> Void) {
        guard let library else { return }
        do {
            try work(library)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(action): \(error.localizedDescription)"
        }
        reload()
    }
}

// MARK: - File transfer apps

/// Drag-and-drop file transfer apps that can open an `sftp://` URL.
/// Only the ones installed on this Mac are offered.
enum FileTransferApp: String, CaseIterable, Identifiable {
    case transmit = "com.panic.Transmit"
    case forkLift = "com.binarynights.ForkLift"
    case forkLift3 = "com.binarynights.ForkLift-3"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .transmit: "Transmit"
        case .forkLift, .forkLift3: "ForkLift"
        }
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
    }

    /// Installed apps, one entry per name.
    static var installed: [FileTransferApp] {
        var seen = Set<String>()
        return allCases.filter { $0.applicationURL != nil && seen.insert($0.name).inserted }
    }

    /// Opens the host in this app. Asks ssh where the host really is first
    /// (`ssh -G`), so ssh_config aliases, ports and users carry over.
    /// No password goes in the URL; the app asks or uses its own keychain.
    @MainActor
    func open(_ target: SSHTarget) async {
        guard let applicationURL else { return }
        let effective = await ReachabilityProbe.effectiveConfig(for: target)
        let url = SSHTarget.sftpURL(
            host: effective?.hostname ?? target.host,
            port: effective?.port ?? target.port,
            user: effective?.user ?? target.user
        )
        guard let url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration)
    }
}
