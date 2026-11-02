import Testing
@testable import SevenTermCore

@Suite struct SSHConfigScannerTests {
    @Test func findsConcreteAliasesWithFirstValuesWinning() {
        let config = """
        # Lab
        Host pve01 pve02
            HostName 10.0.0.21
            User root
            User ignored
        Host *.lab !bastion bastion
          Port=2222
        Host "quoted alias"
        Match host foo
            User nobody
        Host *
            ServerAliveInterval 30
        """
        let aliases = SSHConfigScanner.aliases(in: config)
        #expect(aliases.map(\.alias) == ["pve01", "pve02", "bastion"])
        #expect(aliases[0] == SSHConfigAlias(alias: "pve01", hostName: "10.0.0.21", user: "root"))
        #expect(aliases[1].hostName == "10.0.0.21")
        #expect(aliases[2].port == 2222)
    }

    @Test func keywordsIgnoreCaseAndEqualsSign() {
        let aliases = SSHConfigScanner.aliases(in: "host  jump\n  HOSTNAME = 192.0.2.10\n  port 22\n")
        #expect(aliases == [SSHConfigAlias(alias: "jump", hostName: "192.0.2.10", port: 22)])
    }

    @Test func matchEndsTheHostBlock() {
        let aliases = SSHConfigScanner.aliases(in: "Host a\nMatch all\nHostName shouldnotapply\n")
        #expect(aliases == [SSHConfigAlias(alias: "a")])
    }

    @Test func followsIncludesRelativeToDotSSHAndSkipsLoops() {
        let files: [String: String] = [
            "/Users/me/.ssh/config": "Include conf.d/*\nInclude ~/.orbstack/ssh/config\nHost main\n",
            // Includes the main config again: the scanner must not loop.
            "/Users/me/.ssh/conf.d/lab": "Host pve01\nInclude config\n",
            "/Users/me/.orbstack/ssh/config": "Host orb\n  HostName 127.0.0.1\n",
        ]
        let scanner = SSHConfigScanner(
            homeDirectory: "/Users/me",
            readFile: { files[$0] },
            expandGlob: { pattern in
                pattern == "/Users/me/.ssh/conf.d/*" ? ["/Users/me/.ssh/conf.d/lab"] : [pattern]
            }
        )
        let aliases = scanner.aliases(inFileAt: "/Users/me/.ssh/config")
        #expect(aliases.map(\.alias) == ["pve01", "orb", "main"])
    }

    @Test func missingFileYieldsNothing() {
        let scanner = SSHConfigScanner(homeDirectory: "/Users/me", readFile: { _ in nil }, expandGlob: { [$0] })
        #expect(scanner.aliases(inFileAt: "/Users/me/.ssh/config").isEmpty)
    }
}

@Suite struct SSHEffectiveConfigTests {
    @Test func readsHostnamePortAndUser() {
        let output = """
        user root
        hostname 10.0.0.21
        port 22
        identityfile ~/.ssh/id_ed25519
        """
        #expect(SSHEffectiveConfig.parse(output) == SSHEffectiveConfig(hostname: "10.0.0.21", port: 22, user: "root"))
    }

    @Test func rejectsOutputWithoutPort() {
        #expect(SSHEffectiveConfig.parse("hostname pve01\n") == nil)
    }

    @Test func argumentsMirrorAConnection() {
        let target = SSHTarget(user: "root", host: "pve01", port: 2222)
        #expect(SSHEffectiveConfig.arguments(for: target) == ["-G", "-l", "root", "-p", "2222", "--", "pve01"])
    }
}
