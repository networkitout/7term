import Foundation

/// File names for log segments:
/// `<folder>/<host>/<host>_<yyyyMMdd-HHmmss>Z_<protocol>_seg<n>` + `.log`,
/// `.log.sha256`, `.meta.json` and `.txt`.
public enum LogNaming {
    public static let logExtension = "log"
    public static let sidecarSuffix = ".log.sha256"
    public static let metaSuffix = ".meta.json"
    public static let readableExtension = "txt"

    /// Letters, digits, ".", "_" and "-" survive; anything else becomes "_".
    /// Never empty, never hidden, at most 64 characters.
    public static func safeComponent(_ text: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var result = String(text.map { allowed.contains($0) ? $0 : "_" }.prefix(64))
        if result.hasPrefix(".") { result = "_" + String(result.dropFirst()) }
        return result.isEmpty ? "host" : result
    }

    public static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date) + "Z"
    }

    /// "+00:00" style offset for `date` in `timeZone`.
    public static func utcOffset(for date: Date, in timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d:%02d", sign, minutes / 60, minutes % 60)
    }

    /// The base name (no extension) for a new segment.
    public static func baseName(host: String, protocolName: String, segment: Int, startedAt: Date) -> String {
        let hostPart = safeComponent(host)
        return "\(hostPart)_\(stamp(startedAt))_\(safeComponent(protocolName))_seg\(segment)"
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
