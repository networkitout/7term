# 7 Term roadmap

How 7 Term was built, and what might come next. Ideas and requests are welcome as GitHub issues.

## Milestones

All 13 milestones are done; 1.2.0 is the first public release.

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

### Toward the first public release

| # | Milestone | Notes |
|---|---|---|
| 10 | Find in the terminal (⌘F, ⌘G, ⇧⌘G) | Done |
| 11 | Serial console ([design](serial.md)) | Done. Tested with a Flipper Zero; Send Break still to try on network gear |
| 12 | Import from other tools | Done: Royal TSX, SecureCRT, PuTTY/KiTTY, MobaXterm, FileZilla, Ansible inventory (INI/YAML), Tabby. Royal TSX checked against a real document |
| 13 | Release | Done: MIT license, Sparkle updates, `tools/release.sh` (Developer ID signing, notarization, signed DMG, appcast, GitHub release). See [releasing.md](releasing.md) |

### Decided against

 keepalives on by default (left to ssh_config), RDP/VNC, sync between Macs, Mosh, a built-in key generator.

### Worth considering

 port forwards saved with a host, a colour per host (prod vs lab), Option as Meta.

## Backlog

Nice to have, not planned:

- Pull hosts from Proxmox: an API token kept in the Keychain lists VMs and containers with their IPs (from the guest agent), tags them by node and pool, and keeps the list in sync. Read-only token. Likely its own milestone after 1.0.

- Resume interrupted transfers: keep the partial file when the connection drops, check the source hasn't changed (size and modified time), continue from the partial size and re-hash the part already copied. Retry button on failed transfers.
- Drag from the remote pane straight into Finder (file promises).
- Drop onto a folder row instead of into the folder that's open.
