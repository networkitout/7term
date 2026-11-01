import Testing
@testable import ThreeTermCore

@Suite struct SSHTargetTests {
    @Test func plainHost() {
        #expect(SSHTarget.parse("pve01") == SSHTarget(host: "pve01"))
    }

    @Test func userHostAndPort() {
        #expect(SSHTarget.parse("root@pve01:2222") == SSHTarget(user: "root", host: "pve01", port: 2222))
    }

    @Test func ipv4WithUser() {
        #expect(SSHTarget.parse("laremy@10.0.0.21") == SSHTarget(user: "laremy", host: "10.0.0.21"))
    }

    @Test func bracketedIPv6WithPort() {
        #expect(SSHTarget.parse("admin@[fe80::1]:22") == SSHTarget(user: "admin", host: "fe80::1", port: 22))
    }

    @Test func bareIPv6() {
        #expect(SSHTarget.parse("fe80::1") == SSHTarget(host: "fe80::1"))
    }

    @Test func userContainingAtSign() {
        #expect(SSHTarget.parse("svc@corp.local@jump01") == SSHTarget(user: "svc@corp.local", host: "jump01"))
    }

    @Test func surroundingSpacesAreTrimmed() {
        #expect(SSHTarget.parse("  pve02  ") == SSHTarget(host: "pve02"))
    }

    @Test(arguments: [
        "", "   ", "@pve01", "root@", "pve01:", "pve01:abc", "pve01:0", "pve01:65536",
        "[fe80::1", "[fe80::1]x", "two words", "-oProxyCommand=evil", "root@-oProxyCommand=evil",
        "-l@pve01", "pve01\u{0007}",
    ])
    func rejects(_ input: String) {
        #expect(SSHTarget.parse(input) == nil)
    }

    @Test func sshArgumentsEndOptionsBeforeHost() {
        let target = SSHTarget(user: "root", host: "pve01", port: 2222)
        #expect(target.sshArguments == ["-l", "root", "-p", "2222", "--", "pve01"])
    }

    @Test func sshArgumentsForBareHost() {
        #expect(SSHTarget(host: "pve01").sshArguments == ["--", "pve01"])
    }

    @Test func displayName() {
        #expect(SSHTarget(user: "root", host: "pve01", port: 2222).displayName == "root@pve01:2222")
        #expect(SSHTarget(host: "pve01").displayName == "pve01")
    }
}

@Suite struct ChildEnvironmentTests {
    @Test func defaultsWhenParentIsEmpty() {
        let environment = ChildEnvironment.make(from: [:])
        #expect(environment.contains("LANG=en_US.UTF-8"))
        #expect(environment.contains("TERM=xterm-256color"))
        #expect(environment.contains("COLORTERM=truecolor"))
        #expect(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
    }

    @Test func keepsParentLang() {
        let environment = ChildEnvironment.make(from: ["LANG": "en_GB.UTF-8"])
        #expect(environment.contains("LANG=en_GB.UTF-8"))
    }

    @Test func passesAgentSocketButNotOtherVariables() {
        let environment = ChildEnvironment.make(from: [
            "SSH_AUTH_SOCK": "/tmp/agent.sock",
            "AWS_SECRET_ACCESS_KEY": "nope",
            "DYLD_INSERT_LIBRARIES": "nope",
        ])
        #expect(environment.contains("SSH_AUTH_SOCK=/tmp/agent.sock"))
        #expect(!environment.contains { $0.hasPrefix("AWS_") || $0.hasPrefix("DYLD_") })
    }
}
