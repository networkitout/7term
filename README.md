# 7 Term

[![Latest release](https://img.shields.io/github/v/release/networkitout/7term?label=release)](https://github.com/networkitout/7term/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-informational)
![Apple silicon and Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-informational)
[![MIT License](https://img.shields.io/badge/license-MIT-informational)](LICENSE)

A small, native macOS SSH, SFTP and serial console client: a list of your hosts, one click to connect, tabs, and logging you switch on when you need a record. It opens fast and does a few things well.

<img width="2098" height="1272" alt="image" src="https://github.com/user-attachments/assets/ca5839bc-bb15-4468-a7ca-87e3ffad3e37" />

7 Term doesn't reimplement SSH. It runs the Mac's own OpenSSH, so your `~/.ssh/config`, keys, agents (1Password, Secretive, ssh-agent), ProxyJump and `known_hosts` all work exactly as they already do.

## Download

**[Download the latest release](https://github.com/networkitout/7term/releases/latest)** (`7Term-<version>.dmg`), open it, and drag 7 Term to Applications.

- **Requires** macOS 14 Sonoma or later, on Apple silicon or Intel.
- **Signed and notarized** by Apple, so it opens without security warnings.
- **Updates itself:** 7 Term ▸ Check for Updates…, or let it check automatically. Updates are signed, and a tampered download is refused.

## Features

- **Saved hosts** with tags, a filter, and one-click SSH or SFTP. Imports your `~/.ssh/config` on first run.
- **Tabs** for every session, with reconnect (⇧⌘R) and find in the scrollback (⌘F).
- **File browser:** this Mac and the host side by side, drag and drop, folder copies, a transfer queue, and a SHA-256 for every file copied.
- **Serial consoles:** USB console cables for switches, routers and firewalls, found by name as you plug them in, with Send Break for ROMMON and password recovery.
- **Session logging** you switch on per tab or per host: the raw log, a readable copy, and a SHA-256 written as it records, so you can show a log hasn't been changed.
- **Credentials your way:** your agent and ssh_config, a specific key file, or a password kept in the macOS Keychain and released only after Touch ID.
- **Import** from Royal TSX, SecureCRT, PuTTY/KiTTY, MobaXterm, FileZilla, Ansible inventories, Tabby, or a spreadsheet. Passwords are never imported.
- **iCloud backup** of hosts and settings (never passwords or keys), with restore on a new Mac.
- **Themes:** tactical red, 6 Bits green, Night Red for dark rooms, Dark, Light, or any iTerm2 colour scheme. ⌘+ / ⌘- resizes text in every tab at once.

## Documentation

- **[User guide](docs/user-guide.md):** everything above, step by step. It's also built into the app under **Help ▸ 7 Term Help** (⌘?).
- **[Roadmap](docs/roadmap.md):** what's done, what's next, and what was decided against.

## Security and privacy

- **Your data stays on your Mac.** Hosts and settings are in `~/Library/Application Support/7 Term/`, logs in `~/Documents/7 Term/Logs/`, and passwords in your login Keychain. Nothing is sent anywhere, apart from the update check, which only fetches the release feed from GitHub.
- **Passwords never touch the terminal.** ssh asks 7 Term for a stored password directly (`SSH_ASKPASS`) after Touch ID, so a remote host can't fake a prompt to collect it.
- **Logs record output, never keystrokes**, and each one carries a SHA-256 you can check with `shasum -a 256 -c`.
- **Not sandboxed, on purpose:** ssh needs your `~/.ssh` folder and agent sockets. It uses the hardened runtime and is notarized by Apple.

Found a security problem? Please report it privately; see [SECURITY.md](SECURITY.md).

## Building from source

You don't need to build 7 Term to use it. If you want to:

**Requirements:** macOS 14 or later, Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/networkitout/7term.git
cd 7term
tools/install.sh
```

`tools/install.sh` generates the Xcode project from `project.yml`, builds a Release copy with the pinned dependency versions, and installs it in `/Applications`. Your hosts and settings are kept. Builds without a `DEVELOPMENT_TEAM` in `project.yml` are signed for your Mac only, and update checks are off in them.

To work on it in Xcode instead: `xcodegen generate`, then `open SevenTerm.xcodeproj` and Run. The Xcode project is generated and not committed.

**Tests** cover the logic without UI (SSH targets, host storage, SFTP, serial, logging, imports, backups):

```sh
cd Packages/SevenTermCore && swift test
```

**Releases** are made with `tools/release.sh`; see [docs/releasing.md](docs/releasing.md).

### Layout

```
project.yml                  XcodeGen spec (dependencies pinned in Package.resolved)
SevenTerm/App                App entry, menus, settings
SevenTerm/Sessions           Tabs: ssh, sftp and serial sessions, logging
SevenTerm/Files              File browser (SFTP)
SevenTerm/Serial             Serial port discovery
SevenTerm/Hosts              Saved host directory, reachability test
SevenTerm/Credentials        Keychain passwords and the ssh askpass helper
SevenTerm/UI                 Views, theme, logo, help window
SevenTerm/Updates            Sparkle
Packages/SevenTermCore       Logic and tests: hosts (GRDB), SFTP, serial, imports, logging, backup
tools/                       install.sh, release.sh, icon and help generators
docs/                        User guide, roadmap, serial design, releasing
```

## Contributing

Bug reports and ideas are welcome as [GitHub issues](https://github.com/networkitout/7term/issues). For anything security-related, use the private route in [SECURITY.md](SECURITY.md) instead.

## License and thanks

7 Term is released under the [MIT License](LICENSE).

Built on [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (terminal emulation), [GRDB](https://github.com/groue/GRDB.swift) (SQLite), [Sparkle](https://sparkle-project.org) (updates) and [Yams](https://github.com/jpsim/Yams) (YAML), and on the Mac's own OpenSSH.
