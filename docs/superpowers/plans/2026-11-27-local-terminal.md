# Local Terminal ("This Mac") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A built-in **This Mac** sidebar row and **File ▸ New Local Terminal** (⇧⌘T) that open the user's login shell in a normal 7 Term tab.

**Architecture:** The pure logic (which shell, its environment, the tab label, the sidebar filter match) goes in SevenTermCore with tests. The app adds `TerminalSession.Kind.local`, which starts the shell through the same `LocalProcess` path ssh uses. The sidebar draws the row itself, outside `HostTree` and the database.

**Tech Stack:** Swift 6, SwiftUI/AppKit, SwiftTerm 1.99.2 (`LocalProcess.startProcess(executable:args:environment:execName:currentDirectory:)`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-27-local-terminal-design.md`

## Global Constraints

- Branch `claude/serene-cannon-9ltlq7`, draft PR networkitout/7term#9.
- Core tests: `cd Packages/SevenTermCore && swift test` (on the Mac, prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). The app target only builds on macOS: `xcodegen generate && xcodebuild -scheme SevenTerm -configuration Debug CODE_SIGNING_ALLOWED=NO build`, expecting `BUILD SUCCEEDED`.
- Copy, exactly: row title `This Mac`; row subtitle `Local terminal (<shell name>)`; menu `New Local Terminal` (⇧⌘T); settings `Show This Mac in the sidebar` (default on), `Log local terminals by default` (default off).
- The shell's environment comes only from `ChildEnvironment.makeLocal`. `DYLD_*`, `AWS_*` and any other parent variable outside the allowlist never reach it.
- Nothing about This Mac is written to the hosts database, backups, or imports.
- No tab opens at launch.

## Review Focus

1. `pw_shell` is empty, relative, or not executable (for example a removed Homebrew bash): fall back to `/bin/zsh`, don't fail to start. (Task 1 tests.)
2. The app was started from Finder, so its cwd is `/` and `PATH` is minimal: the shell must still start in `$HOME` with a login `PATH`. (Task 2 checklist.)
3. The shell sets a window title (oh-my-zsh, starship): the tab keeps saying `This Mac`. (Task 1 test.)
4. Dragging a row from a file browser's host pane onto a local tab must type nothing. A server path means nothing locally. (Task 2, `textForDrop` guard.)
5. An empty host list: the "No Saved Hosts" overlay must not cover the This Mac row. (Task 3 checklist.)

---

### Task 0: Core builds on Linux again (prerequisite)

On Linux, `swift test` fails today with `AskPassCaller.swift:1:8: error: no such module 'Darwin'`. `ProcessAncestry` uses libproc (`proc_pidpath`, `proc_pidinfo`), which only exists on macOS. `docs/serial.md` says the core tests run in the Linux container, and the serial code already guards Darwin-only calls with `#if canImport(Darwin)`.

**Files:** Modify `Packages/SevenTermCore/Sources/SevenTermCore/AskPassCaller.swift`.

- [ ] **Step 1: Guard the libproc code.** Guard `import Darwin` and the bodies of `ProcessAncestry.executablePath(of:)` and `parent(of:)` with `#if canImport(Darwin)`. In the `#else` branch, `return nil`. That fails closed: no path and no parent means `currentProcessIsTrusted()` and `parentIsSSH()` are false. Nothing changes on macOS.
- [ ] **Step 2: Run `swift test` on Linux.** Every existing test passes. That's the baseline.
- [ ] **Step 3: Commit** `"Core: build and test on Linux again (libproc is macOS-only)"`.

### Task 1: Core logic

**Files:**
- Create: `Packages/SevenTermCore/Sources/SevenTermCore/Local/LocalShell.swift`
- Modify: `Packages/SevenTermCore/Sources/SevenTermCore/ChildEnvironment.swift`
- Modify: `Packages/SevenTermCore/Sources/SevenTermCore/Tabs/TabLabel.swift`
- Test: `Packages/SevenTermCore/Tests/SevenTermCoreTests/LocalShellTests.swift`, `TabLabelTests.swift`

**Interfaces (produces):**
- `public struct LocalShell: Equatable, Sendable { public let path: String }`
  - `public static let fallbackPath = "/bin/zsh"`
  - `public static func resolve(passwdShell: String?, isExecutable: (String) -> Bool) -> LocalShell`. Uses `passwdShell` when it is non-empty, starts with `/`, and `isExecutable` says yes; otherwise `fallbackPath`.
  - `public static func current() -> LocalShell`: `getpwuid(getuid())?.pointee.pw_shell` with `FileManager.default.isExecutableFile(atPath:)`.
  - `public var name: String`: last path component (`"zsh"`).
  - `public var loginArgv0: String`: `"-" + name`.
- `public enum LocalTerminal`, in the same file:
  - `public static let title = "This Mac"`, `public static let sidebarID = "builtin.this-mac"`
  - `public static func subtitle(shellName: String) -> String`: `"Local terminal (\(shellName))"`
  - `public static func matches(query: String, shellName: String) -> Bool`: true for an empty or whitespace-only query, otherwise a case-insensitive `contains` against the title, `"local"`, and `shellName`.
  - `public static func machineName(hostName: String) -> String`: the part before the first `"."`, or `"localhost"` if that's empty.
- `ChildEnvironment.makeLocal(from parent: [String: String], shell: String) -> [String]`: `make(from:)` plus `SHELL=<shell>` and `TERM_PROGRAM=7Term`, in the same sorted `KEY=value` form.
- `TabLabel.Kind.local`. `defaultTitle` returns `base` with no suffix, and `remoteTitle` is never used for `.local`.

- [ ] **Step 1: Write the failing tests**

`LocalShellTests`:
- `resolve(passwdShell: "/opt/homebrew/bin/fish", isExecutable: { _ in true }).path == "/opt/homebrew/bin/fish"`
- each of `nil`, `""`, `"fish"` and `"/gone/bash"` with `isExecutable: { $0 != "/gone/bash" }` gives `.path == "/bin/zsh"`
- `LocalShell(path: "/bin/zsh").loginArgv0 == "-zsh"`, `.name == "zsh"`
- `LocalTerminal.subtitle(shellName: "zsh") == "Local terminal (zsh)"`
- `matches`: `""`, `"  "`, `"mac"`, `"LOCAL"`, `"zs"` → true; `"core-sw"` → false
- `machineName(hostName: "mbp.lan") == "mbp"`, `machineName(hostName: "") == "localhost"`
- `makeLocal(from: ["HOME": "/Users/a", "DYLD_INSERT_LIBRARIES": "x", "AWS_SECRET_ACCESS_KEY": "y"], shell: "/bin/zsh")` contains `"SHELL=/bin/zsh"`, `"TERM_PROGRAM=7Term"`, `"HOME=/Users/a"`, `"PATH=/usr/bin:/bin:/usr/sbin:/sbin"`, and nothing with the prefix `DYLD_` or `AWS_`.

`TabLabelTests`:
- `TabLabel(kind: .local, savedName: "This Mac", remoteTitle: "vim ~/x", destination: "mbp").title == "This Mac"`

- [ ] **Step 2: Run `swift test`.** It should fail to compile (`LocalShell`, `makeLocal` and `.local` are undefined).
- [ ] **Step 3: Implement the interfaces above.**
- [ ] **Step 4: Run `swift test`.** Everything passes, old tests included.
- [ ] **Step 5: Commit** `"Local terminal: shell, environment and label rules"`.

### Task 2: Local sessions in the app

**Files:**
- Modify: `SevenTerm/Sessions/TerminalSession.swift`, `SevenTerm/Sessions/SessionStore.swift`, `SevenTerm/App/SevenTermApp.swift`, `SevenTerm/UI/TabStrip.swift`
- Create: `SevenTerm/App/LocalTerminalSettings.swift`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces:
  - `enum LocalTerminalSettings { static let showInSidebarKey = "localTerminal.showInSidebar"; static let logByDefaultKey = "localTerminal.logByDefault"; static var logByDefault: Bool }`, read from `UserDefaults.standard`.
  - `SessionStore.openLocal()`
  - `TerminalSession.isLocal: Bool`

- [ ] **Step 1: `TerminalSession`.**
  - Add `case local` to `Kind`, with `arguments(for:)` returning `[]`.
  - In `start()`, a `.local` branch builds the environment with `ChildEnvironment.makeLocal(from: ProcessInfo.processInfo.environment, shell: shell.path)` and calls `process.startProcess(executable: shell.path, args: [], environment:, execName: shell.loginArgv0, currentDirectory: NSHomeDirectory())`. The note reads `starting <shell.name> on this Mac…`. There's no keychain, no ConnectTimeout, and no ssh arguments.
  - When a local session ends, `terminated` shows `[shell exited, exit N · ⇧⌘R for a new shell]`, and `restart()` shows `[new shell]`.
  - `textForDrop(fileURLs:strings:)` accepts `.local` for file URLs only and returns nil for host-pane rows.
  - `startLogging` passes `host: target.host` for `.local`, so logs are named after the Mac, not after "This Mac".
- [ ] **Step 2: `SessionStore.openLocal()`.** It opens `TerminalSession(kind: .local, target: SSHTarget(host: LocalTerminal.machineName(hostName: ProcessInfo.processInfo.hostName)), name: LocalTerminal.title, logByDefault: LocalTerminalSettings.logByDefault, appearance:)`, then sets up `didAcceptDrop`, appends, selects and starts it the same way `open(_:kind:…)` does. Put the shared tail of the two in a private helper rather than copying it.
- [ ] **Step 3: Menus.**
  - Add File ▸ `New Local Terminal` (⇧⌘T) after Quick Connect.
  - Session ▸ Reconnect, and the tab context menu's Reconnect, read `Restart Shell` when the session is local.
- [ ] **Step 4: Build the app.** Expect `BUILD SUCCEEDED`. Then check by hand on the Mac (checklist below, items 1 to 4).
- [ ] **Step 5: Commit** `"Local terminal: sessions"`.

### Task 3: Sidebar row and Settings ▸ General

**Files:**
- Modify: `SevenTerm/UI/HostSidebar.swift`, `SevenTerm/App/SevenTermApp.swift`
- Create: `SevenTerm/UI/GeneralSettings.swift`

**Interfaces:** Consumes `LocalTerminal`, `LocalShell.current()`, `LocalTerminalSettings`, `SessionStore.openLocal()`.

- [ ] **Step 1: `ThisMacRow`.**
  - It's a private view in `HostSidebar.swift`: SF Symbol `desktopcomputer` in `chrome.accent`, the title in `Brand.mono(13, weight: .medium)`, the subtitle in `Brand.mono(10.5)` secondary, and a hover `OPEN` button styled like `HostRow`'s. There's no gear and it isn't draggable.
  - It's tagged `LocalTerminal.sidebarID` and placed first in the `List`, followed by a `Divider()`. It's shown when `@AppStorage(LocalTerminalSettings.showInSidebarKey) = true` and `LocalTerminal.matches(query: hosts.query, shellName:)` holds, and it's hidden while a tag filter is set.
- [ ] **Step 2: Actions.**
  - In `primaryAction`, `LocalTerminal.sidebarID` calls `sessions.openLocal()`.
  - In `contextMenu`, that id gets `Open Local Terminal` and `Hide This Mac` (which sets the setting to false). It must not reach the host or folder branches.
  - Move `emptyState` down (for example with top padding) so it doesn't cover the row when the row is visible.
- [ ] **Step 3: Settings.** `GeneralSettings` is a grouped `Form` with the two toggles bound through `@AppStorage`, plus a footer: `This Mac opens your login shell in your home folder. Hidden, it's still in File ▸ New Local Terminal (⇧⌘T).` Add it as the first `Settings` tab, `Label("General", systemImage: "gearshape")`.
- [ ] **Step 4: Build.** Check by hand (checklist items 5 to 8).
- [ ] **Step 5: Commit** `"Local terminal: This Mac in the sidebar, Settings ▸ General"`.

### Task 4: Docs, What's New, housekeeping

- [ ] **Step 1:**
  - Add `.anchor/` to `.gitignore` and commit it on its own: `"Ignore .anchor/ (plugin session state)"`.
- [ ] **Step 2:**
  - `SevenTerm/Resources/WhatsNew.json`: add a `"1.7.0"` entry, title `This Mac`, detail `A local terminal is now at the top of the host list: double-click This Mac, or choose File ▸ New Local Terminal (⇧⌘T). It has tabs, find and logging like any session. Hide it in Settings ▸ General.`
  - `docs/user-guide.md`: add a `### This Mac (local terminal)` section under Connecting, and a ⇧⌘T row in Keyboard shortcuts.
  - `SevenTerm/Resources/Help/help.html`: the same two additions.
  - `docs/roadmap.md`: add milestone row 15 `Local terminal (This Mac) ([design](superpowers/specs/2026-11-27-local-terminal-design.md))` and mark it Done.
- [ ] **Step 3: Check the JSON.** `python3 -m json.tool SevenTerm/Resources/WhatsNew.json` must succeed. No test reads the bundled file. Run `swift test`, which should still pass.
- [ ] **Step 4: Commit** `"Local terminal: documentation and What's New"`, then push.

## Manual checklist (on the Mac, after Tasks 2 and 3)

1. Start 7 Term from Finder. Open File ▸ New Local Terminal. `pwd` prints `$HOME`, `echo $0` prints `-zsh`, and `which brew` finds Homebrew if it's installed.
2. `env | grep -E '^(DYLD|AWS)_'` prints nothing, and `echo $TERM_PROGRAM` prints `7Term`.
3. `exit`. The tab shows the exit line, Session ▸ reads `Restart Shell`, ⇧⌘R starts a new shell in the same tab, and the tab still says `This Mac`.
4. Start logging, run `ls`, stop. The log in `~/Documents/7 Term/Logs/` is named after the Mac's short host name, and `shasum -a 256 -c` passes.
5. The This Mac row is first, with the subtitle `Local terminal (zsh)`. Double-click and Return both open a tab, and right-click shows only the two local actions.
6. Typing `prod` in the filter hides the row, `mac` shows it, and choosing a tag hides it.
7. Settings ▸ General: turning off "Show This Mac" hides the row while ⇧⌘T still works. "Log local terminals by default" starts logging on new local tabs.
8. With no saved hosts, the "No Saved Hosts" overlay sits below the row and doesn't cover it.
