import Foundation

/// File and folder operations.
extension SFTPClient {
    /// Size of each read or write request. OpenSSH accepts up to 255 KiB, but
    /// 32 KiB is what every server supports.
    static let chunkSize = 32 * 1024
    /// Requests kept in flight during a transfer, so a high-latency link isn't
    /// idle waiting for each reply.
    static let window = 32

    /// The absolute form of `path` ("." gives the home folder).
    public func realPath(_ path: String) async throws -> String {
        let reply = try await request(.realpath) { $0.string(path) }
        switch reply {
        case .name(let entries) where entries.count == 1: return entries[0].name
        case .status(let code, let message): throw SFTPError.status(code, message)
        default: throw SFTPError.unexpectedReply
        }
    }

    /// Follows symlinks.
    public func stat(_ path: String) async throws -> SFTPAttributes {
        try attributes(from: await request(.stat) { $0.string(path) })
    }

    /// Describes a symlink itself rather than its target.
    public func lstat(_ path: String) async throws -> SFTPAttributes {
        try attributes(from: await request(.lstat) { $0.string(path) })
    }

    /// nil when nothing is at `path`.
    public func exists(_ path: String) async throws -> SFTPAttributes? {
        do {
            return try await lstat(path)
        } catch let error as SFTPError where error.code == .noSuchFile {
            return nil
        }
    }

    private func attributes(from reply: Reply) throws -> SFTPAttributes {
        switch reply {
        case .attrs(let attributes): return attributes
        case .status(let code, let message): throw SFTPError.status(code, message)
        default: throw SFTPError.unexpectedReply
        }
    }

    /// The folder's entries, without "." and "..".
    public func list(_ path: String) async throws -> [SFTPEntry] {
        let handle = try expectHandle(await request(.opendir) { $0.string(path) })
        var entries: [SFTPEntry] = []
        do {
            readLoop: while true {
                let reply = try await request(.readdir) { $0.bytes(handle) }
                switch reply {
                case .name(let batch):
                    entries += batch.filter { $0.name != "." && $0.name != ".." }
                case .status(.eof, _):
                    break readLoop
                case .status(let code, let message):
                    throw SFTPError.status(code, message)
                default:
                    throw SFTPError.unexpectedReply
                }
            }
        } catch {
            try? await closeHandle(handle)
            throw error
        }
        try? await closeHandle(handle)
        return entries
    }

    public func makeDirectory(_ path: String, permissions: UInt32 = 0o755) async throws {
        try expectOK(await request(.mkdir) {
            $0.string(path)
            $0.attributes(SFTPAttributes(permissions: permissions))
        })
    }

    public func removeDirectory(_ path: String) async throws {
        try expectOK(await request(.rmdir) { $0.string(path) })
    }

    public func removeFile(_ path: String) async throws {
        try expectOK(await request(.remove) { $0.string(path) })
    }

    /// Renames, replacing an existing file at `to` when the server supports
    /// it (OpenSSH's posix-rename). Plain SFTP rename refuses to replace.
    public func rename(_ from: String, to: String, replacing: Bool = false) async throws {
        if replacing, extensions["posix-rename@openssh.com"] != nil {
            try expectOK(await request(.extended) {
                $0.string("posix-rename@openssh.com")
                $0.string(from)
                $0.string(to)
            })
            return
        }
        if replacing, try await exists(to) != nil {
            try await removeFile(to)
        }
        try expectOK(await request(.rename) {
            $0.string(from)
            $0.string(to)
        })
    }

    public func setAttributes(_ path: String, _ attributes: SFTPAttributes) async throws {
        try expectOK(await request(.setstat) {
            $0.string(path)
            $0.attributes(attributes)
        })
    }

    /// Removes a folder and everything in it. Symlinks are removed, never followed.
    public func removeTree(_ path: String) async throws {
        for entry in try await list(path) {
            let child = SFTPPath.join(path, entry.name)
            if entry.attributes.isDirectory {
                try await removeTree(child)
            } else {
                try await removeFile(child)
            }
        }
        try await removeDirectory(path)
    }

    func open(_ path: String, flags: SFTPOpenFlags, attributes: SFTPAttributes = SFTPAttributes()) async throws -> Data {
        try expectHandle(await request(.open) {
            $0.string(path)
            $0.uint32(flags.rawValue)
            $0.attributes(attributes)
        })
    }

