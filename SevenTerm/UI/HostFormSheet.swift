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
    @Environment(SerialPortList.self) private var serialPorts
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
            HStack {
                Spacer()
                Picker("Type", selection: $draft.kind) {
                    Text("SSH").tag(HostKind.ssh)
                    Text("Serial").tag(HostKind.serial)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("A host you reach with ssh, or a console on a serial port")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            if draft.kind == .serial {
                serialColumns
            } else {
                sshColumns
            }
            footer
        }
        .frame(width: 730)
        .onChange(of: draft.hostname) { probeMessage = nil }
        .onChange(of: draft.port) { probeMessage = nil }
    }

    private var sshColumns: some View {
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
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                if draft.kind == .ssh {
                    Button(isProbing ? "Testing…" : "Test Reachability") {
                        Task { await probe() }
                    }
                    .disabled(draft.target == nil || isProbing)
                    .help("Checks that the port accepts a TCP connection. Never logs in.")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add Host" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .tint(chrome.accent)
            }
            .padding(20)
        }
    }

    // MARK: Serial

    private var serialColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section {
                    field("Name", text: $draft.name, prompt: "Defaults to the adapter", error: .name)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Port", selection: portSelection) {
                            if serialPorts.ports.isEmpty && draft.serialPath.isEmpty {
                                Text("No adapters connected").tag("")
                            }
                            ForEach(serialPorts.ports) { port in
                                Text(port.displayName).tag(port.path)
                            }
                            if !draft.serialPath.isEmpty, !serialPorts.ports.contains(where: { $0.path == draft.serialPath }) {
                                Text("\((draft.serialPath as NSString).lastPathComponent) (not connected)").tag(draft.serialPath)
                            }
                        }
                        if showErrors, let message = draft.errors[.serialPort] {
                            Text(message).font(.caption).foregroundStyle(.red)
                        }
                    }
                    field("Tags", text: $draft.tags, prompt: "console, lab", error: .tags)
                    Toggle("Log every session", isOn: $draft.logByDefault)
                } header: {
                    Text(entry == nil ? "New Serial Console" : "Edit Serial Console")
                } footer: {
                    Text(serialFooter)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .frame(width: 390)

            Form {
                Section("Line settings") {
                    Picker("Speed", selection: $draft.serial.settings.baudRate) {
                        ForEach(SerialSettings.commonRates, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Data bits", selection: $draft.serial.settings.dataBits) {
                        ForEach([8, 7, 6, 5], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Parity", selection: $draft.serial.settings.parity) {
                        Text("None").tag(SerialSettings.Parity.none)
                        Text("Even").tag(SerialSettings.Parity.even)
                        Text("Odd").tag(SerialSettings.Parity.odd)
                    }
                    Picker("Stop bits", selection: $draft.serial.settings.stopBits) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                    Picker("Flow control", selection: $draft.serial.settings.flowControl) {
                        Text("None").tag(SerialSettings.FlowControl.none)
                        Text("RTS/CTS").tag(SerialSettings.FlowControl.hardware)
                        Text("XON/XOFF").tag(SerialSettings.FlowControl.software)
                    }
                    note("9600 8N1, no flow control suits Cisco, Juniper, Aruba and most consoles. A Raspberry Pi uses 115200.")
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
        }
        .onAppear {
            if draft.serialPath.isEmpty, let first = serialPorts.ports.first { choose(first) }
        }
    }

    /// Picking a port also remembers the adapter's serial number and model,
    /// so the entry still finds it if macOS renames the port.
    private var portSelection: Binding<String> {
        Binding {
            draft.serialPath
        } set: { path in
            if let port = serialPorts.ports.first(where: { $0.path == path }) {
                choose(port)
            } else {
                draft.serialPath = path
            }
        }
    }

    private func choose(_ port: SerialPortInfo) {
        draft.serialPath = port.path
        draft.serial.usbSerialNumber = port.serialNumber
        draft.serial.vendorID = port.vendorID
        draft.serial.productID = port.productID
    }

    private var serialFooter: String {
        guard !draft.serialPath.isEmpty else { return "Plug in the console cable to choose its port." }
        return "\(draft.serialPath) · \(draft.serial.settings.summary)"
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
            if draft.kind == .serial {
                draft.name = serialPorts.ports.first { $0.path == draft.serialPath }?.displayName
                    ?? (draft.serialPath as NSString).lastPathComponent
            } else {
                draft.name = draft.hostname.trimmingCharacters(in: .whitespaces)
            }
        }
        guard draft.isValid else {
            showErrors = true
            return
        }
        // A console has no sign-in; this also removes a Keychain password
        // left from when the entry was an ssh host.
        if draft.kind == .serial { draft.authMethod = .automatic }
        if draft.kind == .ssh, draft.authMethod == .password, password.isEmpty, !hasStoredPassword {
            saveError = "Enter the password to store in the Keychain."
            return
        }
        if let message = onSave(draft, draft.kind == .ssh && !password.isEmpty ? password : nil) {
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
