# 3 Term

A small native macOS SSH and SFTP client for a home lab: a list of hosts, one click to connect, tabs, and logging you switch on per session. It opens fast and does a few things well.

3 Term doesn't implement SSH. It runs the system's `/usr/bin/ssh` and `/usr/bin/sftp` in a pseudo-terminal and shows them with [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), so your `~/.ssh/config`, keys, agents, ProxyJump and `known_hosts` all work as they already do.

## Status

Milestones 1 to 3 of 7 are written: tabs, quick connect, a saved host list grouped by tag with a one-time import from `~/.ssh/config`, and per-tab logging. Saved hosts live in `~/Library/Application Support/3 Term/hosts.sqlite`.

| # | Milestone | State |
|---|---|---|
| 1 | Terminal in a window, with tabs | Committed |
| 2 | Saved host list, tags, filter, import from `~/.ssh/config` | Built |
| 3 | Per-tab logging to `~/Documents/3 Term/Logs/`, SHA-256 on close | Written, needs a build |
| 4 | Themes (3 Term red, 6 Bits green, dark, light), global ⌘+ / ⌘- / ⌘0 | |
| 5 | SFTP from the same host entry, hand-off to Transmit or ForkLift | |
| 6 | Credentials: agent, key file, Keychain password behind Touch ID | |
| 7 | JSON backup of hosts and settings to iCloud Drive | |

## Build

Requirements: macOS 14 or later, Xcode 26 or later (SwiftTerm needs Swift 6.2 tools), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open ThreeTerm.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities for the ThreeTerm target, then Run. The Xcode project is generated from `project.yml` and isn't committed; regenerate it after pulling changes that add files.

The app is deliberately not sandboxed: ssh needs your `~/.ssh` folder and agent sockets.

## Logs

Logging is off until you turn it on for a tab (⇧⌘L or the Log button), or tick "Log every session to this host" on a saved host. Each on/off stretch is one segment in `~/Documents/3 Term/Logs/<host>/`:

| File | What it is |
|---|---|
| `<host>_<UTC time>Z_ssh_seg<n>.log` | Raw output bytes, exactly as received. Keystrokes are never logged. |
| `….log.sha256` | SHA-256 of the raw file, computed while it was written |
| `….meta.json` | Host, destination, start (UTC and local offset), end, size, hash, and whether it closed cleanly |
| `….txt` | Readable copy: colors stripped, overwrites applied, full-screen programs replaced by one line |

Verify a log with `shasum -a 256 -c <file>.log.sha256` in its folder. If 3 Term quits without closing a log, the next launch hashes it and marks it `"closedCleanly": false`.

## Tests

The logic without UI lives in a local package, tested with Swift Testing:

```sh
cd Packages/ThreeTermCore
swift test
```

## Layout

```
project.yml                  XcodeGen spec
ThreeTerm/App                App entry, menus, quit confirmation
ThreeTerm/Sessions           Tabs and the ssh process behind each one
ThreeTerm/Hosts              Saved host library, ssh_config import, reachability test
ThreeTerm/UI                 Views and theme
Packages/ThreeTermCore       Parsing, host storage (GRDB), ssh_config scanning, later logging
```

## Keyboard

| Keys | Action |
|---|---|
| ⌘N | New saved host |
| ⌘T | Quick connect |
| Return or double-click | Connect to the selected host |
| ⌘W | Close tab (closes the window when no tabs are open) |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |
| ⇧⌘R | Reconnect an ended session |
| ⇧⌘L | Start or stop logging the current tab |
