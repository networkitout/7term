import SwiftUI

/// Settings ▸ General: This Mac, the local terminal.
struct GeneralSettings: View {
    @AppStorage(LocalTerminalSettings.showInSidebarKey) private var showThisMac = true
    @AppStorage(LocalTerminalSettings.logByDefaultKey) private var logLocalByDefault = false

    var body: some View {
        Form {
            Section {
                Toggle("Show This Mac in the sidebar", isOn: $showThisMac)
                Toggle("Log local terminals by default", isOn: $logLocalByDefault)
            } header: {
                Text("Local terminal")
            } footer: {
                Text("This Mac opens your login shell in your home folder. Hidden, it's still in File ▸ New Local Terminal (⇧⌘T).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
