# 3 Term

A small native macOS SSH and SFTP client for a home lab: a list of hosts, one click to connect, tabs, and logging you switch on per session. It opens fast and does a few things well.

3 Term doesn't implement SSH. It runs the system's `/usr/bin/ssh` and `/usr/bin/sftp` in a pseudo-terminal and shows them with [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), so your `~/.ssh/config`, keys, agents, ProxyJump and `known_hosts` all work as they already do.

## Status

Milestone 1 of 7: a window with tabs, quick connect (`user@host:port` or an ssh_config alias), and resize handling. No saved hosts yet.

| # | Milestone | State |
|---|---|---|
| 1 | Terminal in a window, with tabs | In progress |
| 2 | Saved host list, tags, filter, import from `~/.ssh/config` | |
| 3 | Per-tab logging to `~/Documents/3 Term/Logs/`, SHA-256 on close | |
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
ThreeTerm/UI                 Views and theme
Packages/ThreeTermCore       Parsing, child environment, later logging
```

## Keyboard

| Keys | Action |
|---|---|
| ⌘T | New connection |
| ⌘W | Close tab (closes the window when no tabs are open) |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |
| ⇧⌘R | Reconnect an ended session |
