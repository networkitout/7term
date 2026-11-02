import AppKit
import SwiftUI
import SevenTermCore

/// Add or edit a saved host.
struct HostFormSheet: View {
    @Environment(\.chrome) private var chrome
    let entry: HostEntry?
    /// Saves the draft and a new Keychain password (nil keeps the stored
    /// one), and returns an error message, or nil on success.
    let onSave: (HostDraft, String?) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: HostDraft
    @State private var showErrors = false
    @State private var saveError: String?
    @State private var probeMessage: String?
    @State private var isProbing = false
    @State private var password = ""
    private let hasStoredPassword: Bool

    init(entry: HostEntry?, onSave: @escaping (HostDraft, String?) -> String?) {
        self.entry = entry
        self.onSave = onSave
        _draft = State(initialValue: entry.map(HostDraft.init(entry:)) ?? HostDraft())
        hasStoredPassword = entry.map { PasswordVault.exists(hostID: $0.id) } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Two columns, so the form fits a short window without scrolling:
            // where the host is on the left, how to sign in on the right.
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section {
                        field("Name", text: $draft.name, prompt: "Defaults to the host", error: .name)
                        field("Host", text: $draft.hostname, prompt: "IP, DNS name, or alias", error: .hostname)
                        field("Port", text: $draft.port, prompt: "22, or from ssh_config", error: .port)
                        field("User", text: $draft.username, prompt: "From ssh_config", error: .username)
                        field("Tags", text: $draft.tags, prompt: "proxmox, lab", error: .tags)
                        Toggle("Log every session", isOn: $draft.logByDefault)
                    } header: {
                        Text(entry == nil ? "New Host" : "Edit Host")
                    } footer: {
                        Text(commandPreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .formStyle(.grouped)
                .frame(width: 390)

                Form {
                    Section("Authentication") {
                        Picker("Sign in with", selection: $draft.authMethod) {
                            Text("Agent / ssh_config").tag(AuthMethod.automatic)
                            Text("Key file").tag(AuthMethod.keyFile)
                            Text("Password in Keychain").tag(AuthMethod.password)
                        }
                        switch draft.authMethod {
                        case .automatic:
                            note("ssh tries your agent (1Password, Secretive, ssh-agent) and ~/.ssh/config, then asks in the terminal.")
                        case .keyFile:
                            HStack(alignment: .firstTextBaseline) {
                                field("Key", text: $draft.identityFile, prompt: "~/.ssh/id_ed25519", error: .identityFile)
                                Button("Choose…", action: chooseKey)
                            }
                            note("Only this key is offered (IdentitiesOnly). A passphrase, if any, is asked for in a dialog.")
                        case .password:
                            SecureField(
                                "Password",
                                text: $password,
                                prompt: Text(hasStoredPassword ? "Stored. Type to replace." : "Saved to your Keychain")
                            )
                            note("Touch ID is required each time 7 Term uses it. Never written to the host list, backups or logs, and never typed into the terminal.")
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 340)
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            if let probeMessage {
                Text(probeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button(isProbing ? "Testing…" : "Test Reachability") {
                    Task { await probe() }
                }
                .disabled(draft.target == nil || isProbing)
                .help("Checks that the port accepts a TCP connection. Never logs in.")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add Host" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .tint(chrome.accent)
            }
            .padding(20)
        }
        .frame(width: 730)
        .onChange(of: draft.hostname) { probeMessage = nil }
        .onChange(of: draft.port) { probeMessage = nil }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, error: HostDraft.Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: text, prompt: Text(prompt))
                .autocorrectionDisabled()
            if showErrors, let message = draft.errors[error] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh", directoryHint: .isDirectory)
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the private key (not the .pub file)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        draft.identityFile = path.hasPrefix(home + "/") ? "~" + String(path.dropFirst(home.count)) : path
    }

    private var commandPreview: String {
        guard let target = draft.target else { return "ssh …" }
        return "ssh " + target.sshArguments.joined(separator: " ")
    }

    private func save() {
        if draft.trimmedName.isEmpty {
            draft.name = draft.hostname.trimmingCharacters(in: .whitespaces)
        }
        guard draft.isValid else {
            showErrors = true
            return
        }
        if draft.authMethod == .password, password.isEmpty, !hasStoredPassword {
            saveError = "Enter the password to store in the Keychain."
            return
        }
        if let message = onSave(draft, password.isEmpty ? nil : password) {
            saveError = message
        } else {
            dismiss()
        }
    }

    private func probe() async {
        guard let target = draft.target else { return }
        isProbing = true
        probeMessage = nil
        probeMessage = await ReachabilityProbe.describe(target)
        isProbing = false
    }
}