    func closeHandle(_ handle: Data) async throws {
        try expectOK(await request(.close) { $0.bytes(handle) })
    }

    // MARK: Transfers

    /// Copies a remote file to `destination`. An existing file there is only
    /// replaced when `replacing` is true, and only once the copy is complete.
    ///
    /// Data is written to a hidden partial file first and renamed when done,
    /// so a cancelled or failed transfer never leaves a truncated file under
    /// the real name. `onData` sees every byte in order (for hashing);
    /// `progress` gets the running total. Returns the number of bytes copied.
    @discardableResult
    public func download(
        _ remotePath: String,
        to destination: URL,
        replacing: Bool = false,
        onData: @Sendable (Data) -> Void = { _ in },
        progress: @Sendable (UInt64) -> Void = { _ in }
    ) async throws -> UInt64 {
        let handle = try await open(remotePath, flags: .read)
        let remoteAttributes = try? attributes(from: await request(.fstat) { $0.bytes(handle) })

        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).7term-part")
        try? FileManager.default.removeItem(at: partial)
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            try? await closeHandle(handle)
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: destination.path])
        }
        let file = try FileHandle(forWritingTo: partial)

        var total: UInt64 = 0
        do {
            total = try await pipelinedRead(handle: handle) { chunk in
                try file.write(contentsOf: chunk)
                onData(chunk)
            } progress: { progress($0) }
            try file.close()
            try? await closeHandle(handle)

            if let permissions = remoteAttributes?.permissions {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: NSNumber(value: permissions & 0o777)], ofItemAtPath: partial.path)
            }
            if let modified = remoteAttributes?.modificationDate {
                try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: partial.path)
            }
            if replacing {
                // rename(2) swaps the finished file in atomically.
                guard Foundation.rename(partial.path, destination.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            } else {
                try FileManager.default.moveItem(at: partial, to: destination)
            }
            return total
        } catch {
            try? file.close()
            try? FileManager.default.removeItem(at: partial)
            try? await closeHandle(handle)
            throw (error is CancellationError) ? SFTPError.cancelled : error
        }
    }

    /// Reads a whole open file with up to `window` requests in flight,
    /// delivering data strictly in order.
    private func pipelinedRead(
        handle: Data,
        deliver: (Data) throws -> Void,
        progress: (UInt64) -> Void
    ) async throws -> UInt64 {
        // Ranges in file order; a short reply puts its remainder at the front.
        var queue: [(offset: UInt64, length: UInt32, task: Task<Reply, Error>)] = []
        var nextOffset: UInt64 = 0
        var reachedEnd = false
        var total: UInt64 = 0

        func enqueue(_ offset: UInt64, _ length: UInt32, atFront: Bool = false) {
            let task = Task { [self] in
                try await request(.read) {
                    $0.bytes(handle)
                    $0.uint64(offset)
                    $0.uint32(length)
                }
            }
            if atFront { queue.insert((offset, length, task), at: 0) } else { queue.append((offset, length, task)) }
        }

        defer { queue.forEach { $0.task.cancel() } }

        while true {
            while !reachedEnd, queue.count < Self.window {
                enqueue(nextOffset, UInt32(Self.chunkSize))
                nextOffset += UInt64(Self.chunkSize)
            }
            guard !queue.isEmpty else { break }
            try Task.checkCancellation()
            let head = queue.removeFirst()
            switch try await head.task.value {
            case .data(let chunk):
                guard !chunk.isEmpty, chunk.count <= Int(head.length) else { throw SFTPError.badReply }
                try deliver(chunk)
                total += UInt64(chunk.count)
                progress(total)
                if chunk.count < Int(head.length) {
                    enqueue(head.offset + UInt64(chunk.count), head.length - UInt32(chunk.count), atFront: true)
                }
            case .status(.eof, _):
                // Everything after this offset is past the end as well.
                reachedEnd = true
                queue.forEach { $0.task.cancel() }
                queue.removeAll()
            case .status(let code, let message):
                throw SFTPError.status(code, message)
            default:
                throw SFTPError.unexpectedReply
            }
        }
        return total
    }

    /// Copies a local file to `remotePath`.
    ///
    /// Written to a hidden partial file beside it and renamed when complete;
    /// `replacing` allows that rename to replace an existing file.
    @discardableResult
    public func upload(
        _ source: URL,
        to remotePath: String,
        replacing: Bool = false,
        onData: @Sendable (Data) -> Void = { _ in },
        progress: @Sendable (UInt64) -> Void = { _ in }
    ) async throws -> UInt64 {
        let localAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let permissions = (localAttributes[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }

        let partial = SFTPPath.join(SFTPPath.parent(remotePath), ".\(SFTPPath.name(remotePath)).7term-part")
        let handle = try await open(
            partial, flags: [.write, .create, .truncate],
            attributes: SFTPAttributes(permissions: permissions & 0o777)
        )

        var inFlight: [Task<Reply, Error>] = []
        var offset: UInt64 = 0
        var acknowledged: UInt64 = 0
        var sizes: [Int] = []
        do {
            defer { inFlight.forEach { $0.cancel() } }
            while true {
                try Task.checkCancellation()
                guard let chunk = try reader.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
                onData(chunk)
                let at = offset
                inFlight.append(Task { [self] in
                    try await request(.write) {
                        $0.bytes(handle)
                        $0.uint64(at)
                        $0.bytes(chunk)
                    }
                })
                sizes.append(chunk.count)
                offset += UInt64(chunk.count)
                if inFlight.count >= Self.window {
                    try expectOK(await inFlight.removeFirst().value)
                    acknowledged += UInt64(sizes.removeFirst())
                    progress(acknowledged)
                }
            }
            while !inFlight.isEmpty {
                try expectOK(await inFlight.removeFirst().value)
                acknowledged += UInt64(sizes.removeFirst())
                progress(acknowledged)
            }
            try await closeHandle(handle)
        } catch {
            try? await closeHandle(handle)
            try? await removeFile(partial)
            throw (error is CancellationError) ? SFTPError.cancelled : error
        }

        do {
            if let modified = localAttributes[.modificationDate] as? Date {
                let seconds = UInt32(clamping: Int(modified.timeIntervalSince1970))
                try? await setAttributes(partial, SFTPAttributes(accessTime: seconds, modificationTime: seconds))
            }
            try await rename(partial, to: remotePath, replacing: replacing)
        } catch {
            try? await removeFile(partial)
            throw error
        }
        return offset
    }

    /// Every file and folder under `path`, depth first, folders before their
    /// contents. Symlinks are listed but never followed, so a link loop can't
    /// recurse forever. Names that can't be used as a local file name throw.
    public func walk(_ path: String) async throws -> [SFTPTreeItem] {
        var items: [SFTPTreeItem] = []
        func visit(_ folder: String, relative: String) async throws {
            for entry in try await list(folder).sorted(by: { $0.name < $1.name }) {
                guard SFTPPath.isSafeName(entry.name) else { throw SFTPError.unsafeName(entry.name) }
                let childRelative = relative.isEmpty ? entry.name : relative + "/" + entry.name
                let item = SFTPTreeItem(
                    remotePath: SFTPPath.join(folder, entry.name),
                    relativePath: childRelative,
                    attributes: entry.attributes
                )
                items.append(item)
                if entry.attributes.isDirectory {
                    try await visit(item.remotePath, relative: childRelative)
                }
            }
        }
        try await visit(path, relative: "")
        return items
    }
}

public struct SFTPTreeItem: Equatable, Sendable {
    public var remotePath: String
    /// Path below the folder that was walked, with "/" separators.
    public var relativePath: String
    public var attributes: SFTPAttributes
}

/// Remote paths are always "/"-separated, whatever the local system uses.
public enum SFTPPath {
    public static func join(_ folder: String, _ name: String) -> String {
        if folder.isEmpty { return name }
        return folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }

    public static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        if slash == path.startIndex { return "/" }
        return String(path[..<slash])
    }

    public static func name(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// True for a single path component that's safe to create locally: not
    /// empty, ".", "..", and no "/", NUL or other control characters. A
    /// server choosing names like "../../.zshrc" can't write outside the
    /// folder you dropped into.
    public static func isSafeName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return !name.unicodeScalars.contains { $0 == "/" || $0.value < 0x20 || $0.value == 0x7F }
    }
}
