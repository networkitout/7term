import Foundation

/// Carries data over from when the app was called "3 Term" (bundle
/// com.networkitout.threeterm). Runs once, at launch, before anything reads
/// settings or the host library:
/// - preferences (theme, font, size, import and logging flags)
/// - ~/Library/Application Support/3 Term → 7 Term (saved hosts, themes)
/// - ~/Documents/3 Term → 7 Term (session logs), only if logging was used,
///   so people who never logged never see the Documents permission prompt
/// Nothing is overwritten: a move only happens when the new location is empty.
enum LegacyMigration {
    static let oldBundleID = "com.networkitout.threeterm"
    static let oldFolderName = "3 Term"
    static let newFolderName = "7 Term"
    private static let doneKey = "migratedFrom3Term"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        if let old = defaults.persistentDomain(forName: oldBundleID) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        if defaults.string(forKey: "terminalPalette") == "3term" {
            defaults.set("7term", forKey: "terminalPalette")
        }

        moveFolder(in: URL.applicationSupportDirectory)
        if defaults.bool(forKey: "hasUsedLogging") {
            moveFolder(in: URL.documentsDirectory)
        }
        defaults.set(true, forKey: doneKey)
    }

    private static func moveFolder(in base: URL) {
        let fileManager = FileManager.default
        let old = base.appending(path: oldFolderName, directoryHint: .isDirectory)
        let new = base.appending(path: newFolderName, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.moveItem(at: old, to: new)
    }
}
