# 7 Term

<img width="2098" height="1272" alt="image" src="https://github.com/user-attachments/assets/ca5839bc-bb15-4468-a7ca-87e3ffad3e37" />


A small native macOS SSH and SFTP client for a home lab: a list of hosts, one click to connect, tabs, and logging you switch on per session. It opens fast and does a few things well.

7 Term doesn't implement SSH. It runs the system's `/usr/bin/ssh` and `/usr/bin/sftp` in a pseudo-terminal and shows them with [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), so your `~/.ssh/config`, keys, agents, ProxyJump and `known_hosts` all work as they already do.

**[User guide](docs/user-guide.md)**: how to use 7 Term.

## Status

Milestones 1 to 9 are built and in use. Saved hosts live in `~/Library/Application Support/7 Term/hosts.sqlite`.

| # | Milestone | State |
|---|---|---|
| 1 | Terminal in a window, with tabs | Done |
| 2 | Saved host list, tags, filter, import from `~/.ssh/config` | Done |
| 3 | Per-tab logging to `~/Documents/7 Term/Logs/`, SHA-256 on close | Done |
| 4 | Themes (7 Term, 6 Bits, Night Red, Dark, Light, .itermcolors import), global ⌘+ / ⌘- / ⌘0 | Done |
| 5 | SFTP prompt from the same host entry, hand-off to Transmit or ForkLift | Done |
| 6 | Credentials: agent, key file, Keychain password behind Touch ID | Done |
| 7 | JSON backup of hosts and settings to iCloud Drive | Done |
| 8 | File browser: local and remote panes, drag and drop, transfer queue with SHA-256 | Done |
| 9 | Import hosts from a spreadsheet (pasted cells or CSV) | Done |

## Plan: 1.0 for other people

In this order. Milestones 10 to 12 are done.

| # | Milestone | Notes |
|---|---|---|
| 10 | Find in the terminal (⌘F, ⌘G, ⇧⌘G) | Done |
| 11 | Serial console ([design](docs/serial.md)) | Done. Tested with a Flipper Zero; Send Break still to try on network gear |
| 12 | Import from other tools | Done: Royal TSX, SecureCRT, PuTTY/KiTTY, MobaXterm, FileZilla, Ansible inventory (INI/YAML), Tabby. Royal TSX checked against a real document |
| 13 | Release | Built: MIT license, Sparkle updates, `tools/release.sh` (Developer ID signing, notarization, signed DMG, appcast, GitHub release). Needs the one-time setup in [docs/releasing.md](docs/releasing.md) |

Decided against: keepalives on by default (left to ssh_config), RDP/VNC, sync between Macs, Mosh, a built-in key generator.

Also worth considering: port forwards saved with a host, a colour per host (prod vs lab), Option as Meta.

## Backlog

Nice to have, not planned:

- Pull hosts from Proxmox: an API token kept in the Keychain lists VMs and containers with their IPs (from the guest agent), tags them by node and pool, and keeps the list in sync. Read-only token. Likely its own milestone after 1.0.

- Resume interrupted transfers: keep the partial file when the connection drops, check the source hasn't changed (size and modified time), continue from the partial size and re-hash the part already copied. Retry button on failed transfers.
- Drag from the remote pane straight into Finder (file promises).
- Drop onto a folder row instead of into the folder that's open.

## Install on your Mac

```
tools/install.sh
```

Builds a Release copy and puts it in `/Applications`, replacing any older copy and reopening it. Xcode has to be installed but doesn't need to be open. Run it again after pulling changes to update. Your hosts, settings and logs are kept: they don't live in the app.

Until releases are signed with a Developer ID (milestone 13), each build is signed only for this Mac. macOS may ask once per new build whether 7 Term can use a saved Keychain password; choose **Always Allow**.

## Build

Requirements: macOS 14 or later, Xcode 26 or later (SwiftTerm needs Swift 6.2 tools), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open SevenTerm.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities for the SevenTerm target, then Run. The Xcode project is generated from `project.yml` and isn't committed; regenerate it after pulling changes that add files.

