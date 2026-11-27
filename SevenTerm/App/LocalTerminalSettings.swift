import Foundation

/// Settings ▸ General for This Mac, the local terminal. The keys are shared
/// by the settings view (`@AppStorage`), the sidebar and the session store.
/// Kept out of iCloud backups: they're about this Mac only.
enum LocalTerminalSettings {
    /// Show the This Mac row at the top of the sidebar. On unless turned off.
    static let showInSidebarKey = "localTerminal.showInSidebar"
    /// Start logging as soon as a local tab opens. Off unless turned on.
    static let logByDefaultKey = "localTerminal.logByDefault"

    static var logByDefault: Bool {
        UserDefaults.standard.bool(forKey: logByDefaultKey)
    }
}
