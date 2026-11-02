import SwiftUI
import ThreeTermCore

/// Add or edit a saved host.
struct HostFormSheet: View {
    let entry: HostEntry?
    /// Saves the draft and returns an error message, or nil on success.
    let onSave: (HostDraft) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: HostDraft
    @State private var showErrors = false
    @State private var saveError: String?
    @State private var probeMessage: String?
    @State private var isProbing = false

    init(entry: HostEntry?, onSave: @escaping (HostDraft) -> String?) {
        self.entry = entry
        self.onSave = onSave
        _draft = State(initialValue: entry.map(HostDraft.init(entry:)) ?? HostDraft())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    field("Name", text: $draft.name, prompt: "Defaults to the host", error: .name)
                    field("Host", text: $draft.hostname, prompt: "IP, DNS name, or ssh_config alias", error: .hostname)
                    field("Port", text: $draft.port, prompt: "22, or from ssh_config", error: .port)
                    field("User", text: $draft.username, prompt: "From ssh_config, or your Mac user", error: .username)
                    field("Tags", text: $draft.tags, prompt: "proxmox, lab", error: .tags)
                    Toggle("Log every session to this host", isOn: $draft.logByDefault)
                } header: {
                    Text(entry == nil ? "New Host" : "Edit Host")
                } footer: {
                    Text(commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

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
                    .tint(Brand.red)
            }
            .padding(20)
        }
        .frame(width: 480)
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
        if let message = onSave(draft) {
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
