import AppKit
import Foundation
import Observation
import ThreeTermCore

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
    /// The sidebar row selected, as "<section>|<host id>" (a host with two
    /// tags has a row in each section).
    var selectedRowID: String?
    /// A host waiting for the delete confirmation.
    var pendingDelete: HostEntry?
    var isImportPresented = false
    private(set) var importCandidates: [SSHConfigAlias] = []

    private let library: HostLibrary?
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

    /// ~/Library/Application Support/3 Term/hosts.sqlite
    static var libraryURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "3 Term", directoryHint: .isDirectory)
            .appending(path: "hosts.sqlite", directoryHint: .notDirectory)
    }

    var sections: [HostFilter.Section] {
        HostFilter.sections(HostFilter.filter(entries, query: query))
    }

    func entry(id: String) -> HostEntry? {
        entries.first { $0.id == id }
    }

    static func rowID(section: HostFilter.Section, entry: HostEntry) -> String {
        section.id + "|" + entry.id
    }

    func entry(forRow rowID: String?) -> HostEntry? {
        guard let rowID, let hostID = rowID.split(separator: "|").last else { return nil }
        return entry(id: String(hostID))
    }

    var selectedEntry: HostEntry? {
        entry(forRow: selectedRowID)
    }

    func reload() {
        guard let library else { return }
        do {
            entries = try library.entries()
        } catch {
            errorMessage = "Couldn't read saved hosts: \(error.localizedDescription)"
        }
    }

    // MARK: Editing

    /// Saves the draft. Returns an error message, or nil on success.
    func save(_ draft: HostDraft, id: String?) -> String? {
        guard let library else { return errorMessage ?? "The host library isn't available." }
        do {
            try library.save(draft, id: id)
            reload()
            return nil
        } catch {
            return "Couldn't save: \(error.localizedDescription)"
        }
    }

    func duplicate(_ entry: HostEntry) {
        perform("duplicate") { try $0.duplicate(id: entry.id) }
    }

    func delete(_ entry: HostEntry) {
        perform("delete") { try $0.delete(id: entry.id) }
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
