# Dropping paths into terminal tabs, and Reconnect on the tab menu: design

Status: approved in conversation (2026-11-23).

## Why

A friend asked for Terminal.app's habit: type `cd `, drag a folder in from Finder, and the path appears. In 7 Term almost every tab is a shell on a server, so a Mac path alone rarely helps; the user chose both kinds of drop. Separately, Reconnect (⇧⌘R) should also be reachable from a tab's right-click menu.

## Behaviour

**Reconnect on the tab menu (user's request).** Right-clicking a tab offers **Reconnect**, greyed out while that tab is connected, exactly like **Session ▸ Reconnect** but for the tab clicked. Name, colour and logging behave as they do with ⇧⌘R.

**Drops into a terminal tab (user's choice: both kinds).** A drop types text at the prompt, as if pasted; it never presses Return.

- **From Finder** (or the file browser's Mac pane): the Mac path of each item.
- **From the file browser's host pane**: the server path of each item, but only onto a tab connected to the same machine (same host, user and port; the key file doesn't matter). Onto any other tab the drop is refused, since that path means nothing there.
- Several items give several paths, separated by spaces. A space follows the last one, ready for the next word.
- Paths are escaped for a shell the way Terminal does: a backslash before spaces and characters a shell treats specially (`My Folder` → `My\ Folder`, a leading `~` included). A drop that includes a name with a control character (a hidden line break, ^U, an escape) is refused: typed into a terminal those act as they arrive, whatever the quoting, so such a name could run a command. (Changed after review; the first version single-quoted them.) The same quoting works at the `sftp>` prompt.
- Accepted on ssh and `sftp>` tabs while connected. Refused on serial consoles (their devices aren't shells), on file browser tabs, and on tabs that have ended.

All of these are Claude's calls within the user's choice, except where marked.

## Approaches

1. **Subclass SwiftTerm's `TerminalView` as a drop target (chosen).** It is an open `NSView`, has no drag handling of its own, and already has `pasteText(_:)`, meant for exactly this: it goes through the session like typing, uses bracketed paste when the remote side asks, and scrolls to the prompt. Small and local.
2. A SwiftUI `dropDestination` over the terminal. Rejected: the terminal is an AppKit view inside a representable, where SwiftUI drop targets and AppKit's first responder fight.
3. Changing SwiftTerm itself. Rejected: a fork to maintain for a few lines.

## Where it lands

- Core, tested: path escaping (`DroppedPaths`), the host-pane drag payload format (`RemoteDragPayload`, moved out of `FileBrowser` so both ends share it), and "same machine" for two `SSHTarget`s.
- App: `DropTerminalView`, `TerminalSession` deciding what a drop types, `SessionStore` resolving a dragged row's browser to its host, the tab menu item, the user guide and help page.
