import SwiftUI
import SevenTermCore

/// ⌘T: connect to any host without saving it, or open a serial port.
struct QuickConnectSheet: View {
    @Environment(\.chrome) private var chrome
    let connect: (SSHTarget, TerminalSession.Kind) -> Void
    let openSerial: (String, SerialSettings) -> Void

    private enum Mode: String, CaseIterable {
        case ssh = "SSH"
        case serial = "Serial"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SerialPortList.self) private var serialPorts
    @AppStorage("quickConnectMode") private var mode = Mode.ssh
    @State private var text = ""
    @State private var portPath: String?
    @State private var settings = SerialSettings()
    @AppStorage("quickConnectBaud") private var lastBaud = 9600
    @FocusState private var isFocused: Bool

    private var target: SSHTarget? { SSHTarget.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New Connection")
                    .font(.headline)
                Spacer()
                Picker("Type", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            switch mode {
            case .ssh: sshFields
            case .serial: serialFields
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if mode == .ssh {
                    Button("SFTP") { submit(.files) }
                        .disabled(target == nil)
                        .help("Browse files over SFTP instead of opening a shell")
                    Button("Connect") { submit(.ssh) }
                        .keyboardShortcut(.defaultAction)
                        .tint(chrome.accent)
                        .disabled(target == nil)
                } else {
                    Button("Open") { submitSerial() }
                        .keyboardShortcut(.defaultAction)
                        .tint(chrome.accent)
                        .disabled(selectedPort == nil || settings.problem != nil)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            isFocused = true
            settings.baudRate = lastBaud
            portPath = portPath ?? serialPorts.ports.first?.path
        }
        .onChange(of: serialPorts.ports) {
            // A newly plugged-in adapter is the one you want.
            if selectedPort == nil { portPath = serialPorts.ports.last?.path }
        }
    }

    // MARK: SSH

    private var sshFields: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
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

    // MARK: Serial

    private var selectedPort: SerialPortInfo? {
        serialPorts.ports.first { $0.path == portPath }
    }

    @ViewBuilder
    private var serialFields: some View {
        if serialPorts.ports.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("No serial adapters found", systemImage: "cable.connector")
                    .foregroundStyle(.secondary)
                Text("Plug in a USB console cable; it appears here by itself. FTDI and CH340 cables need no driver. Prolific and Silicon Labs adapters may need the maker's driver: check System Information ▸ USB for the chip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        } else {
            Form {
                Picker("Port", selection: $portPath) {
                    ForEach(serialPorts.ports) { port in
                        Text(port.displayName).tag(String?.some(port.path))
                    }
                }
                Picker("Speed", selection: $settings.baudRate) {
                    ForEach(SerialSettings.commonRates, id: \.self) { Text("\($0)").tag($0) }
                }
                HStack {
                    Picker("Data", selection: $settings.dataBits) {
                        ForEach([8, 7, 6, 5], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Parity", selection: $settings.parity) {
                        Text("None").tag(SerialSettings.Parity.none)
                        Text("Even").tag(SerialSettings.Parity.even)
                        Text("Odd").tag(SerialSettings.Parity.odd)
                    }
                    Picker("Stop", selection: $settings.stopBits) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                }
                Picker("Flow control", selection: $settings.flowControl) {
                    Text("None").tag(SerialSettings.FlowControl.none)
                    Text("RTS/CTS (hardware)").tag(SerialSettings.FlowControl.hardware)
                    Text("XON/XOFF (software)").tag(SerialSettings.FlowControl.software)
                }
            }
            .formStyle(.columns)
            Text(selectedPort.map { "\($0.path) · \(settings.summary)" } ?? "Choose a port.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func submitSerial() {
        guard let port = selectedPort, settings.problem == nil else { return }
        lastBaud = settings.baudRate
        openSerial(port.path, settings)
        dismiss()
    }
}
