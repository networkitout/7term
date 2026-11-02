import Foundation

/// SFTP version 3 (draft-ietf-secsh-filexfer-02), the version OpenSSH speaks.
///
/// 7 Term never implements SSH itself: OpenSSH opens the connection and the
/// `sftp` subsystem (`ssh -s host sftp`), handling encryption, sign-in, host
/// keys, ProxyJump and ssh_config. What flows over ssh's stdin and stdout is
/// this much simpler protocol: length-prefixed request and reply messages.
enum SFTPMessage: UInt8 {
    case initialize = 1, version = 2
    case open = 3, close = 4, read = 5, write = 6
    case lstat = 7, fstat = 8, setstat = 9, fsetstat = 10
    case opendir = 11, readdir = 12, remove = 13, mkdir = 14, rmdir = 15
    case realpath = 16, stat = 17, rename = 18, readlink = 19, symlink = 20
    case status = 101, handle = 102, data = 103, name = 104, attrs = 105
    case extended = 200, extendedReply = 201
}

public struct SFTPOpenFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let read = SFTPOpenFlags(rawValue: 0x01)
    public static let write = SFTPOpenFlags(rawValue: 0x02)
    public static let append = SFTPOpenFlags(rawValue: 0x04)
    public static let create = SFTPOpenFlags(rawValue: 0x08)
    public static let truncate = SFTPOpenFlags(rawValue: 0x10)
    public static let exclusive = SFTPOpenFlags(rawValue: 0x20)
}

public enum SFTPStatusCode: UInt32, Sendable {
    case ok = 0, eof, noSuchFile, permissionDenied, failure, badMessage
    case noConnection, connectionLost, unsupported
}

/// File attributes. Every field is optional on the wire.
public struct SFTPAttributes: Equatable, Sendable {
    public var size: UInt64?
    public var uid: UInt32?
    public var gid: UInt32?
    public var permissions: UInt32?
    public var accessTime: UInt32?
    public var modificationTime: UInt32?

    public init(
        size: UInt64? = nil, uid: UInt32? = nil, gid: UInt32? = nil,
        permissions: UInt32? = nil, accessTime: UInt32? = nil, modificationTime: UInt32? = nil
    ) {
        self.size = size
        self.uid = uid
        self.gid = gid
        self.permissions = permissions
        self.accessTime = accessTime
        self.modificationTime = modificationTime
    }

    static let fileTypeMask: UInt32 = 0o170000

    public var isDirectory: Bool { permissions.map { $0 & Self.fileTypeMask == 0o040000 } ?? false }
    public var isSymlink: Bool { permissions.map { $0 & Self.fileTypeMask == 0o120000 } ?? false }
    public var isRegularFile: Bool { permissions.map { $0 & Self.fileTypeMask == 0o100000 } ?? false }

    public var modificationDate: Date? {
        modificationTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// `rwxr-xr-x` style, without the type character.
    public var modeString: String {
        guard let permissions else { return "" }
        let symbols: [(UInt32, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return String(symbols.map { permissions & $0.0 != 0 ? $0.1 : "-" })
    }
}

/// Builds a message body: big-endian integers and length-prefixed strings.
struct SFTPWriter {
    private(set) var data = Data()

    mutating func byte(_ value: UInt8) { data.append(value) }

    mutating func uint32(_ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func uint64(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func bytes(_ value: Data) {
        uint32(UInt32(value.count))
        data.append(value)
    }

    mutating func string(_ value: String) { bytes(Data(value.utf8)) }

    mutating func attributes(_ attributes: SFTPAttributes) {
        var flags: UInt32 = 0
        if attributes.size != nil { flags |= 0x1 }
        if attributes.uid != nil, attributes.gid != nil { flags |= 0x2 }
        if attributes.permissions != nil { flags |= 0x4 }
        if attributes.accessTime != nil, attributes.modificationTime != nil { flags |= 0x8 }
        uint32(flags)
        if let size = attributes.size { uint64(size) }
        if flags & 0x2 != 0 { uint32(attributes.uid!); uint32(attributes.gid!) }
        if let permissions = attributes.permissions { uint32(permissions) }
        if flags & 0x8 != 0 { uint32(attributes.accessTime!); uint32(attributes.modificationTime!) }
    }

    /// A whole packet: 4-byte length, type, then this body.
    static func packet(_ type: SFTPMessage, body: Data) -> Data {
        var packet = SFTPWriter()
        packet.uint32(UInt32(body.count + 1))
        packet.byte(type.rawValue)
        packet.data.append(body)
        return packet.data
    }
}

/// Reads a message body. Every read is bounds-checked: a short or malformed
/// reply throws instead of crashing.
struct SFTPReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }

    private mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, data.endIndex - offset >= count else { throw SFTPError.badReply }
        let slice = data[offset..<offset + count]
        offset += count
        return slice
    }

    mutating func byte() throws -> UInt8 { try take(1).first! }

    mutating func uint32() throws -> UInt32 {
        try take(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func uint64() throws -> UInt64 {
        try take(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func bytes() throws -> Data {
        let count = try uint32()
        guard count <= UInt32(Int32.max) else { throw SFTPError.badReply }
        return Data(try take(Int(count)))
    }

    mutating func string() throws -> String {
        let raw = try bytes()
        return String(decoding: raw, as: UTF8.self)
    }

    mutating func attributes() throws -> SFTPAttributes {
        let flags = try uint32()
        var attributes = SFTPAttributes()
        if flags & 0x1 != 0 { attributes.size = try uint64() }
        if flags & 0x2 != 0 { attributes.uid = try uint32(); attributes.gid = try uint32() }
        if flags & 0x4 != 0 { attributes.permissions = try uint32() }
        if flags & 0x8 != 0 { attributes.accessTime = try uint32(); attributes.modificationTime = try uint32() }
        if flags & 0x8000_0000 != 0 {
            let count = try uint32()
            for _ in 0..<count {
                _ = try bytes()
                _ = try bytes()
            }
        }
        return attributes
    }
}

/// One entry in a remote folder listing.
public struct SFTPEntry: Equatable, Sendable {
    public var name: String
    public var attributes: SFTPAttributes

    public init(name: String, attributes: SFTPAttributes) {
        self.name = name
        self.attributes = attributes
    }
}

public enum SFTPError: Error, LocalizedError, Equatable {
    case status(SFTPStatusCode?, String)
    case badReply
    case unexpectedReply
    case connectionClosed(String)
    /// The first bytes back weren't SFTP, almost always because the remote
    /// shell prints text at login (an echo in ~/.bashrc, for example).
    case notSFTP(String)
    case unsafeName(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .status(let code, let message):
            if !message.isEmpty { return message }
            switch code {
            case .noSuchFile: return "No such file or folder."
            case .permissionDenied: return "Permission denied."
            case .unsupported: return "The server doesn't support that."
            default: return "The server reported a failure."
            }
        case .badReply:
            return "The server sent a reply 7 Term couldn't read."
        case .unexpectedReply:
            return "The server sent an unexpected reply."
        case .connectionClosed(let detail):
            return detail.isEmpty ? "The connection closed." : detail
        case .notSFTP(let preview):
            return "The server's login shell printed text before SFTP started (check ~/.bashrc or similar for echo or other output): “\(preview)”"
        case .unsafeName(let name):
            return "Skipped a file with an unsafe name from the server: “\(name)”"
        case .cancelled:
            return "Cancelled."
        }
    }

    public var code: SFTPStatusCode? {
        if case .status(let code, _) = self { return code }
        return nil
    }
}
