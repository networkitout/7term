import Testing
@testable import SevenTermCore

@Suite struct LocalShellTests {
    // MARK: Which shell

    @Test func usesTheAccountShellWhenItRuns() {
        let shell = LocalShell.resolve(passwdShell: "/opt/homebrew/bin/fish", isExecutable: { _ in true })
        #expect(shell.path == "/opt/homebrew/bin/fish")
    }

    @Test(arguments: [nil, "", "fish", "/gone/bash"] as [String?])
    func fallsBackToZshWhenTheAccountShellIsUnusable(_ passwdShell: String?) {
        let shell = LocalShell.resolve(passwdShell: passwdShell, isExecutable: { $0 != "/gone/bash" })
        #expect(shell.path == "/bin/zsh")
    }

    @Test func startsAsALoginShell() {
        let shell = LocalShell(path: "/bin/zsh")
        #expect(shell.name == "zsh")
        #expect(shell.loginArgv0 == "-zsh")
    }

    // MARK: The This Mac row

    @Test func subtitleNamesTheShell() {
        #expect(LocalTerminal.subtitle(shellName: "zsh") == "Local terminal (zsh)")
    }

    @Test(arguments: ["", "  ", "mac", "LOCAL", "zs"])
    func filterKeepsTheRow(_ query: String) {
        #expect(LocalTerminal.matches(query: query, shellName: "zsh"))
    }

    @Test func filterForAHostHidesTheRow() {
        #expect(!LocalTerminal.matches(query: "core-sw", shellName: "zsh"))
    }

    @Test func machineNameIsTheShortHostName() {
        #expect(LocalTerminal.machineName(hostName: "mbp.lan") == "mbp")
        #expect(LocalTerminal.machineName(hostName: "") == "localhost")
    }

    // MARK: The shell's environment

    @Test func localEnvironmentAddsShellAndTerminalProgramAndNothingElse() {
        let environment = ChildEnvironment.makeLocal(
            from: ["HOME": "/Users/a", "DYLD_INSERT_LIBRARIES": "x", "AWS_SECRET_ACCESS_KEY": "y"],
            shell: "/bin/zsh"
        )
        #expect(environment.contains("SHELL=/bin/zsh"))
        #expect(environment.contains("TERM_PROGRAM=7Term"))
        #expect(environment.contains("HOME=/Users/a"))
        #expect(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(!environment.contains { $0.hasPrefix("DYLD_") || $0.hasPrefix("AWS_") })
    }
}
