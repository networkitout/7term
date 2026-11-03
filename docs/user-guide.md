# 7 Term User Guide

7 Term is a small Mac app for connecting to the machines you manage: a list of saved hosts, one click to open a terminal or a file browser, tabs, and logging you switch on when you need a record.

It uses the Mac's own OpenSSH (`/usr/bin/ssh`). Anything you've set up for ssh already works: `~/.ssh/config`, keys, agents such as 1Password or Secretive, ProxyJump, and `known_hosts`.

- [Getting started](#getting-started)
- [Saved hosts](#saved-hosts)
- [Connecting](#connecting)
- [Serial consoles](#serial-consoles)
- [Signing in](#signing-in)
- [Copying files](#copying-files)
- [Logging sessions](#logging-sessions)
- [Finding text](#finding-text)
- [Appearance](#appearance)
- [Backup and restore](#backup-and-restore)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Troubleshooting](#troubleshooting)

## Getting started

The first time 7 Term opens, it offers to import the hosts in your `~/.ssh/config`. Choose the ones you want, optionally give them a tag, or skip. You can run the import again later from **File ▸ Import from ~/.ssh/config…**.

The window has two parts: your saved hosts on the left, and tabs on the right. With no tabs open, the right side shows **Quick Connect…**.

## Saved hosts

### Adding and editing

- **New host:** ⌘N, or the **+** button above the list.
- **Edit:** click the **gear** at the end of a host's row, select it and press ⌘E, or right-click ▸ **Edit…**.

The host form has two columns:

| Field | What to enter |
|---|---|
| Name | What the list shows. Defaults to the host. |
| Host | An IP address, a DNS name, or an alias from `~/.ssh/config`. |
| Port | Leave empty for 22, or whatever your ssh_config says. |
| User | Leave empty to use your ssh_config or your Mac username. |
| Tags | Comma-separated, for example `proxmox, lab`. |
| Log every session | Starts logging automatically each time this host opens. |
| Sign in with | See [Signing in](#signing-in). |

The line under the left column shows the exact ssh command 7 Term will run. **Test Reachability** checks that the port accepts a connection without logging in.

### Finding hosts

- Type in **Filter hosts** to search names, addresses, users and tags.
- The menu at the bottom of the list shows only hosts with one tag.
- Each host appears once, whatever its tags. Its first three tags show under its name.

### Other actions (right-click a host)

**Duplicate**, **Copy Hostname**, and **Delete…**. Deleting removes the host from 7 Term only. Your `~/.ssh/config` and any open tabs aren't touched, and its stored password is removed from the Keychain.

### Importing many hosts at once

**File ▸ Import from Spreadsheet…** (⇧⌘I):

1. In Excel or Numbers, select the cells (including a header row if you have one) and copy them. Then click **Paste Rows**. Or click **Open CSV…**, or drop a CSV file onto the sheet.
2. Check the column guesses. Each column has a menu (Name, Host, Port, User, Tags, Key file, Ignore). A header row such as `Name, IP, Port, User, Tags` is matched automatically.
3. Check the rows: **+** is new, the circular arrows mean already saved, and **✕** shows why a row can't be imported.
4. Optionally add a tag to every host, and choose whether hosts you already have should be updated (new details filled in, tags added) or skipped.
5. Click **Import**.

Good to know:
- Tags in one cell can be separated by `;`, `,` or `|`.
- A host cell like `admin@10.0.0.9:2022` fills in the user and port too.
- Columns that look like passwords are shown as locked and never read. 7 Term doesn't import passwords from anywhere.

## Connecting

- **Open a terminal:** double-click a host, press Return, or hover and click **SSH**.
- **Browse files:** hover and click **SFTP**, or press ⌥⌘Return. See [Copying files](#copying-files).
- **Any host, without saving it:** ⌘T for **Quick Connect**. Type `host`, `user@host` or `user@host:port`. Aliases from ssh_config work too. Click **Connect** for a terminal or **SFTP** for the file browser.

Each connection opens in a tab. ⇧⌘] and ⇧⌘[ move between tabs, and ⌘W closes the current one.

The dot on a tab is green while connected and grey after the session ends. When a session ends, press ⇧⌘R to reconnect in the same tab. If nothing answers, 7 Term gives up after 15 seconds and says so, rather than waiting in silence.

**Right-click a host** for more options: **SFTP Prompt** opens the classic `sftp>` command line, and **Open in Transmit/ForkLift** appears if one of those apps is installed.

## Serial consoles

7 Term opens USB console cables (switches, routers, firewalls, a Raspberry Pi, a Flipper Zero) in a tab, with the same logging, search, themes and text size as ssh.

**Quick look:** ⌘T, switch to **Serial**, pick the port and speed, and click **Open**. Adapters appear in the list as soon as you plug them in, by name (for example "FTDI FT232R USB UART").

**Save one:** ⌘N, switch the form to **Serial**, and choose:

| Setting | Usually |
|---|---|
| Port | Your adapter. One that isn't plugged in shows as "(not connected)". |
| Speed | 9600 for Cisco, Juniper, Aruba and most network gear; 115200 for a Raspberry Pi |
| Data bits, Parity, Stop bits | 8, None, 1 (written "8N1") |
| Flow control | None |

Saved consoles show their port and settings in the list (`usbserial-A10K · 9600 8N1`). Double-click one, or hover and click **OPEN**.

7 Term also remembers which adapter you chose. If macOS gives it a different name later (some cables are named after the USB socket they're plugged into), the saved console still finds it.

**Send Break:** **Session ▸ Send Break** (⌘B) holds the line in the break state for 300 ms, which a Cisco device needs to enter ROMMON or password recovery. Logging notes each break.

**Unplugging:** the tab says the port isn't connected. Plug the cable back in and press ⇧⌘R.

**Drivers:** FTDI and CH340 cables work without installing anything. Prolific (PL2303) and Silicon Labs (CP210x) adapters may need the maker's driver: check **System Information ▸ USB** to see which chip yours has. Cisco's own mini-USB console port needs Cisco's driver; its RJ45 console port with a USB cable doesn't.

## Signing in

Choose how each host signs in under **Sign in with** in the host form.

**Agent / ssh_config** (the default)
ssh works as it does in Terminal: your agent, then the keys and settings in `~/.ssh/config`, then a password prompt in the terminal if all else fails.

**Key file**
Choose a private key (not the `.pub` file). Only that key is offered to the server, which avoids "too many authentication failures" when your agent holds many keys. If the key has a passphrase, 7 Term asks for it in a dialog.

**Password in Keychain**
Type the password once; it's saved in your login Keychain. Each time 7 Term connects, it asks for **Touch ID** (or your Mac password) and hands the password to ssh directly. The password never appears in the terminal, the host list, backups or logs. That also means a server can't trick you into typing it with a fake prompt. A wrong stored password fails after one try instead of asking again and again. Edit the host to replace it.

**Other prompts.** When ssh needs an answer, 7 Term shows it in a dialog with ssh's exact wording. This happens in the file browser, and for hosts set to use the Keychain. It covers a new host key (only **Continue** accepts it), a one-time code, or a key passphrase. In ordinary terminal tabs these prompts appear in the terminal as usual.

## Copying files

The file browser tab (**SFTP** on a host) shows **this Mac** on the left and the **host** on the right, with a list of transfers underneath.

**Browsing**
- Double-click a folder to open it, or press the up arrow to go to the enclosing folder.
- Type a path into the bar at the top of a pane and press Return.
- The eye button shows or hides dotfiles. Click a column heading to sort.

**Copying**
- **Drag** files or folders from one pane to the other. You can also drag from Finder onto the host pane.
- Or select items and click **Upload →** or **← Download**.
- Double-clicking a file on the host downloads it into the folder shown on the left.
- Folders are copied with everything inside them. Symbolic links are skipped.

**Transfers**
- Transfers run one after another. Each shows progress and can be cancelled.
- If a file already exists at the destination, 7 Term asks: **Replace**, **Skip** or **Stop**. Tick "Do this for the rest" to answer once for the whole batch.
- A file is copied under a hidden temporary name and renamed only when complete. A cancelled or failed copy never leaves a half-written file behind, and never damages the file it was replacing.
- Each finished transfer shows its **SHA-256**. Click it to copy the full hash.
- File permissions and modified dates are kept.

**Other file actions (right-click)**
New Folder, Rename, Copy Path, Show in Finder (this Mac), Delete. Deleting on this Mac moves items to the Trash. Deleting on the host is permanent, and 7 Term says so before doing it.

## Logging sessions

Logging records everything a tab shows, so you have a record of what happened.

- **Start or stop:** ⇧⌘L, or the **Log** button at the right of the tab bar. A tab that's logging shows **REC**.
- **Always on for a host:** turn on **Log every session** in the host form.
- **Where logs go:** `~/Documents/7 Term/Logs/`, in a folder per host. **Session ▸ Show Log in Finder** takes you there.

Each stretch of logging (from start to stop) produces:

| File | What it is |
|---|---|
| `.log` | The raw session, byte for byte, including terminal control codes |
| `.txt` | A readable copy without control codes. Full-screen programs such as `vim` or `top` are left out. |
| `.log.sha256` | The SHA-256 of the `.log` file |
| `.meta.json` | Host, start and end times (UTC, with your time zone offset), size and hash |

To check that a log hasn't changed since it was written, go to its folder in Terminal and run `shasum -a 256 -c <name>.log.sha256`.

Existing logs are never overwritten. If 7 Term quits unexpectedly while logging, it finishes the open log the next time it starts.

In a file browser tab, logging records each connection, transfer and remote delete, with paths, sizes and SHA-256 hashes.

## Finding text

In a terminal tab, press **⌘F** to search the screen and scrollback. ⌘G finds the next match, ⇧⌘G the previous one. **Edit ▸ Find ▸ Use Selection for Find** searches for the selected text.

## Appearance

**Text size** applies to every tab at once:
- ⌘+ or ⌘= makes text bigger.
- ⌘- makes it smaller.
- ⌘0 resets it.

**Themes:** **View ▸ Theme**, or **Settings ▸ Appearance** (⌘,).

| Theme | Look |
|---|---|
| 7 Term | Red on near-black (the default) |
| 6 Bits | Green on near-black. The whole app turns green, including the Dock icon. |
| Night Red | Dim red, kind to dark-adapted eyes |
| Dark, Light | Plain |

You can also **import an iTerm2 colour scheme** (`.itermcolors`) in Settings ▸ Appearance, and choose any monospaced font there.

## Backup and restore

7 Term can keep a copy of your hosts and settings in iCloud Drive, under `iCloud Drive/7 Term/`. Turn it on in **Settings ▸ Backup**.

- It saves a couple of seconds after any change, and keeps a dated copy per day for 30 days in `History/`.
- **Included:** hosts, tags, key file paths, theme, font and text size.
- **Never included:** passwords, private keys and session logs.

**To restore** (after a reinstall, or on another Mac):
1. Choose **File ▸ Restore from Backup…** and pick `7term-backup.json` or one of the dated copies.
2. 7 Term adds the hosts you don't already have and applies the saved theme and text size. Hosts already in 7 Term aren't changed.
3. Hosts that used **Password in Keychain** need their passwords entered again.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| ⌘N | New host |
| ⌘T | Quick Connect |
| Return, double-click, ⌘Return | Open a terminal to the selected host |
| ⌥⌘Return | Browse files on the selected host |
| ⌘E / ⌘D / ⌘Delete | Edit / duplicate / delete the selected host |
| ⇧⌘I | Import hosts from a spreadsheet |
| ⌘W | Close tab (closes the window when no tabs are open) |
| ⇧⌘] / ⇧⌘[ | Next / previous tab |
| ⇧⌘R | Reconnect an ended session |
| ⇧⌘L | Start or stop logging the current tab |
| ⌘F / ⌘G / ⇧⌘G | Find / next / previous in the terminal |
| ⌘B | Send Break (serial consoles) |
| ⌘+ (⌘=) / ⌘- / ⌘0 | Bigger / smaller / default text size |
| ⌘, | Settings |

## Troubleshooting

**"Operation timed out" after 15 seconds**
Nothing answered on that address and port. Check the host and port in the form, then use **Test Reachability**.

**"Permission denied (publickey)"**
The server didn't accept any key that was offered. Check the user name. If you use a key file, check that it's the private key and that the server has the matching `.pub` in `~/.ssh/authorized_keys`.

**The file browser says the login shell printed text before SFTP started**
A startup file on the server (for example `~/.bashrc`) prints something, such as an `echo` or a banner, even for non-interactive logins, and that text breaks file transfer. Make it print only for interactive shells. For bash: `[[ $- == *i* ]] && echo "welcome"`.

**macOS asks whether 7 Term may use a Keychain item**
This can happen once after you install a new copy of the app. Click **Always Allow**.

**A host key warning ("REMOTE HOST IDENTIFICATION HAS CHANGED")**
This comes from ssh, not 7 Term. If you rebuilt the machine, remove the old key with `ssh-keygen -R <host>` and connect again. If you didn't, treat it as a possible attack.

**"No serial adapters found"**
macOS doesn't see a serial port. Try another USB port or cable, then check **System Information ▸ USB**: if the adapter is listed there but not in 7 Term, it needs its maker's driver (common for Prolific and Silicon Labs chips).

**A serial console shows nothing, or garbage**
Press Return first: many consoles stay silent until you do. Garbage means the speed is wrong. Try 9600, then 115200.

**"…is in use by another app"**
Another program (screen, minicom, or another 7 Term tab) has the port open. Close it first.

**Where 7 Term keeps things**

| What | Where |
|---|---|
| Saved hosts | `~/Library/Application Support/7 Term/hosts.sqlite` |
| Logs | `~/Documents/7 Term/Logs/` |
| Backups | `iCloud Drive/7 Term/` |
| Passwords | Your login Keychain, under "7 Term" |
