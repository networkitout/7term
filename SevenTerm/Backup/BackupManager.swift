import AppKit
import Foundation
import Observation
import SevenTermCore
import UniformTypeIdentifiers

/// Keeps a JSON snapshot of the host list and settings in iCloud Drive
/// (iCloud Drive/7 Term/7term-backup.json, plus one dated copy per day for
/// 30 days). It writes a couple of seconds after any change. With iCloud
/// Advanced Data Protection on, iCloud Drive content is end-to-end encrypted.
/// Passwords, keys and logs are never included.
@MainActor
@Observable
final class BackupManager {
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { scheduleBackup() }
        }
    }
    private(set) var lastBackup: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let hosts: HostDirectory
    @ObservationIgnored private let appearance: Appearance
    @ObservationIgnored private var pending: Task<Void, Never>?

    private enum Keys {
        static let enabled = "backupEnabled"
        static let lastBackup = "lastBackup"
    }

    init(hosts: HostDirectory, appearance: Appearance) {
        self.hosts = hosts
        self.appearance = appearance
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        lastBackup = defaults.object(forKey: Keys.lastBackup) as? Date
    }

    /// ~/Library/Mobile Documents/com~apple~CloudDocs, which is iCloud Drive's
    /// root when iCloud Drive is on.
    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
    }

    var folder: URL {
        Self.iCloudDrive.appending(path: "7 Term", directoryHint: .isDirectory)
    }

    var isICloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: Self.iCloudDrive.path)
    }

    /// Debounced: several quick edits produce one write.
    func scheduleBackup() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.backupNow()
        }
    }

    func backupNow() {
        guard isICloudDriveAvailable else {
            lastError = "iCloud Drive is turned off on this Mac."
            return
        }
        let snapshot = BackupSnapshot(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            hosts: hosts.entries,
            settings: .init(
                paletteID: appearance.paletteID,
                fontFamily: appearance.fontFamily,
                fontSize: appearance.fontSize
            ),
            importedPalettes: appearance.importedPalettes
        )
        do {
            try BackupStore(folder: folder).write(snapshot)
            lastBackup = snapshot.exportedAt
            UserDefaults.standard.set(snapshot.exportedAt, forKey: Keys.lastBackup)
            lastError = nil
        } catch {
            lastError = "Backup failed: \(error.localizedDescription)"
        }
    }

    func showInFinder() {
        let latest = BackupStore(folder: folder).latestURL
        if FileManager.default.fileExists(atPath: latest.path) {
            NSWorkspace.shared.activateFileViewerSelecting([latest])
        } else if isICloudDriveAvailable {
            NSWorkspace.shared.open(Self.iCloudDrive)
        }
    }

    /// File ▸ Restore from Backup…: pick a backup, confirm, then add the hosts
    /// that are missing and apply the saved settings. Nothing already in
    /// 7 Term is overwritten.
    func chooseAndRestore() {
        let panel = NSOpenPanel()
        panel.directoryURL = isICloudDriveAvailable ? folder : nil
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a 7 Term backup (7term-backup.json, or a dated copy in History)."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let snapshot: BackupSnapshot
        do {
            snapshot = try BackupSnapshot.decode(Data(contentsOf: url))
        } catch {
            alert("Couldn't read that backup", error.localizedDescription)
            return
        }

        let missing = snapshot.hosts.filter { hosts.entry(id: $0.id) == nil }
        let confirm = NSAlert()
        confirm.messageText = "Restore from this backup?"
        let date = snapshot.exportedAt.formatted(date: .abbreviated, time: .shortened)
        confirm.informativeText = """
            Made \(date). Adds \(missing.count) of its \(snapshot.hosts.count) hosts \
            (hosts already in 7 Term are left as they are) and applies its theme and text size.
            Passwords aren't in backups: re-enter them for hosts that use the Keychain.
            """
        confirm.addButton(withTitle: "Restore")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            let added = try hosts.restore(snapshot.hosts)
            appearance.applyBackup(snapshot.settings, palettes: snapshot.importedPalettes)
            alert("Restored", added == 1 ? "Added 1 host." : "Added \(added) hosts.")
        } catch {
            alert("Restore failed", error.localizedDescription)
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
