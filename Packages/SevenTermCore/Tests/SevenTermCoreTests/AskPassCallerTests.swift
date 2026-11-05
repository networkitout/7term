import Darwin
import Foundation
import Testing
@testable import SevenTermCore

@Suite struct AskPassCallerTests {
    let app = "/Applications/7 Term.app/Contents/MacOS/7 Term"

    @Test func sshStartedBy7Term() {
        #expect(AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", app, "/sbin/launchd"], app: app))
    }

    @Test func sshStartedBySftpStartedBy7Term() {
        #expect(AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", "/usr/bin/sftp", app], app: app))
    }

    @Test func helperRunByAnotherProgram() {
        #expect(!AskPassCaller.isTrusted(ancestors: ["/tmp/evil", "/bin/zsh"], app: app))
        #expect(!AskPassCaller.isTrusted(ancestors: ["/bin/zsh", app], app: app))
    }

    @Test func sshRunByAnotherProgram() {
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", "/bin/zsh", "/usr/bin/login"], app: app))
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", "/usr/bin/sftp", "/bin/zsh"], app: app))
    }

    @Test func proxyJumpHopIsRefused() {
        // The jump host's ssh is a child of the outer ssh.
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", "/usr/bin/ssh", app], app: app))
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", "/bin/sh", "/usr/bin/ssh"], app: app))
    }

    @Test func orphanedOrMissing() {
        #expect(!AskPassCaller.isTrusted(ancestors: [], app: app))
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh"], app: app))
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", "/usr/bin/sftp"], app: app))
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", ""], app: ""))
    }

    @Test func differentCopyOfTheApp() {
        #expect(!AskPassCaller.isTrusted(ancestors: ["/usr/bin/ssh", "/tmp/7 Term"], app: app))
    }

    @Test func realAncestry() {
        let me = ProcessAncestry.executablePath(of: getpid())
        #expect(me != nil)
        #expect(ProcessAncestry.parent(of: getpid()) == getppid())
        let ancestors = ProcessAncestry.ancestorPaths(of: getpid(), count: 2)
        #expect(ancestors.first == ProcessAncestry.executablePath(of: getppid()))
        // The test runner isn't run by ssh.
        #expect(!AskPassCaller.currentProcessIsTrusted())
    }

    /// The kernel must report ssh and sftp at exactly the paths the check
    /// expects, or 7 Term's own ssh would never be trusted.
    @Test(arguments: [
        (AskPassCaller.ssh, ["-F", "/dev/null", "-o", "BatchMode=yes", "-o", "ProxyCommand=sleep 5", "x"]),
        (AskPassCaller.sftp, ["-F", "/dev/null", "-o", "BatchMode=yes", "-o", "ProxyCommand=sleep 5", "x"]),
    ])
    func kernelReportsExpectedPath(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }
        let pid = process.processIdentifier
        #expect(ProcessAncestry.executablePath(of: pid) == executable)
        #expect(ProcessAncestry.parent(of: pid) == getpid())
    }
}
