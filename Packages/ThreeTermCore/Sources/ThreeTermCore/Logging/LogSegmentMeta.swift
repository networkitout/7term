import Foundation

/// The `.meta.json` written beside every log segment. It's created when the
/// segment opens (with no end, size or hash) and completed when it closes, so
/// a segment whose meta has no `endedAt` was cut off by a crash.
public struct LogSegmentMeta: Codable, Equatable, Sendable {
    public var formatVersion = 1
    /// The tab's label: a saved host's name, or the destination.
    public var host: String
    /// What ssh was pointed at, e.g. `root@pve01:2222`.
    public var destination: String
    public var protocolName: String
    /// 1 for the first time logging was switched on in a tab, 2 for the next…
    public var segment: Int
    public var logFile: String
    /// UTC.
    public var startedAt: Date
    /// The Mac's offset from UTC when the segment started, e.g. "-05:00".
    public var utcOffset: String
    public var endedAt: Date?
    public var byteCount: Int?
    public var sha256: String?
    /// False when the hash was computed after a crash instead of at close.
    public var closedCleanly: Bool?

    public init(
        host: String,
        destination: String,
        protocolName: String,
        segment: Int,
        logFile: String,
        startedAt: Date,
        utcOffset: String
    ) {
        self.host = host
        self.destination = destination
        self.protocolName = protocolName
        self.segment = segment
        self.logFile = logFile
        self.startedAt = startedAt
        self.utcOffset = utcOffset
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func write(to url: URL) throws {
        try Self.encoder.encode(self).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> LogSegmentMeta {
        try decoder.decode(LogSegmentMeta.self, from: Data(contentsOf: url))
    }
}
