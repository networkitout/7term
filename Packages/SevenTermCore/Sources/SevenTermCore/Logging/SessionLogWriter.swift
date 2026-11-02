import CryptoKit
import Darwin
import Foundation

/// Writes one log segment: the raw output bytes, exactly as the terminal
/// received them, hashed with SHA-256 as they're written so closing needs no
/// second read. Only output is logged; keystrokes never pass through here.
///
/// Not thread-safe: 7 Term uses each writer from the main actor only.
public final class SessionLogWriter {
    public let logURL: URL
    public private(set) var byteCount = 0
    public private(set) var isClosed = false

    private let handle: FileHandle
    private var hasher = SHA256()
    private var meta: LogSegmentMeta
    private let metaURL: URL

    /// Creates `<folder>/<host>/<name>.log` and its meta file. If a file with
    /// that name exists (two tabs to one host in the same second), a numeric
    /// suffix is added; existing files are never opened or overwritten.
    public init(
        folder: URL,
        host: String,
        destination: String,
        protocolName: String = "ssh",
        segment: Int,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) throws {
        let hostFolder = folder.appending(path: LogNaming.safeComponent(host), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hostFolder, withIntermediateDirectories: true)

        let base = LogNaming.baseName(host: host, protocolName: protocolName, segment: segment, startedAt: now)
        let created = try Self.createExclusively(in: hostFolder, base: base)
        logURL = created.url
        handle = created.handle
        metaURL = hostFolder.appending(path: created.name + LogNaming.metaSuffix)
        meta = LogSegmentMeta(
            host: host,
            destination: destination,
            protocolName: protocolName,
            segment: segment,
            logFile: logURL.lastPathComponent,
            startedAt: now,
            utcOffset: LogNaming.utcOffset(for: now, in: timeZone)
        )
        try meta.write(to: metaURL)
    }

    deinit {
        if !isClosed { try? handle.close() }
    }

    public func append(_ bytes: some Collection<UInt8>) throws {
        precondition(!isClosed, "append after close")
        guard !bytes.isEmpty else { return }
        let data = Data(bytes)
        try handle.write(contentsOf: data)
        hasher.update(data: data)
        byteCount += data.count
    }

    /// Finishes the hash, closes the file, and writes the `.log.sha256`
    /// sidecar (in `shasum -a 256 -c` format) and the completed meta.
    @discardableResult
    public func close(now: Date = Date()) throws -> LogSegmentMeta {
        guard !isClosed else { return meta }
        isClosed = true
        try handle.synchronize()
        try handle.close()

        let digest = Self.hex(hasher.finalize())
        meta.endedAt = now
        meta.byteCount = byteCount
        meta.sha256 = digest
        meta.closedCleanly = true
        try LogFiles.writeSidecar(digest: digest, for: logURL)
        try meta.write(to: metaURL)
        return meta
    }

    /// Creates `<base>.log`, or `<base>-2.log` and so on if taken. O_EXCL
    /// makes creation fail rather than reuse a file that already exists.
    private static func createExclusively(
        in folder: URL,
        base: String
    ) throws -> (url: URL, handle: FileHandle, name: String) {
        for attempt in 1...99 {
            let name = attempt == 1 ? base : "\(base)-\(attempt)"
            let url = folder.appending(path: name + "." + LogNaming.logExtension)
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
            if descriptor >= 0 {
                return (url, FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), name)
            }
            guard errno == EEXIST else { break }
        }
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: folder.path])
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
