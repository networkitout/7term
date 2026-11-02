import AppKit
import Foundation
import ThreeTermCore

/// Where session logs go: ~/Documents/3 Term/Logs/<host>/.
///
/// macOS asks once before an app reads or writes ~/Documents. To avoid that
/// prompt for people who never log, 3 Term only touches the folder after
/// logging has been used at least once.
enum LogLocation {
    static var folder: URL {
        URL.documentsDirectory.appending(path: "3 Term/Logs", directoryHint: .isDirectory)
    }

    private static let usedKey = "hasUsedLogging"

    static func noteLoggingUsed() {
        UserDefaults.standard.set(true, forKey: usedKey)
    }

    /// "~/Documents/3 Term/Logs/…" for display.
    static func abbreviated(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    /// Finishes logs left open by a crash and writes missing readable copies.
    static func repairInBackground() {
        guard UserDefaults.standard.bool(forKey: usedKey) else { return }
        let logsFolder = Self.folder
        Task.detached(priority: .utility) {
            _ = LogMaintenance.repair(folder: logsFolder)
        }
    }

    static func writeReadableCopyInBackground(for logURL: URL) {
        Task.detached(priority: .utility) {
            try? LogFiles.writeReadableCopy(for: logURL)
        }
    }

    /// Selects `url` in Finder, or opens the logs folder.
    @MainActor static func reveal(_ url: URL?) {
        if let url, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
