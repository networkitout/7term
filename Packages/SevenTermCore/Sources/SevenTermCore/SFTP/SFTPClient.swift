import Foundation

/// An SFTP client talking to a server over a pair of pipes.
///
/// In the app the pipes are /usr/bin/ssh's stdin and stdout (`ssh -s host
/// sftp`); in tests they're a local `sftp-server`. Requests can be in flight
/// together: each carries an id, and a reader thread hands every reply to the
/// request with that id.
public final class SFTPClient: @unchecked Sendable {
    /// Largest reply accepted. OpenSSH's own limit is 256 KiB; anything far
    /// bigger means the stream isn't SFTP (or the server is hostile).
    static let maxPacket = 1 << 20

    private let lock = NSLock()
    private var pending: [UInt32: CheckedContinuation<Reply, Error>] = [:]
    private var versionWaiter: CheckedContinuation<(UInt32, [String: Data]), Error>?
    private var nextID: UInt32 = 1
    private var closedError: SFTPError?

    private let input: FileHandle
    private let output: FileHandle
    private let writeLock = NSLock()
    private let process: Process?
    private let stderrTail: StderrTail?

    /// Extensions the server announced (posix-rename@openssh.com and so on).
    public private(set) var extensions: [String: Data] = [:]

    enum Reply {
        case status(SFTPStatusCode?, String)
        case handle(Data)
        case data(Data)
        case name([SFTPEntry])
        case attrs(SFTPAttributes)
        case extended(Data)
    }

    /// `input` is read for replies; requests are written to `output`.
    public init(reading input: FileHandle, writing output: FileHandle) {
        self.input = input
        self.output = output
        process = nil
        stderrTail = nil
    }

    private init(process: Process, input: FileHandle, output: FileHandle, stderrTail: StderrTail) {
        self.input = input
        self.output = output
        self.process = process
        self.stderrTail = stderrTail
    }

