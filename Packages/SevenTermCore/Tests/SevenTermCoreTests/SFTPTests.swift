import Foundation
import Testing
@testable import SevenTermCore

/// These run the client against OpenSSH's real sftp-server over pipes: the
/// same program sshd starts for `ssh -s host sftp`, minus the network.
private let serverPath = ["/usr/libexec/sftp-server", "/usr/lib/openssh/sftp-server"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

private func connect() async throws -> SFTPClient {
    try await SFTPClient.launch(executable: serverPath!, arguments: [], environment: [:])
}

private func scratchFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("7term-sftp-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func randomData(_ count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var last: UInt64 = 0
    func add(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    func progress(_ value: UInt64) { lock.withLock { last = value } }
    var bytes: Data { lock.withLock { data } }
    var lastProgress: UInt64 { lock.withLock { last } }
}

@Suite(.enabled(if: serverPath != nil, "needs OpenSSH sftp-server"))
struct SFTPClientTests {
    @Test func handshakeAndRealPath() async throws {
        let client = try await connect()
        defer { client.close() }
        let home = try await client.realPath(".")
        #expect(home.hasPrefix("/"))
        let folder = try scratchFolder()
        // realpath(3), as the server uses: on macOS /var is really /private/var,
        // which Foundation's resolvingSymlinksInPath() hides again.
        let expected = realpath(folder.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        #expect(try await client.realPath(folder.path + "/.") == expected)
    }

    @Test func folderOperations() async throws {
        let client = try await connect()
        defer { client.close() }
        let root = try scratchFolder().path

        try await client.makeDirectory(root + "/a")
        _ = FileManager.default.createFile(atPath: root + "/a/file.txt", contents: Data("hi".utf8))
        let listing = try await client.list(root + "/a")
        #expect(listing.map(\.name) == ["file.txt"])
        #expect(listing[0].attributes.size == 2)
        #expect(listing[0].attributes.isRegularFile)
        #expect(try await client.stat(root + "/a").isDirectory)

        try await client.rename(root + "/a/file.txt", to: root + "/a/renamed.txt")
        #expect(try await client.exists(root + "/a/file.txt") == nil)
        #expect(try await client.exists(root + "/a/renamed.txt") != nil)

        await #expect(throws: SFTPError.self) { try await client.list(root + "/missing") }
        do {
            _ = try await client.stat(root + "/missing")
            Issue.record("expected an error")
        } catch let error as SFTPError {
            #expect(error.code == .noSuchFile)
        }

        try await client.makeDirectory(root + "/a/b")
        _ = FileManager.default.createFile(atPath: root + "/a/b/deep", contents: Data())
        try await client.removeTree(root + "/a")
        #expect(!FileManager.default.fileExists(atPath: root + "/a"))
    }

    @Test(arguments: [0, 1, 32_768, 32_775, 3_145_851]) // empty, 1 byte, one chunk, a chunk plus 7, ~3 MB
    func roundTrip(size: Int) async throws {
        let client = try await connect()
        defer { client.close() }
        let root = try scratchFolder()
        let original = randomData(size)
        let source = root.appendingPathComponent("source.bin")
        try original.write(to: source)

        let sent = Collector()
        let uploaded = try await client.upload(
            source, to: root.path + "/remote.bin",
            onData: sent.add, progress: sent.progress)
        #expect(uploaded == UInt64(size))
        #expect(sent.bytes == original)
        #expect(sent.lastProgress == UInt64(size))
        #expect(try Data(contentsOf: root.appendingPathComponent("remote.bin")) == original)
        // The partial file was renamed away.
        #expect(!FileManager.default.fileExists(atPath: root.path + "/.remote.bin.7term-part"))

        let received = Collector()
        let destination = root.appendingPathComponent("back.bin")
        let downloaded = try await client.download(
            root.path + "/remote.bin", to: destination,
            onData: received.add, progress: received.progress)
        #expect(downloaded == UInt64(size))
        #expect(received.bytes == original)
        #expect(try Data(contentsOf: destination) == original)
        #expect(!FileManager.default.fileExists(atPath: root.path + "/.back.bin.7term-part"))
    }

    @Test func uploadReplacesOnlyWhenAsked() async throws {
        let client = try await connect()
        defer { client.close() }
        let root = try scratchFolder()
        let source = root.appendingPathComponent("new.txt")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: root.appendingPathComponent("target.txt"))

        try await client.upload(source, to: root.path + "/target.txt", replacing: true)
        #expect(try String(contentsOf: root.appendingPathComponent("target.txt"), encoding: .utf8) == "new")

        // Downloads refuse to replace unless asked.
        let local = root.appendingPathComponent("local.txt")
        try Data("mine".utf8).write(to: local)
        await #expect(throws: (any Error).self) {
            try await client.download(root.path + "/target.txt", to: local)
        }
        #expect(try String(contentsOf: local, encoding: .utf8) == "mine")
        try await client.download(root.path + "/target.txt", to: local, replacing: true)
        #expect(try String(contentsOf: local, encoding: .utf8) == "new")
    }

    @Test func downloadKeepsPermissions() async throws {
        let client = try await connect()
        defer { client.close() }
        let root = try scratchFolder()
        let script = root.appendingPathComponent("run.sh")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: script.path)

        let copy = root.appendingPathComponent("copy.sh")
        try await client.download(script.path, to: copy)
        let mode = try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o750)
    }

    @Test func walkListsFoldersBeforeContentsAndSkipsLinks() async throws {
        let client = try await connect()
        defer { client.close() }
        let root = try scratchFolder()
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("top/sub"), withIntermediateDirectories: true)
        _ = manager.createFile(atPath: root.path + "/top/a.txt", contents: Data("a".utf8))
        _ = manager.createFile(atPath: root.path + "/top/sub/b.txt", contents: Data("b".utf8))
        // A link back up: following it would loop forever.
        try manager.createSymbolicLink(atPath: root.path + "/top/sub/loop", withDestinationPath: root.path + "/top")

        let items = try await client.walk(root.path + "/top")
        #expect(items.map(\.relativePath) == ["a.txt", "sub", "sub/b.txt", "sub/loop"])
        #expect(items.first { $0.relativePath == "sub/loop" }?.attributes.isSymlink == true)
    }

    @Test func manyRequestsInFlight() async throws {
        let client = try await connect()
        defer { client.close() }
        let root = try scratchFolder().path
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<200 {
                group.addTask { try await client.realPath(root) }
            }
            for try await path in group {
                #expect(path.hasSuffix(URL(fileURLWithPath: root).lastPathComponent))
            }
        }
    }

    @Test func cancelledDownloadLeavesNothingBehind() async throws {
        let client = try await connect()
        defer { client.close() }
        let root = try scratchFolder()
        try randomData(8 * 1024 * 1024).write(to: root.appendingPathComponent("big.bin"))
        let destination = root.appendingPathComponent("partial.bin")

        let task = Task {
            try await client.download(root.path + "/big.bin", to: destination, progress: { total in
                if total > 1024 * 1024 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: root.path + "/.partial.bin.7term-part"))
        // The connection is still usable afterwards.
        #expect(try await client.realPath(root.path).hasPrefix("/"))
    }
}

