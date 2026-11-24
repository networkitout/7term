# Terminal Drops and Tab Reconnect Implementation Plan

> **For agentic workers:** executed inline (small change).

**Goal:** Reconnect on the tab's right-click menu; dropping Finder items or host-pane rows on a terminal tab types their paths.

**Spec:** `docs/superpowers/specs/2026-11-23-terminal-drops-and-reconnect-design.md`

## Global Constraints

- Branch `feature/tab-drops-reconnect` from `main`. Pull request when done; no push to `main`.
- Core tests: `cd Packages/SevenTermCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. App build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate` then `xcodebuild -project SevenTerm.xcodeproj -scheme SevenTerm -configuration Debug build` (expect `BUILD SUCCEEDED`).
- A drop never sends Return. Nothing is typed into a tab that isn't running.

## Review Focus

1. A path with a newline or other control character: must arrive single-quoted, never able to run a command. (Task 1 test.)
2. A host-pane drag onto a tab for a different machine: refused. (Task 1 test for same-machine; manual check.)
3. Text dragged in from another app: refused, not typed. (Task 3 manual check.)
4. A drop on an ended tab: refused. (Task 3 manual check.)
5. A `~` in a dropped path: escaped so the shell doesn't expand it. (Dropped paths are always absolute, so a leading `-` can't occur.) (Task 1 test.)

### Task 1: Core: escaping, payload, same machine

- `public enum DroppedPaths { public static func typedText(for paths: [String]) -> String }` in `Packages/SevenTermCore/Sources/SevenTermCore/Tabs/DroppedPaths.swift`. Safe characters: ASCII letters and digits, `_ - . / , : + @ % = ^`, and any non-ASCII letter or symbol; everything else gets a backslash. Any control character (including newline and tab) makes the whole path single-quoted, with `'` written `'\''`. Returns "" for no paths.
- `public enum RemoteDragPayload { static func make(browserID: UUID, path: String) -> String; static func parse(_ text: String) -> (browserID: UUID, path: String)? }`, format unchanged: `7term-remote:<uuid>:<path>`.
- `extension SSHTarget { public func isSameMachine(as other: SSHTarget) -> Bool }`: host compared ignoring case, user compared ignoring case (nil equals nil only), port nil equals 22; identity file ignored.
- Tests (`DroppedPathsTests.swift`): plain path; space; each special character; leading `~`; Unicode kept; newline and quote single-quoted; several paths; empty list; payload round trip and rejection of other text; same-machine cases.
- Commit `"Terminal drops: path escaping, drag payload, same machine"`.

### Task 2: Reconnect on the tab menu

- `SevenTerm/UI/TabStrip.swift`: `Button("Reconnect") { session.restart() }.disabled(session.state == .running)` above Close Tab, after a divider.
- Build. Commit `"Reconnect on the tab menu"`.

### Task 3: Drops in the terminal

- `SevenTerm/Sessions/DropTerminalView.swift`: `final class DropTerminalView: TerminalView` registering `.fileURL` and `.string`; `var dropText: ((NSPasteboard) -> String?)?`; `draggingEntered`/`draggingUpdated` return `.copy` when `dropText` gives text, else `[]`; `performDragOperation` sends it with `send(txt:)` and takes focus.
- `TerminalSession`: uses `DropTerminalView`; `var remoteTarget: ((UUID) -> SSHTarget?)?` set by `SessionStore`; `func textForDrop(_ pasteboard: NSPasteboard) -> String?` applying the design's rules.
- `FileBrowser` uses `RemoteDragPayload` for `dragPayload(for:)` and `remotePaths(fromDrop:)`.
- `SessionStore.open` sets `session.remoteTarget` to look up the open file browser by id.
- Build. Commit `"Terminal drops: Finder and host-pane paths"`.

### Task 4: Docs

- `docs/user-guide.md`: Reconnect in the tab menu; a "Dropping paths" paragraph under Connecting. Regenerate `help.html` with `tools/build_help.py`.
- Commit `"Terminal drops and tab Reconnect: documentation"`.
