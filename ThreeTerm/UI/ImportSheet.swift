import SwiftUI
import ThreeTermCore

/// Offers the Host aliases in ~/.ssh/config as saved hosts.
struct ImportSheet: View {
    let aliases: [SSHConfigAlias]
    let savedHostnames: Set<String>
    let onImport: (_ aliases: [SSHConfigAlias], _ tag: String) -> Void
    let onSkip: () -> Void

    @State private var chosen: Set<String>
    @State private var tag = ""

    init(
        aliases: [SSHConfigAlias],
        savedHostnames: Set<String>,
        onImport: @escaping ([SSHConfigAlias], String) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.aliases = aliases
        self.savedHostnames = savedHostnames
        self.onImport = onImport
        self.onSkip = onSkip
        let importable = aliases.filter { !savedHostnames.contains($0.alias.lowercased()) }
        _chosen = State(initialValue: Set(importable.map(\.alias)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Hosts from ~/.ssh/config")
                .font(.headline)

            if aliases.isEmpty {
                Text("No Host aliases found in ~/.ssh/config or the files it includes.")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Close", action: onSkip)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Each alias is saved as a host. ssh still reads your config, so keys, ProxyJump and other settings keep applying.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                List(aliases) { alias in
                    Toggle(isOn: binding(for: alias)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(alias.alias)
                            Text(detail(for: alias))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isSaved(alias))
                }
                .frame(minHeight: 160, maxHeight: 320)

                TextField("Tag imported hosts", text: $tag, prompt: Text("Optional, e.g. lab"))

                HStack {
                    Button(chosen.count == importableCount ? "Select None" : "Select All") {
                        if chosen.count == importableCount {
                            chosen.removeAll()
                        } else {
                            chosen = Set(aliases.filter { !isSaved($0) }.map(\.alias))
                        }
                    }
                    .disabled(importableCount == 0)
                    Spacer()
                    Button("Skip", action: onSkip)
                        .keyboardShortcut(.cancelAction)
                    Button(chosen.count == 1 ? "Import 1 Host" : "Import \(chosen.count) Hosts") {
                        onImport(aliases.filter { chosen.contains($0.alias) }, tag)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var importableCount: Int {
        aliases.filter { !isSaved($0) }.count
    }

    private func isSaved(_ alias: SSHConfigAlias) -> Bool {
        savedHostnames.contains(alias.alias.lowercased())
    }

    private func binding(for alias: SSHConfigAlias) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(alias.alias) },
            set: { isOn in
                if isOn { chosen.insert(alias.alias) } else { chosen.remove(alias.alias) }
            }
        )
    }

    private func detail(for alias: SSHConfigAlias) -> String {
        if isSaved(alias) { return "Already saved" }
        var parts: [String] = []
        if let hostName = alias.hostName { parts.append(hostName) }
        if let user = alias.user { parts.append("user " + user) }
        if let port = alias.port { parts.append("port \(port)") }
        return parts.isEmpty ? "No HostName set; ssh uses the alias as the host" : parts.joined(separator: " · ")
    }
}