    /// Starts `executable` (ssh, or sftp-server in tests) with pipes for
    /// stdin, stdout and stderr, then performs the SFTP handshake.
    public static func launch(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> SFTPClient {
        // A write to a pipe whose reader is gone must fail, not kill the app.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let tail = StderrTail(handle: stderr.fileHandleForReading)
        try process.run()

        let client = SFTPClient(
            process: process,
            input: stdout.fileHandleForReading,
            output: stdin.fileHandleForWriting,
            stderrTail: tail
        )
        tail.start()
        try await client.handshake()
        return client
    }

    /// Sends INIT and waits for VERSION. Starts the reader thread.
    public func handshake() async throws {
        let thread = Thread { [self] in readLoop() }
        thread.name = "7 Term SFTP reader"
        thread.start()

        var body = SFTPWriter()
        body.uint32(3)
        let (_, extensions) = try await withCheckedThrowingContinuation { continuation in
            let closed: SFTPError? = lock.withLock {
                if let closedError { return closedError }
                versionWaiter = continuation
                return nil
            }
            if let closed {
                continuation.resume(throwing: closed)
                return
            }
            // If ssh has already exited, this write fails; the reader then
            // sees the end of the stream and reports ssh's own error message.
            try? send(SFTPWriter.packet(.initialize, body: body.data))
        }
        self.extensions = extensions
    }

    /// Ends the session: closes ssh's stdin, which makes it disconnect.
    public func close() {
        try? output.close()
        if let process, process.isRunning {
            process.terminate()
        }
    }

    public var isClosed: Bool { lock.withLock { closedError != nil } }

    // MARK: Requests

    func request(_ type: SFTPMessage, _ build: (inout SFTPWriter) -> Void = { _ in }) async throws -> Reply {
        try Task.checkCancellation()
        var body = SFTPWriter()
        let id: UInt32 = lock.withLock {
            defer { nextID &+= 1 }
            return nextID
        }
        body.uint32(id)
        build(&body)
        let packet = SFTPWriter.packet(type, body: body.data)
        return try await withCheckedThrowingContinuation { continuation in
            let closed: SFTPError? = lock.withLock {
                if let closedError { return closedError }
                pending[id] = continuation
                return nil
            }
            if let closed {
                continuation.resume(throwing: closed)
                return
            }
            do {
                try send(packet)
            } catch {
                let waiting = lock.withLock { pending.removeValue(forKey: id) }
                waiting?.resume(throwing: SFTPError.connectionClosed(stderrSummary))
            }
        }
    }

    private func send(_ packet: Data) throws {
        try writeLock.withLock {
            try output.write(contentsOf: packet)
        }
    }

    /// Expects an OK status.
    func expectOK(_ reply: Reply) throws {
        guard case .status(let code, let message) = reply else { throw SFTPError.unexpectedReply }
        guard code == .ok else { throw SFTPError.status(code, message) }
    }

    func expectHandle(_ reply: Reply) throws -> Data {
        switch reply {
        case .handle(let handle): return handle
        case .status(let code, let message): throw SFTPError.status(code, message)
        default: throw SFTPError.unexpectedReply
        }
    }

    // MARK: Reading replies

    private func readLoop() {
        var buffer = Data()
        var sawFirstPacket = false
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while buffer.count >= 4 {
                let start = buffer.startIndex
                let length = buffer[start..<start + 4].reduce(0) { $0 << 8 | Int($1) }
                guard length >= 1, length <= Self.maxPacket else {
                    let preview = sawFirstPacket
                        ? nil
                        : String(decoding: buffer.prefix(80), as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    finish(preview.map(SFTPError.notSFTP) ?? .badReply)
                    return
                }
                guard buffer.count >= 4 + length else { break }
                let packet = buffer[(start + 4)..<(start + 4 + length)]
                buffer = Data(buffer[(start + 4 + length)...])
                sawFirstPacket = true
                dispatch(Data(packet))
            }
        }
        // Give ssh a moment to finish writing its error before reporting it.
        process?.waitUntilExit()
        stderrTail?.waitUntilDone()
        finish(.connectionClosed(stderrSummary))
    }

    private func dispatch(_ packet: Data) {
        var reader = SFTPReader(packet)
        do {
            guard let type = SFTPMessage(rawValue: try reader.byte()) else { return }
            if type == .version {
                let version = try reader.uint32()
                var extensions: [String: Data] = [:]
                while !reader.isAtEnd {
                    let name = try reader.string()
                    extensions[name] = try reader.bytes()
                }
                let waiter = lock.withLock {
                    defer { versionWaiter = nil }
                    return versionWaiter
                }
                waiter?.resume(returning: (version, extensions))
                return
            }
            let id = try reader.uint32()
            let reply: Reply
            switch type {
            case .status:
                let code = try reader.uint32()
                let message = reader.isAtEnd ? "" : try reader.string()
                reply = .status(SFTPStatusCode(rawValue: code), message)
            case .handle: reply = .handle(try reader.bytes())
            case .data: reply = .data(try reader.bytes())
            case .name:
                let count = try reader.uint32()
                var entries: [SFTPEntry] = []
                entries.reserveCapacity(Int(min(count, 4096)))
                for _ in 0..<count {
                    let name = try reader.string()
                    _ = try reader.string() // ls -l style long name; not used
                    entries.append(SFTPEntry(name: name, attributes: try reader.attributes()))
                }
                reply = .name(entries)
            case .attrs: reply = .attrs(try reader.attributes())
            case .extendedReply:
                var rest = Data()
                while !reader.isAtEnd { rest.append(try reader.byte()) }
                reply = .extended(rest)
            default:
                return
            }
            let waiter = lock.withLock { pending.removeValue(forKey: id) }
            waiter?.resume(returning: reply)
        } catch {
            finish(.badReply)
        }
    }

    /// Fails everything still waiting. Later requests fail straight away.
    private func finish(_ error: SFTPError) {
        let (waiters, version): ([CheckedContinuation<Reply, Error>], CheckedContinuation<(UInt32, [String: Data]), Error>?) =
            lock.withLock {
                if closedError == nil { closedError = error }
                let waiters = Array(pending.values)
                pending.removeAll()
                defer { versionWaiter = nil }
                return (waiters, versionWaiter)
            }
        let reported = lock.withLock { closedError ?? error }
        waiters.forEach { $0.resume(throwing: reported) }
        version?.resume(throwing: reported)
        if case .notSFTP = error { close() }
        if case .badReply = error { close() }
    }

    /// The last thing ssh wrote to stderr, such as "Permission denied (publickey)."
    public var stderrSummary: String {
        stderrTail?.summary ?? ""
    }
}

/// Keeps the last couple of KB that ssh writes to stderr.
final class StderrTail: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var text = ""
    private let done = DispatchSemaphore(value: 0)
    private var finished = false

    init(handle: FileHandle) {
        self.handle = handle
    }

    func start() {
        let thread = Thread { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lock.withLock {
                    text += String(decoding: chunk, as: UTF8.self)
                    if text.count > 2048 { text = String(text.suffix(2048)) }
                }
            }
            lock.withLock { finished = true }
            done.signal()
        }
        thread.name = "7 Term ssh stderr"
        thread.start()
    }

    func waitUntilDone() {
        if lock.withLock({ finished }) { return }
        _ = done.wait(timeout: .now() + 2)
    }

    /// The last meaningful lines, without ssh's informational warnings.
    var summary: String {
        let lines = lock.withLock { text }
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Warning: Permanently added") }
        return lines.suffix(3).joined(separator: "\n")
    }
}
