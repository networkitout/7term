import AppKit
import Observation
import SwiftTerm
import ThreeTermCore

/// One tab: an ssh process in a pseudo-terminal, and the view that shows it.
///
/// 3 Term runs its own `LocalProcess` and feeds a plain `TerminalView`, instead
/// of using SwiftTerm's `LocalProcessTerminalView`. That keeps every output
/// byte passing through `received(_:from:)`, which is where the log writer
/// will tee output in milestone 3.
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
    private(set) var state: State = .idle
    private(set) var remoteTitle: String?

    @ObservationIgnored let terminalView: TerminalView
    @ObservationIgnored private var process: LocalProcess?
    @ObservationIgnored private var bridge: ProcessBridge?

    var title: String {
        guard let remoteTitle, !remoteTitle.isEmpty else { return target.displayName }
        return remoteTitle
    }

    init(target: SSHTarget) {
        self.target = target
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
    }

    func restart() {
        guard state != .running else { return }
        terminalView.feed(text: "\r\n\u{1b}[2m[reconnecting to \(target.displayName)]\u{1b}[0m\r\n")
        start()
    }

    func stop() {
        guard state == .running else { return }
        process?.terminate()
    }

    // MARK: Process callbacks, delivered on the main queue by ProcessBridge

    fileprivate func received(_ bytes: ArraySlice<UInt8>, from source: ProcessBridge) {
        guard source === bridge else { return }
        terminalView.feed(byteArray: bytes)
    }

    fileprivate func terminated(exitCode: Int32?, from source: ProcessBridge) {
        guard source === bridge else { return }
        state = .ended(exitCode: exitCode)
        let detail = exitCode.map { ", exit \($0)" } ?? ""
        terminalView.feed(text: "\r\n\u{1b}[2m[session ended\(detail) · ⇧⌘R to reconnect]\u{1b}[0m\r\n")
    }

    fileprivate func failedToStart(_ message: String, from source: ProcessBridge) {
        guard source === bridge else { return }
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
