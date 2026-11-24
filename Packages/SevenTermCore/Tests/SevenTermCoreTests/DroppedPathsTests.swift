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

    /// Typed into a pty, control bytes act as they arrive (^U erases the line,
    /// CR submits it), whatever quoting surrounds them, so such a path is refused.
    @Test func controlCharactersRefuseTheDrop() {
        for scalar in [0x0A, 0x0D, 0x09, 0x03, 0x15, 0x0F, 0x1B, 0x7F, 0x85, 0x9B] as [UInt32] {
            let character = String(Character(Unicode.Scalar(scalar)!))
            #expect(DroppedPaths.typedText(for: ["/tmp/x\(character)id"]) == nil, "U+\(String(scalar, radix: 16))")
        }
        #expect(DroppedPaths.typedText(for: ["/ok", "/tmp/bad\u{15}"]) == nil)
    }

    @Test func emojiJoinersAreNotControlCharacters() {
        let family = "/tmp/👨‍👩‍👧"
        #expect(DroppedPaths.typedText(for: [family]) == family + " ")
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
