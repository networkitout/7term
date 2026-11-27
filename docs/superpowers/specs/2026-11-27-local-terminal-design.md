# Local terminal ("This Mac") — design

Status: proposed · 2026-11-27

## Intent

7 Term only opens ssh, sftp and serial sessions. Local work (an `nmap`, an
`openssl s_client`, a `dig`) means switching to Terminal.app or iTerm. Give
7 Term a local shell so that work stays in the same window, the same tabs, and
the same logging as the remote sessions, without changing how the app starts.

## Goals

- A built-in **This Mac** row, pinned at the top of the sidebar, with its own
  icon and a subtitle that says what it is (`Local terminal (zsh)`).
- Double-click or Return on it, or **File ▸ New Local Terminal** (⇧⌘T), opens
  a tab running the user's login shell in `$HOME`.
- Present on every install, fresh or updated through Sparkle, with nothing to
  migrate. A What's New entry announces it.
- Local tabs get everything a terminal tab already has: find, themes, font
  size, split view, drag and drop of paths, and per-tab logging with SHA-256.

## Non-goals

- Opening a local tab at launch, or restoring tabs between launches.
- Several local profiles, a per-entry choice of shell, or a starting folder
  per entry.
- Renaming, moving into folders, or deleting the row (hide it instead).

## Anti-goals (a failure even if it works)

- Anything that interrupts the launch flow (no sheet, no auto-opened tab).
- The local row showing up in iCloud backups, restores, imports, Open All,
  SFTP actions or the reachability probe.
- Passing the app's own environment wholesale to the shell (`DYLD_*` and
  similar must never reach it).

## Approaches

| | Approach | Trade-off |
|---|---|---|
| **A (chosen)** | A built-in row drawn by the sidebar, not stored in the hosts database, plus a menu command | Can't break backup, import, SFTP or the probe, and updating needs no migration. It can't be renamed, put in a folder or deleted; settings live in Settings, not on the entry. |
| B | A real host entry of a new `HostKind.local`, created on first launch | Behaves like any host (rename, folders, log by default), but every ssh-only path needs a `.local` check, and deleting it raises the question of whether it comes back. |

Chosen: A, because it is harder to break and the first row in the list makes it
obvious what it is.

## Decided

- **Process:** `TerminalSession.Kind.local`. The executable is the user's login
  shell from `getpwuid(getuid())->pw_shell`, falling back to `/bin/zsh` when that
  is empty or not executable. It is started with
  `execName: "-" + basename(shell)` (a login shell, so `/etc/zprofile` runs
  `path_helper` and dotfiles rebuild `PATH`) and `currentDirectory: $HOME`.
  SwiftTerm 1.99.2 (pinned) supports both parameters.
- **Environment:** a new `ChildEnvironment.makeLocal(from:)` in SevenTermCore.
  It starts from the same allowlist as ssh, adds `SHELL` and
  `TERM_PROGRAM=7Term`, and keeps the baseline `PATH` (the login shell extends
  it). Nothing else is passed; it gets tests next to `ChildEnvironmentTests`.
- **Ending:** when the shell exits, the tab shows the usual ended state.
  ⇧⌘R starts a new shell, and its menu title reads "Restart Shell" for a local
  tab.
- **Settings ▸ General** (a new tab): "Show This Mac in the sidebar" (on) and
  "Log local terminals by default" (off).
- **Update path:** nothing is stored, so updated and fresh installs behave the
  same. What's New gets an entry for the release that ships it.
- **Housekeeping:** add `.anchor/` to `.gitignore` in its own commit.

## Left to the builder

- The icon (an SF Symbol such as `desktopcomputer` or `laptopcomputer`), and the
  styling that sets the row apart from saved hosts.
- How the sidebar filter treats the row (suggested: keep it shown when the
  filter matches "This Mac" or "local", otherwise hide it).
- The log file name for local tabs (suggested: the Mac's short host name, the
  same way remote logs use the host's name).
- Context menu wording (suggested: "Open Local Terminal" and "Hide This Mac…",
  the second pointing to the setting).
- Updating `docs/user-guide.md`, the in-app Help, and `docs/roadmap.md`.