@Suite struct SFTPStreamTests {
    @Test func loginBannerIsReportedClearly() async throws {
        do {
            _ = try await SFTPClient.launch(
                executable: "/bin/sh",
                arguments: ["-c", "echo 'Welcome to the lab'; cat >/dev/null"],
                environment: [:])
            Issue.record("expected an error")
        } catch let error as SFTPError {
            guard case .notSFTP(let preview) = error else {
                Issue.record("got \(error)")
                return
            }
            #expect(preview.contains("Welcome"))
        }
    }

    @Test func sshFailureCarriesItsMessage() async throws {
        do {
            _ = try await SFTPClient.launch(
                executable: "/bin/sh",
                arguments: ["-c", "echo 'user@host: Permission denied (publickey).' >&2; exit 255"],
                environment: [:])
            Issue.record("expected an error")
        } catch let error as SFTPError {
            #expect(error == .connectionClosed("user@host: Permission denied (publickey)."))
        }
    }

    @Test func requestsAfterCloseFail() async throws {
        guard let serverPath else { return }
        let client = try await SFTPClient.launch(executable: serverPath, arguments: [], environment: [:])
        client.close()
        await #expect(throws: SFTPError.self) { try await client.realPath(".") }
    }
}

@Suite struct SFTPWireTests {
    @Test func attributesRoundTrip() throws {
        let attributes = SFTPAttributes(
            size: 1 << 40, uid: 501, gid: 20, permissions: 0o100644,
            accessTime: 1_700_000_000, modificationTime: 1_700_000_100)
        var writer = SFTPWriter()
        writer.attributes(attributes)
        var reader = SFTPReader(writer.data)
        #expect(try reader.attributes() == attributes)
        #expect(reader.isAtEnd)
        #expect(attributes.modeString == "rw-r--r--")
        #expect(attributes.isRegularFile && !attributes.isDirectory)
    }

    @Test func truncatedInputThrows() {
        var reader = SFTPReader(Data([0, 0, 0, 9, 65]))
        #expect(throws: SFTPError.badReply) { try reader.string() }
    }

    @Test(arguments: [
        ("report.txt", true), (".bashrc", true), ("with space", true), ("ünïcode", true),
        ("", false), (".", false), ("..", false), ("../etc", false), ("a/b", false), ("bad\nname", false),
    ])
    func safeNames(name: String, safe: Bool) {
        #expect(SFTPPath.isSafeName(name) == safe)
    }

    @Test func paths() {
        #expect(SFTPPath.join("/home/me", "x") == "/home/me/x")
        #expect(SFTPPath.join("/", "x") == "/x")
        #expect(SFTPPath.parent("/home/me/x") == "/home/me")
        #expect(SFTPPath.parent("/x") == "/")
        #expect(SFTPPath.name("/home/me/x") == "x")
    }
}
