import SwiftUI
import ThreeTermCore

/// Milestone 1's way in: type a destination, see the exact ssh command, connect.
/// The saved host list replaces this as the main path in milestone 2.
struct QuickConnectSheet: View {
    let connect: (SSHTarget) -> Void

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
                .onSubmit(submit)
            Text(hint)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: submit)
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

    private func submit() {
        guard let target else { return }
        connect(target)
        dismiss()
    }
}
