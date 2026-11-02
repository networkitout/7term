import AppKit
import Observation
import SwiftTerm
import ThreeTermCore

/// One tab: an ssh process in a pseudo-terminal, and the view that shows it.
///
/// 3 Term runs its own `LocalProcess` and feeds a plain `TerminalView`, instead
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

    let id = UUID()
    let target: SSHTarget
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
    @ObservationIgnored private var process: LocalProcess?
    @ObservationIgnored private var bridge: ProcessBridge?
    @ObservationIgnored private var logWriter: SessionLogWriter?
    @ObservationIgnored private var logSegmentCount = 0

    /// A saved host keeps its name; a quick connection shows what the remote
    /// shell sets as the title, falling back to user@host.
    var title: String {
        if let name, !name.isEmpty { return name }
        guard let remoteTitle, !remoteTitle.isEmpty else { return target.displayName }
        return remoteTitle
    }

    init(target: SSHTarget, name: String? = nil, logByDefault: Bool = false) {
        self.target = target
        self.name = name
        self.logByDefault = logByDefault
        terminalView = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        TerminalTheme.threeTerm.apply(to: terminalView)
        terminalView.terminalDelegate = self
    }

    func start() {
        guard state != .running else { return }

        // A fresh bridge per launch, so a late callback from an old process
        // can never change the state of a new one.
        let bridge = ProcessBridge(owner: self)
        bridge.updateWindowSize(currentWindowSize())
        let process = LocalProcess(delegate: bridge, dispatchQueue: .main)
        self.bridge = bridge
        self.process = process
        remoteTitle = nil
        state = .running

        process.startProcess(
            executable: "/usr/bin/ssh",
            args: target.sshArguments,
            environment: ChildEnvironment.make(from: ProcessInfo.processInfo.environment),
            execName: "ssh"
        )
        if logByDefault { startLogging() }
    }

    func restart() {
        guard state != .running else { return }
        terminalView.feed(text: "\r\n\u{1b}[2m[reconnecting to \(target.displayName)]\u{1b}[0m\r\n")
        start()
    }

    /// Closes the log first, so its hash is written even when the app is quitting.
    func stop() {
        stopLogging()
        guard state == .running else { return }
        process?.terminate()
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
        let color = isError ? "\u{1b}[31m" : "\u{1b}[2m"
        terminalView.feed(text: "\r\n\(color)[\(message)]\u{1b}[0m\r\n")
    }

    // MARK: Process callbacks, delivered on the main queue by ProcessBridge

    fileprivate func received(_ bytes: ArraySlice<UInt8>, from source: ProcessBridge) {
        guard source === bridge else { return }
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
        terminalView.feed(text: "\r\n\u{1b}[31m[could not start ssh: \(message)]\u{1b}[0m\r\n")
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
        process?.send(data: data)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

// MARK: - ProcessBridge

/// `LocalProcessDelegate` isn't main-actor isolated, but 3 Term creates every
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
