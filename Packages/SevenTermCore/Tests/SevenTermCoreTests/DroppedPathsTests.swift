import Foundation
import Testing
@testable import SevenTermCore

@Suite struct DroppedPathsTests {
    @Test func plainPathGetsTrailingSpace() {
        #expect(DroppedPaths.typedText(for: ["/Users/me/Projects"]) == "/Users/me/Projects ")
    }

    @Test func spaceIsEscaped() {
        #expect(DroppedPaths.typedText(for: ["/Users/me/My Folder"]) == "/Users/me/My\\ Folder ")
    }

    @Test func shellSpecialCharactersAreEscaped() {
        for character in ["'", "\"", "$", "&", "(", ")", ";", "|", "*", "?", "[", "]", "{", "}", "<", ">", "!", "#", "\\", "`"] {
            #expect(DroppedPaths.typedText(for: ["/a\(character)b"]) == "/a\\\(character)b ", "\(character)")
        }
    }

    @Test func safeCharactersAreLeftAlone() {
        #expect(DroppedPaths.typedText(for: ["/a_b-c.d,e:f+g@h%i=j^k/0123"]) == "/a_b-c.d,e:f+g@h%i=j^k/0123 ")
    }

    @Test func tildeIsEscaped() {
        #expect(DroppedPaths.typedText(for: ["~/notes"]) == "\\~/notes ")
        #expect(DroppedPaths.typedText(for: ["/tmp/~x"]) == "/tmp/\\~x ")
    }

    @Test func unicodeIsKept() {
        #expect(DroppedPaths.typedText(for: ["/Users/me/Café 😀"]) == "/Users/me/Café\\ 😀 ")
    }

    @Test func controlCharactersSwitchToSingleQuotes() {
        #expect(DroppedPaths.typedText(for: ["/tmp/a\nb"]) == "'/tmp/a\nb' ")
        #expect(DroppedPaths.typedText(for: ["/tmp/it's\tx"]) == "'/tmp/it'\\''s\tx' ")
    }

    @Test func severalPathsAreSeparatedBySpaces() {
        #expect(DroppedPaths.typedText(for: ["/a", "/b c"]) == "/a /b\\ c ")
    }

    @Test func noPathsTypesNothing() {
        #expect(DroppedPaths.typedText(for: []) == "")
    }

    @Test func payloadRoundTrips() {
        let id = UUID()
        let text = RemoteDragPayload.make(browserID: id, path: "/var/log/my file:1")
        #expect(text == "7term-remote:\(id.uuidString):/var/log/my file:1")
        let parsed = RemoteDragPayload.parse(text)
        #expect(parsed?.browserID == id)
        #expect(parsed?.path == "/var/log/my file:1")
    }

    @Test func otherTextIsNotAPayload() {
        #expect(RemoteDragPayload.parse("/Users/me/file") == nil)
        #expect(RemoteDragPayload.parse("7term-remote:not-a-uuid:/x") == nil)
        #expect(RemoteDragPayload.parse("7term-remote:\(UUID().uuidString):") == nil)
    }

    @Test func sameMachineIgnoresKeyCaseAndDefaultPort() {
        let saved = SSHTarget(user: "root", host: "PVE01.lab", port: 22, identityFile: "~/.ssh/id_ed25519")
        #expect(saved.isSameMachine(as: SSHTarget(user: "Root", host: "pve01.lab")))
        #expect(!saved.isSameMachine(as: SSHTarget(user: "admin", host: "pve01.lab")))
        #expect(!saved.isSameMachine(as: SSHTarget(user: "root", host: "pve01.lab", port: 2222)))
        #expect(!saved.isSameMachine(as: SSHTarget(user: "root", host: "pve02.lab")))
        #expect(!SSHTarget(host: "a").isSameMachine(as: SSHTarget(user: "me", host: "a")))
    }
}
