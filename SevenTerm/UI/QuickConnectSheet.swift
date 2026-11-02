import SwiftUI
import SevenTermCore

/// Milestone 1's way in: type a destination, see the exact ssh command, connect.
/// The saved host list replaces this as the main path in milestone 2.
struct QuickConnectSheet: View {
    let connect: (SSHTarget, TerminalSession.Kind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var target: SSHTarget? { SSHTarget.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Connection")
                .font(.headline)
            TextField("user@host:port", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .focused($isFocused)
                .onSubmit { submit(.ssh) }
            Text(hint)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("SFTP") { submit(.sftp) }
                    .disabled(target == nil)
                    .help("Open an sftp session instead of a shell")
                Button("Connect") { submit(.ssh) }
                    .keyboardShortcut(.defaultAction)
                    .tint(Brand.red)
                    .disabled(target == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { isFocused = true }
    }

    private var hint: String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Aliases from ~/.ssh/config work here too."
        }
        guard let target else { return "Use host, user@host, or user@host:port." }
        return "ssh " + target.sshArguments.joined(separator: " ")
    }

    private func submit(_ kind: TerminalSession.Kind) {
        guard let target else { return }
        connect(target, kind)
        dismiss()
    }
}
