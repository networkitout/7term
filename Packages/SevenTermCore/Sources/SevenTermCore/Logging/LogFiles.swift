import CryptoKit
import Foundation

/// File-level helpers shared by the writer and by repair.
public enum LogFiles {
    /// `<name>.log` → `<name>.log.sha256`
    public static func sidecarURL(for logURL: URL) -> URL {
        logURL.deletingLastPathComponent().appending(path: logURL.lastPathComponent + ".sha256")
    }

    /// `<name>.log` → `<name>.txt`
    public static func readableURL(for logURL: URL) -> URL {
        logURL.deletingPathExtension().appendingPathExtension(LogNaming.readableExtension)
    }

    /// `<name>.meta.json` → `<name>.log`, read from the meta itself.
    static func logURL(forMetaAt metaURL: URL, meta: LogSegmentMeta) -> URL {
        metaURL.deletingLastPathComponent().appending(path: meta.logFile)
    }

    /// Same format as `shasum -a 256`, so `shasum -a 256 -c <sidecar>` run in
    /// the log's folder verifies it.
    static func writeSidecar(digest: String, for logURL: URL) throws {
        let line = "\(digest)  \(logURL.lastPathComponent)\n"
        try Data(line.utf8).write(to: sidecarURL(for: logURL), options: .atomic)
    }

    /// SHA-256 of a file, read in 1 MiB chunks.
    static func sha256(of url: URL) throws -> (digest: String, byteCount: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            total += chunk.count
        }
        return (SessionLogWriter.hex(hasher.finalize()), total)
    }

    /// Writes the readable `.txt` beside a raw log. The raw file is not changed.
    public static func writeReadableCopy(for logURL: URL) throws {
        let raw = try Data(contentsOf: logURL)
        let text = TranscriptRenderer.render(raw)
        try Data(text.utf8).write(to: readableURL(for: logURL), options: .atomic)
    }
}
