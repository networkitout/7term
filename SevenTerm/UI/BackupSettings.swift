import SwiftUI

/// Settings ▸ Backup.
struct BackupSettings: View {
    @Environment(BackupManager.self) private var backup

    var body: some View {
        @Bindable var backup = backup

        Form {
            Section {
                Toggle("Back up hosts and settings to iCloud Drive", isOn: $backup.isEnabled)
                LabeledContent("Last backup", value: lastBackupText)
                if let error = backup.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Back Up Now") { backup.backupNow() }
                        .disabled(!backup.isICloudDriveAvailable)
                    Button("Show in Finder") { backup.showInFinder() }
                    Spacer()
                    Button("Restore…") { backup.chooseAndRestore() }
                }
            } footer: {
                Text("Saved to iCloud Drive/7 Term/ a few seconds after any change, with a dated copy per day for 30 days. Includes hosts, tags, key paths, theme and text size. Never includes passwords, keys or session logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var lastBackupText: String {
        guard let date = backup.lastBackup else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
