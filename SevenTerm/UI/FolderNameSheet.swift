import SwiftUI
import SevenTermCore

/// Names a new folder, or renames one.
struct FolderNameSheet: View {
    @Environment(\.chrome) private var chrome
    @Environment(\.dismiss) private var dismiss
    let request: FolderNameRequest
    /// Saves the name; returns an error message, or nil to close.
    let save: (String) -> String?

    @State private var name = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    private var isRename: Bool {
        if case .rename = request { true } else { false }
    }

    private var canSave: Bool { HostFolder.cleanName(name) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isRename ? "Rename Folder" : "New Folder")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(submit)
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRename ? "Rename" : "Create", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .tint(chrome.accent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if case .rename(let folder) = request { name = folder.name }
            isFocused = true
        }
        .onChange(of: name) { error = nil }
    }

    private func submit() {
        guard canSave else { return }
        if let message = save(name) {
            error = message
        } else {
            dismiss()
        }
    }
}
