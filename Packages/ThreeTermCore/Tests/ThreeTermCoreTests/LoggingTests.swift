import CryptoKit
import Foundation
import Testing
@testable import ThreeTermCore

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "3term-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Suite struct LogNamingTests {
    @Test func safeComponentReplacesUnsafeCharacters() {
        #expect(LogNaming.safeComponent("root@pve01:22") == "root_pve01_22")
        #expect(LogNaming.safeComponent("../../etc") == "_._.._etc")
        #expect(LogNaming.safeComponent(".hidden") == "_hidden")
        #expect(LogNaming.safeComponent("") == "host")
    }

    @Test func baseNameUsesUTCStamp() {
        let date = Date(timeIntervalSince1970: 1_793_563_200) // 2026-11-01 20:00:00 UTC
        #expect(LogNaming.baseName(host: "pve01", protocolName: "ssh", segment: 2, startedAt: date)
            == "pve01_20261101-200000Z_ssh_seg2")
    }

    @Test func utcOffsetFormatsBothSigns() throws {
        let date = Date(timeIntervalSince1970: 1_793_563_200)
        #expect(LogNaming.utcOffset(for: date, in: try #require(TimeZone(identifier: "America/New_York"))) == "-05:00")
        #expect(LogNaming.utcOffset(for: date, in: try #require(TimeZone(identifier: "Asia/Kolkata"))) == "+05:30")
    }
}

@Suite struct SessionLogWriterTests {
    @Test func writesBytesHashSidecarAndMeta() throws {
        let folder = try temporaryFolder()
        let start = Date(timeIntervalSince1970: 1_793_563_200)
        let writer = try SessionLogWriter(folder: folder, host: "pve01", destination: "root@pve01",
                                          segment: 1, now: start, timeZone: TimeZone(identifier: "UTC")!)
        let chunks = [Data("login: ok\r\n".utf8), Data([0x1B, 0x5B, 0x33, 0x31, 0x6D]), Data("red\r\n".utf8)]
        for chunk in chunks { try writer.append(chunk) }
        let meta = try writer.close(now: start.addingTimeInterval(90))

        let expected = chunks.reduce(Data(), +)
        #expect(try Data(contentsOf: writer.logURL) == expected)
        #expect(writer.logURL.path.contains("/pve01/pve01_20261101-200000Z_ssh_seg1.log"))
        #expect(meta.sha256 == sha256Hex(expected))
        #expect(meta.byteCount == expected.count)
        #expect(meta.closedCleanly == true)
        #expect(meta.utcOffset == "+00:00")

        let sidecar = try String(contentsOf: LogFiles.sidecarURL(for: writer.logURL), encoding: .utf8)
        #expect(sidecar == "\(sha256Hex(expected))  pve01_20261101-200000Z_ssh_seg1.log\n")

        let metaURL = writer.logURL.deletingLastPathComponent()
            .appending(path: "pve01_20261101-200000Z_ssh_seg1.meta.json")
        #expect(try LogSegmentMeta.read(from: metaURL) == meta)
    }

    @Test func neverReusesAnExistingFile() throws {
        let folder = try temporaryFolder()
        let start = Date(timeIntervalSince1970: 1_793_563_200)
        let first = try SessionLogWriter(folder: folder, host: "pve01", destination: "pve01", segment: 1, now: start)
        let second = try SessionLogWriter(folder: folder, host: "pve01", destination: "pve01", segment: 1, now: start)
        #expect(first.logURL != second.logURL)
        #expect(second.logURL.lastPathComponent == "pve01_20261101-200000Z_ssh_seg1-2.log")
        try first.close()
        try second.close()
    }

    @Test func metaExistsWithoutEndUntilClosed() throws {
        let folder = try temporaryFolder()
        let writer = try SessionLogWriter(folder: folder, host: "pve01", destination: "pve01", segment: 1)
        let metaURL = LogFiles.readableURL(for: writer.logURL).deletingPathExtension()
            .appendingPathExtension("meta.json")
        #expect(try LogSegmentMeta.read(from: metaURL).endedAt == nil)
        try writer.close()
        #expect(try LogSegmentMeta.read(from: metaURL).endedAt != nil)
    }
}

@Suite struct LogMaintenanceTests {
    @Test func recoversUnclosedSegmentAndWritesReadableCopy() throws {
        let folder = try temporaryFolder()
        var writer: SessionLogWriter? = try SessionLogWriter(folder: folder, host: "pve01", destination: "pve01", segment: 1)
        let payload = Data("uptime\r\n 20:00 up 3 days\r\n".utf8)
        try writer?.append(payload)
        let logURL = try #require(writer?.logURL)
        writer = nil // simulates a crash: never closed

        let report = LogMaintenance.repair(folder: folder)
        // Compare names: the enumerator may spell the temp path differently (/private/var).
        #expect(report.recovered.map(\.lastPathComponent) == [logURL.lastPathComponent])
        #expect(report.failures.isEmpty)

        let metaURL = logURL.deletingPathExtension().appendingPathExtension("meta.json")
        let meta = try LogSegmentMeta.read(from: metaURL)
        #expect(meta.closedCleanly == false)
        #expect(meta.sha256 == sha256Hex(payload))
        #expect(try String(contentsOf: LogFiles.readableURL(for: logURL), encoding: .utf8)
            == "uptime\n 20:00 up 3 days\n")

        // A second run has nothing left to do.
        let again = LogMaintenance.repair(folder: folder)
        #expect(again.recovered.isEmpty && again.readableCopies.isEmpty)
    }
}

@Suite struct TranscriptRendererTests {
    private func render(_ text: String) -> String {
        TranscriptRenderer.render(Data(text.utf8))
    }

    @Test func plainLines() {
        #expect(render("hello\r\nworld\r\n") == "hello\nworld\n")
    }

    @Test func stripsColorsAndTitles() {
        #expect(render("\u{1B}]0;root@pve01: ~\u{07}\u{1B}[1;32mroot@pve01\u{1B}[0m:~# ls\r\n") == "root@pve01:~# ls\n")
    }

    @Test func carriageReturnOverwritesProgress() {
        #expect(render("10%\r20%\r100%\r\n") == "100%\n")
    }

    @Test func backspaceEraseFromShell() {
        #expect(render("lss\u{08} \u{08}\r\n") == "ls\n")
    }

    @Test func eraseToEndOfLine() {
        #expect(render("abcdef\rXY\u{1B}[K\r\n") == "XY\n")
    }

    @Test func expandsTabs() {
        #expect(render("a\tb\r\n") == "a       b\n")
    }

    @Test func omitsFullScreenPrograms() {
        let session = "$ vim notes\r\n\u{1B}[?1049h\u{1B}[H\u{1B}[2Jlots of vim drawing\r\n~\r\n\u{1B}[?1049l$ exit\r\n"
        #expect(render(session) == "$ vim notes\n\(TranscriptRenderer.fullScreenMarker)\n$ exit\n")
    }

    @Test func keepsBlankLines() {
        #expect(render("a\r\n\r\nb\r\n") == "a\n\nb\n")
    }

    @Test func emptyInput() {
        #expect(render("") == "")
    }
}

@Suite struct LogByDefaultTests {
    @Test func savedAndLoaded() throws {
        let library = try HostLibrary.inMemory()
        var draft = HostDraft()
        draft.name = "pve01"
        draft.hostname = "10.0.0.21"
        draft.logByDefault = true
        let saved = try library.save(draft)
        #expect(saved.host.logByDefault)
        #expect(try library.entries().first?.host.logByDefault == true)
        #expect(HostDraft(entry: saved).logByDefault)
    }
}
