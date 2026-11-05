import AppKit
import Observation
import SwiftTerm
import SevenTermCore

/// One tab: an ssh or sftp process in a pseudo-terminal, and the view that shows it.
///
/// 7 Term runs its own `LocalProcess` and feeds a plain `TerminalView`, instead
/// of using SwiftTerm's `LocalProcessTerminalView`. That keeps every output
/// byte passing through `received(_:from:)`, where it is also copied to the
/// session log while logging is on.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    enum State: Equatable {
        case idle
        case running
        case ended(exitCode: Int32?)
        case failed(String)
    }

    /// What runs in the tab. All use the system OpenSSH tools: a shell, the
    /// sftp> prompt, or the file browser (ssh's sftp subsystem).
    enum Kind: String, Equatable {
        case ssh, sftp, files, serial

        var executable: String { "/usr/bin/\(rawValue)" }

        /// Fail within this many seconds when nothing answers, instead of
        /// waiting out the system TCP timeout (about 75 seconds) in silence.
        static let connectTimeoutSeconds = 15

        func arguments(for target: SSHTarget) -> [String] {
            let timeout = ["-o", "ConnectTimeout=\(Self.connectTimeoutSeconds)"]
            switch self {
            case .ssh: return timeout + target.sshArguments
            case .sftp: return timeout + target.sftpArguments
            case .files: return timeout + FileBrowser.sshArguments(for: target)
            case .serial: return []
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let target: SSHTarget
    /// Set when the host's password is in the Keychain: ssh then asks 7 Term
    /// for it (Touch ID) instead of prompting in the terminal.
    let keychainHost: (id: String, name: String)?
    /// The saved host's name, when the tab came from the host list.
    let name: String?
    /// Start logging whenever this session connects.
    let logByDefault: Bool
    private(set) var state: State = .idle
    private(set) var remoteTitle: String?
    private(set) var isLogging = false
    /// The segment being written, or the last one written.
    private(set) var lastLogURL: URL?

    @ObservationIgnored let terminalView: TerminalView
    /// Set for a file browser tab, which shows this instead of the terminal.
    let files: FileBrowser?
    /// Set for a serial console tab: the port and its settings.
    let serial: (path: String, settings: SerialSettings)?
    @ObservationIgnored private var serialPort: SerialPort?
    @ObservationIgnored private var process: LocalProcess?
    @ObservationIgnored private var bridge: ProcessBridge?
    @ObservationIgnored private var logWriter: SessionLogWriter?
    @ObservationIgnored private var logSegmentCount = 0

    /// The user's own name for this tab (Rename Tab…). Overrides the default
    /// label, including the remote shell's title; nil or blank restores it.
    /// In memory only, and kept across reconnects. Set it with `rename(to:)`.
    private(set) var customTitle: String?
    /// A colour to tell tabs to the same host apart. In memory only.
    var tabColor: TabColor = .none

    private var label: TabLabel {
        TabLabel(
            kind: TabLabel.Kind(rawValue: kind.rawValue) ?? .ssh,
            savedName: name,
            remoteTitle: remoteTitle,
            destination: target.displayName,
            baudRate: serial?.settings.baudRate,
            customTitle: customTitle
        )
    }

    /// What the tab shows: the custom name, or else the default label
    /// (see `TabLabel`).
    var title: String { label.title }

    /// The label the tab would show without a custom name.
    var defaultTitle: String { label.defaultTitle }

    /// Gives the tab the user's own name; an empty name restores the default.
    func rename(to text: String?) {
        customTitle = TabLabel.normalizedCustomTitle(text)
    }

    init(
        kind: Kind = .ssh,
        target: SSHTarget,
        name: String? = nil,
        logByDefault: Bool = false,
        keychainHost: (id: String, name: String)? = nil,
        serial: (path: String, settings: SerialSettings)? = nil,
        appearance: Appearance
    ) {
        self.serial = serial
        self.kind = kind
        self.target = target
        self.keychainHost = keychainHost
        self.name = name
        self.logByDefault = logByDefault
        terminalView = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        files = kind == .files ? FileBrowser(target: target, keychainHost: keychainHost) : nil
        appearance.apply(to: terminalView)
        terminalView.terminalDelegate = self
    }

    func start() {
        guard state != .running else { return }

        if let files {
            state = .running
            files.onEnded = { [weak self] message in self?.filesEnded(message) }
            files.log = { [weak self] line in self?.appendLogLine(line) }
            if logByDefault { startLogging() }
            Task { await files.connect() }
            return
        }

        if let serial {
            openSerial(serial.path, serial.settings)
            return
        }

        // A fresh bridge per launch, so a late callback from an old process
        // can never change the state of a new one.
        let bridge = ProcessBridge(owner: self)
        bridge.updateWindowSize(currentWindowSize())
        let process = LocalProcess(delegate: bridge, dispatchQueue: .main)
        self.bridge = bridge
        self.process = process
        remoteTitle = nil
        state = .running

        note("connecting to \(target.displayName) with \(kind.rawValue)…")
        var environment = ChildEnvironment.make(from: ProcessInfo.processInfo.environment)
        var arguments = kind.arguments(for: target)
        if let keychainHost {
            environment += AskPass.environment(hostID: keychainHost.id, hostName: keychainHost.name)
            // One try with the stored password; a wrong one fails instead of
            // asking for Touch ID three times.
            arguments.insert(contentsOf: ["-o", "NumberOfPasswordPrompts=1"], at: 0)
        }
        process.startProcess(
            executable: kind.executable,
            args: arguments,
            environment: environment,
            execName: kind.rawValue
        )
        if logByDefault { startLogging() }
    }

    func restart() {
        guard state != .running else { return }
        if files != nil {
            start()
            return
        }
        terminalView.feed(text: "\r\n\u{1b}[2m[reconnecting to \(target.displayName)]\u{1b}[0m\r\n")
        start()
    }

    /// Closes the log first, so its hash is written even when the app is quitting.
    func stop() {
        stopLogging()
        guard state == .running else { return }
        if let files {
            files.disconnect()
            state = .ended(exitCode: nil)
            return
        }
        if let serialPort {
            self.serialPort = nil
            serialPort.close()
            state = .ended(exitCode: nil)
            note("closed \(serialPort.path)")
            return
        }
        process?.terminate()
    }

    // MARK: Serial

    private func openSerial(_ path: String, _ settings: SerialSettings) {
        do {
            let port = try SerialPort(path: path, settings: settings)
            serialPort = port
            state = .running
            note("opened \(path) at \(settings.summary) · Session ▸ Send Break for ROMMON")
            port.startReading(
                on: .main,
                onData: { [weak self, weak port] bytes in
                    MainActor.assumeIsolated {
                        guard let self, let port, self.serialPort === port else { return }
                        self.consume(bytes[...])
                    }
                },
                onEnd: { [weak self, weak port] error in
                    MainActor.assumeIsolated {
                        guard let self, let port, self.serialPort === port else { return }
                        self.serialEnded(error)
                    }
                }
            )
            if logByDefault { startLogging() }
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            note(message, isError: true)
        }
    }

    private func serialEnded(_ error: SerialError?) {
        stopLogging()
        serialPort?.close()
        serialPort = nil
        state = .ended(exitCode: nil)
        let reason = error?.localizedDescription ?? "port closed"
        terminalView.feed(text: "\r\n\u{1b}[2m[\(reason) · ⇧⌘R to reopen]\u{1b}[0m\r\n")
    }

    var canSendBreak: Bool { serialPort != nil && state == .running }

    /// Holds the line in break for 300 ms: ROMMON, password recovery.
    func sendBreak() {
        guard let serialPort else { return }
        do {
            try serialPort.sendBreak()
            note("break sent")
            appendLogLine("[break sent \(Date().formatted(.iso8601))]")
        } catch {
            note(error.localizedDescription, isError: true)
        }
    }

    /// The file browser's connection closed or failed.
    private func filesEnded(_ message: String?) {
        stopLogging()
        if let message {
            state = .failed(message)
        } else {
            state = .ended(exitCode: nil)
        }
    }

    /// Adds one line to the log, for tabs whose record isn't terminal output
    /// (the file browser logs each transfer and its SHA-256).
    private func appendLogLine(_ line: String) {
        guard let logWriter else { return }
        do {
            try logWriter.append(Array((line + "\r\n").utf8))
        } catch {
            self.logWriter = nil
            isLogging = false
            _ = try? logWriter.close()
            note("logging stopped: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: Logging

    func toggleLogging() {
        if isLogging { stopLogging() } else { startLogging() }
    }

    func startLogging() {
        guard state == .running, logWriter == nil else { return }
        logSegmentCount += 1
        do {
            let writer = try SessionLogWriter(
                folder: LogLocation.folder,
                host: name ?? target.host,
                destination: target.displayName,
                protocolName: kind.rawValue,
                segment: logSegmentCount
            )
            logWriter = writer
            lastLogURL = writer.logURL
            isLogging = true
            LogLocation.noteLoggingUsed()
            note("logging to \(LogLocation.abbreviated(writer.logURL))")
        } catch {
            note("could not start logging: \(error.localizedDescription)", isError: true)
        }
    }

    func stopLogging() {
        guard let writer = logWriter else { return }
        logWriter = nil
        isLogging = false
        do {
            let meta = try writer.close()
            let digest = meta.sha256.map { String($0.prefix(16)) + "…" } ?? ""
            note("log closed · \(meta.byteCount ?? 0) bytes · sha256 \(digest)")
        } catch {
            note("log closed with an error: \(error.localizedDescription)", isError: true)
        }
        LogLocation.writeReadableCopyInBackground(for: writer.logURL)
    }

    /// A dim status line in the terminal. It goes to the screen only, never
    /// into the log, because it doesn't pass through `received`.
    private func note(_ message: String, isError: Bool = false) {
        if let files {
            files.status = message
            return
        }
        let color = isError ? "\u{1b}[31m" : "\u{1b}[2m"
        terminalView.feed(text: "\r\n\(color)[\(message)]\u{1b}[0m\r\n")
    }

    // MARK: Process callbacks, delivered on the main queue by ProcessBridge

    fileprivate func received(_ bytes: ArraySlice<UInt8>, from source: ProcessBridge) {
        guard source === bridge else { return }
        consume(bytes)
    }

    /// Output from ssh or a serial port: to the log while logging, then to the screen.
    private func consume(_ bytes: ArraySlice<UInt8>) {
        if let logWriter {
            do {
                try logWriter.append(bytes)
            } catch {
                self.logWriter = nil
                isLogging = false
                _ = try? logWriter.close()
                note("logging stopped: \(error.localizedDescription)", isError: true)
            }
        }
        terminalView.feed(byteArray: bytes)
    }

    fileprivate func terminated(exitCode: Int32?, from source: ProcessBridge) {
        guard source === bridge else { return }
        stopLogging()
        state = .ended(exitCode: exitCode)
        let detail = exitCode.map { ", exit \($0)" } ?? ""
        terminalView.feed(text: "\r\n\u{1b}[2m[session ended\(detail) · ⇧⌘R to reconnect]\u{1b}[0m\r\n")
    }

    fileprivate func failedToStart(_ message: String, from source: ProcessBridge) {
        guard source === bridge else { return }
        stopLogging()
        state = .failed(message)
        terminalView.feed(text: "\r\n\u{1b}[31m[could not start \(kind.rawValue): \(message)]\u{1b}[0m\r\n")
    }

    private func currentWindowSize() -> winsize {
        let dimensions = terminalView.terminalDimensions
        return winsize(
            ws_row: UInt16(clamping: dimensions.rows),
            ws_col: UInt16(clamping: dimensions.cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
    }
}

// MARK: - TerminalViewDelegate

extension TerminalSession: TerminalViewDelegate {
    /// Window resizes and font changes both land here; the PTY gets the new
    /// size so remote full-screen apps redraw at the right width.
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        var size = winsize(
            ws_row: UInt16(clamping: newRows),
            ws_col: UInt16(clamping: newCols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        bridge?.updateWindowSize(size)
        _ = process?.updateWindowSize(&size)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        remoteTitle = title
    }

    /// Keystrokes go straight to ssh and are never stored.
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard state == .running else { return }
        if let serialPort {
            serialPort.write(Array(data))
        } else {
            process?.send(data: data)
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

// MARK: - ProcessBridge

/// `LocalProcessDelegate` isn't main-actor isolated, but 7 Term creates every
/// `LocalProcess` with `dispatchQueue: .main`. This small class receives those
/// calls and hands them to the session on the main actor.
private final class ProcessBridge: LocalProcessDelegate, @unchecked Sendable {
    // Read only on the main actor; the lock guards the window size, which
    // LocalProcess may ask for from its own thread.
    @MainActor private weak var owner: TerminalSession?
    private let lock = NSLock()
    private var windowSize = winsize()

    @MainActor init(owner: TerminalSession) {
        self.owner = owner
    }

    func updateWindowSize(_ size: winsize) {
        lock.withLock { windowSize = size }
    }

    func getWindowSize() -> winsize {
        lock.withLock { windowSize }
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        onMain { [self] in owner?.received(slice, from: self) }
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        onMain { [self] in owner?.terminated(exitCode: exitCode, from: self) }
    }

    func processFailedToStart(_ source: LocalProcess, error: LocalProcessError) {
        let message = String(describing: error)
        onMain { [self] in owner?.failedToStart(message, from: self) }
    }

    private func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in work() }
        }
    }
}
