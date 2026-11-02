import AppKit
import Foundation
import Observation
import SevenTermCore

/// What the host sheet is editing.
enum HostEditorRequest: Identifiable {
    case new
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
}

/// The app's view of the saved host library: the entries, the filter text,
/// and which sheets are open.
@MainActor
@Observable
final class HostDirectory {
    private(set) var entries: [HostEntry] = []
    private(set) var errorMessage: String?
    var query = ""
    var editor: HostEditorRequest?
    /// The selected host in the sidebar.
    var selectedHostID: String?
    /// Show only hosts with this tag; nil shows all.
    var tagFilter: String?
    /// A host waiting for the delete confirmation.
    var pendingDelete: HostEntry?
    var isImportPresented = false
    /// The spreadsheet (CSV or pasted cells) import sheet.
    var isSpreadsheetImportPresented = false
    private(set) var importCandidates: [SSHConfigAlias] = []

    private let library: HostLibrary?
    /// Called after the host list changes; the backup uses it.
    @ObservationIgnored var onChange: (() -> Void)?
    private static let didOfferImportKey = "didOfferSSHConfigImport"

    init() {
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

    /// What the sidebar shows: each host once, in name order.
    var visibleEntries: [HostEntry] {
        HostFilter.filter(entries, query: query, tag: tagFilter)
    }

    var allTags: [String] {
        HostFilter.tags(in: entries)
    }

    func entry(id: String) -> HostEntry? {
        entries.first { $0.id == id }
    }

    var selectedEntry: HostEntry? {
        selectedHostID.flatMap(entry(id:))
    }

    func reload() {
        guard let library else { return }
        do {
            entries = try library.entries()
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

    /// Adds backed-up hosts that aren't here yet. Returns how many were added.
    func restore(_ backup: [BackupSnapshot.Host]) throws -> Int {
        guard let library else { return 0 }
        let added = try library.restore(backup)
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