The app is deliberately not sandboxed: ssh needs your `~/.ssh` folder and agent sockets.

## Logs

Logging is off until you turn it on for a tab (⇧⌘L or the Log button), or tick "Log every session to this host" on a saved host. Each on/off stretch is one segment in `~/Documents/7 Term/Logs/<host>/`:

| File | What it is |
|---|---|
| `<host>_<UTC time>Z_ssh_seg<n>.log` | Raw output bytes, exactly as received. Keystrokes are never logged. |
| `….log.sha256` | SHA-256 of the raw file, computed while it was written |
| `….meta.json` | Host, destination, start (UTC and local offset), end, size, hash, and whether it closed cleanly |
| `….txt` | Readable copy: colors stripped, overwrites applied, full-screen programs replaced by one line |

Verify a log with `shasum -a 256 -c <file>.log.sha256` in its folder. If 7 Term quits without closing a log, the next launch hashes it and marks it `"closedCleanly": false`.

## Credentials

Each saved host picks how it signs in (Edit Host ▸ Authentication):

| Method | What 7 Term does |
|---|---|
| Agent / ssh_config (default) | Nothing extra. ssh uses your agent (1Password, Secretive, ssh-agent) and `~/.ssh/config`, then asks in the terminal. |
| Key file | Adds `-i <key> -o IdentitiesOnly=yes`. |
| Password in Keychain | Stores the password in your login Keychain. On connect, ssh asks 7 Term for it through `SSH_ASKPASS`; 7 Term requires Touch ID (or your Mac password) and hands it straight to ssh. It is never typed into the terminal, so a remote host can't fake a prompt to collect it. |

For password hosts, ssh's other questions (an unknown host key, a one-time code, a key passphrase) appear as native dialogs showing ssh's exact text. 7 Term's own binary is the helper, so there is nothing extra to install or sign.

## Appearance

**Settings… (⌘,)** picks the theme, font and size; **View ▸ Theme** switches themes from the menu. Size changes apply to every tab at once. Built-in themes: 7 Term (default), 6 Bits green, Night Red (all text dim red, for a dark room), Dark and Light. Any iTerm2 `.itermcolors` scheme can be imported; imported themes are kept in `~/Library/Application Support/7 Term/Themes/`.

The look follows 6 Bits in tactical red: a dot-matrix "7" logo (SSH is a layer 7 protocol), monospaced type, and red `#FF3434` on red-tinted black. The app icon is generated by `tools/make_icon.py`; rerun it after changing the glyph or colors:

```sh
python3 tools/make_icon.py SevenTerm/Resources/Assets.xcassets/AppIcon.appiconset
```

## Tests

The logic without UI lives in a local package, tested with Swift Testing:

```sh
cd Packages/SevenTermCore
swift test
```

## Layout

```
project.yml                  XcodeGen spec
SevenTerm/App                App entry, menus, quit confirmation
SevenTerm/Sessions           Tabs and the ssh process behind each one
SevenTerm/Hosts              Saved host library, ssh_config import, reachability test
SevenTerm/UI                 Views, theme, logo
SevenTerm/Resources          App icon
tools/make_icon.py           Generates the app icon
Packages/SevenTermCore       Parsing, host storage (GRDB), ssh_config scanning, logging
```

## Keyboard

| Keys | Action |
|---|---|
| ⌘N | New saved host |
| ⌘T | Quick connect |
| Return, double-click or ⌘↩ | Connect to the selected host with ssh |
| ⌥⌘↩ | Browse files on the selected host (SFTP) |
| ⇧⌘I | Import hosts from a spreadsheet or another app |
| ⌘E / ⌘D / ⌘⌫ | Edit, duplicate or delete the selected host |
| ⌘W | Close tab (closes the window when no tabs are open) |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |
| ⇧⌘R | Reconnect an ended session |
| ⇧⌘L | Start or stop logging the current tab |
| ⌘F / ⌘G / ⇧⌘G | Find, find next, find previous in the terminal |
| ⌘+ (or ⌘=) / ⌘- / ⌘0 | Bigger, smaller, default text size in every tab |
| ⌘, | Settings: theme, font, size |
