import Foundation

/// Run at launch: finishes segments that a crash or a forced quit left open,
/// and writes any readable copies that weren't written.
public enum LogMaintenance {
    public struct Report: Equatable, Sendable {
        /// Segments that had no hash and were hashed now.
        public var recovered: [URL] = []
        /// Readable `.txt` copies written now.
        public var readableCopies: [URL] = []
        /// Files that couldn't be read or written.
        public var failures: [URL] = []
    }

    public static func repair(folder: URL) -> Report {
        var report = Report()
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return report }

        for case let metaURL as URL in enumerator where metaURL.lastPathComponent.hasSuffix(LogNaming.metaSuffix) {
            do {
                var meta = try LogSegmentMeta.read(from: metaURL)
                let logURL = LogFiles.logURL(forMetaAt: metaURL, meta: meta)
                guard FileManager.default.fileExists(atPath: logURL.path) else { continue }

                if meta.endedAt == nil {
                    let (digest, count) = try LogFiles.sha256(of: logURL)
                    let modified = try logURL.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate
                    meta.endedAt = modified ?? meta.startedAt
                    meta.byteCount = count
                    meta.sha256 = digest
                    meta.closedCleanly = false
                    try LogFiles.writeSidecar(digest: digest, for: logURL)
                    try meta.write(to: metaURL)
                    report.recovered.append(logURL)
                }

                let readable = LogFiles.readableURL(for: logURL)
                if !FileManager.default.fileExists(atPath: readable.path) {
                    try LogFiles.writeReadableCopy(for: logURL)
                    report.readableCopies.append(readable)
                }
            } catch {
                report.failures.append(metaURL)
            }
        }
        return report
    }
}
