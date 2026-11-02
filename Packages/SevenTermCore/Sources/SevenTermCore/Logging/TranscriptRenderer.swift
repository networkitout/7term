import Foundation

/// Turns raw terminal output into readable text for the `.txt` copy.
///
/// It plays back what a line-oriented terminal would show: carriage returns
/// and backspaces overwrite, erase-to-end-of-line truncates, colors and other
/// escape sequences disappear, and tabs expand. Output from full-screen
/// programs (vim, htop, less, top), which draw on the alternate screen, is
/// replaced by a one-line marker. Best effort: the raw `.log` is the record.
public enum TranscriptRenderer {
    public static let fullScreenMarker = "[full-screen program output omitted]"

    public static func render(_ data: Data) -> String {
        var state = State()
        let text = String(decoding: data, as: UTF8.self)
        var scalars = Array(text.unicodeScalars)[...]
        while let scalar = scalars.popFirst() {
            state.consume(scalar, rest: &scalars)
        }
        state.commitLine(force: false)
        return state.lines.isEmpty ? "" : state.lines.joined(separator: "\n") + "\n"
    }

    private struct State {
        var lines: [String] = []
        var line: [Character] = []
        var cursor = 0
        var inAlternateScreen = false

        mutating func consume(_ scalar: Unicode.Scalar, rest: inout ArraySlice<Unicode.Scalar>) {
            switch scalar {
            case "\u{1B}":
                escape(rest: &rest)
            case "\n":
                if !inAlternateScreen { commitLine(force: true) }
            case "\r":
                cursor = 0
            case "\u{08}":
                cursor = max(0, cursor - 1)
            case "\t":
                guard !inAlternateScreen else { return }
                let next = (cursor / 8 + 1) * 8
                while cursor < next { put(" ") }
            default:
                guard !inAlternateScreen, scalar.value >= 0x20, scalar.value != 0x7F else { return }
                put(Character(scalar))
            }
        }

        mutating func put(_ character: Character) {
            if cursor < line.count {
                line[cursor] = character
            } else {
                while line.count < cursor { line.append(" ") }
                line.append(character)
            }
            cursor += 1
        }

        mutating func commitLine(force: Bool) {
            let text = String(line).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if force || !text.isEmpty { lines.append(text) }
            line = []
            cursor = 0
        }

        mutating func escape(rest: inout ArraySlice<Unicode.Scalar>) {
            guard let kind = rest.popFirst() else { return }
            switch kind {
            case "[":
                csi(rest: &rest)
            case "]", "P", "X", "^", "_":
                // OSC, DCS, SOS, PM, APC: skip to BEL or ESC \.
                while let next = rest.popFirst() {
                    if next == "\u{07}" { break }
                    if next == "\u{1B}" {
                        if rest.first == "\\" { rest.removeFirst() }
                        break
                    }
                }
            case "(", ")", "*", "+", "-", ".", "/", "#", "%", " ":
                // Character set and similar: one more byte.
                _ = rest.popFirst()
            default:
                // Two-byte sequence such as ESC 7, ESC 8, ESC =, ESC M.
                break
            }
        }

        mutating func csi(rest: inout ArraySlice<Unicode.Scalar>) {
            var parameters = ""
            var final: Unicode.Scalar?
            while let next = rest.popFirst() {
                if (0x40...0x7E).contains(next.value) {
                    final = next
                    break
                }
                parameters.unicodeScalars.append(next)
            }
            guard let final else { return }

            if parameters.hasPrefix("?"), final == "h" || final == "l" {
                let modes = parameters.dropFirst().split(separator: ";")
                if modes.contains(where: { ["1049", "1047", "47"].contains($0) }) {
                    setAlternateScreen(final == "h")
                }
                return
            }
            guard !inAlternateScreen else { return }

            let count = max(1, Int(parameters) ?? 1)
            switch final {
            case "K":
                // Erase in line. 0 (default): cursor to end; 1: start to cursor; 2: whole line.
                switch Int(parameters) ?? 0 {
                case 0: if cursor < line.count { line.removeSubrange(cursor...) }
                case 1: for index in 0..<min(cursor + 1, line.count) { line[index] = " " }
                default: line = []
                }
            case "C":
                cursor += count
            case "D":
                cursor = max(0, cursor - count)
            case "G":
                cursor = max(0, count - 1)
            default:
                break
            }
        }

        mutating func setAlternateScreen(_ entering: Bool) {
            guard entering != inAlternateScreen else { return }
            if entering {
                commitLine(force: false)
                lines.append(TranscriptRenderer.fullScreenMarker)
            }
            inAlternateScreen = entering
            line = []
            cursor = 0
        }
    }
}
