# Host folders: design

Status: built.

## Why

The sidebar is one flat list sorted by name, and tags are the only grouping. That works for a dozen hosts and gets hard to scan past a few dozen. Folders give the list a shape: a place for each site, customer or lab. This is designed before the Windows version so both apps are built on the same host database and backup format.

## Goals

- Hosts and serial entries can be put in folders, and folders can hold folders.
- A whole folder can be opened at once.
- The sidebar shows the tree; folders collapse and expand.
- Importing from an app that has folders keeps them as folders.
- Folders survive backup and restore.
- The database and backup shapes are plain enough for the Windows app to copy exactly.

## Non-goals

- Settings inherited from a folder (user, key, logging). A folder is a place, nothing more.
- Manual ordering. Everything stays sorted by name.
- Replacing tags. Tags stay as they are, for labels that cut across folders.

## Anti-goals

- Deleting a folder must never delete a host.
- Upgrading must not move, rename or re-tag anything a user already has.

## Behaviour

Every item below is a proposal made on the user's instruction to "just propose something"; none was chosen by the user individually.

**Model.** A host is in exactly one folder, or at the top level. Folders nest to any depth. Folder names are unique among siblings, ignoring case, 1 to 60 characters, and may not contain `/`.

**Sidebar.** At each level: folders first, by name, then hosts, by name.

```
▾ Home lab
    ▸ Proxmox
    nas01
    pi-hole
▾ Work
    ▾ Core switches
        sw-core-1
        sw-core-2
    fw-edge
jumpbox
usb-console
```

- Which folders are open is remembered on this computer only (preferences, not the database or backup).
- With a filter or a tag selected, only matching hosts are shown, inside their folders, with those folders opened and empty ones hidden. Clearing the filter puts the open/closed state back.
- The filter also matches folder names: typing "core" finds every host under "Core switches".

**Actions.**

- New Folder: in the sidebar's right-click menu and the Host menu. Created inside the selected folder, or beside the selected host.
- Rename and Delete on a folder's right-click menu.
- Deleting a folder moves its hosts and subfolders up one level, after a confirmation that says so. Nothing else is removed.
- Moving: drag a host or folder onto a folder, or onto the empty area for the top level; "Move to ▸" in the right-click menu; a Folder picker in the host form.
- A folder can't be moved into itself or anything inside it.
- New Host, with a folder or one of its hosts selected, starts in that folder.
- Duplicate keeps the copy in the same folder.

**Open All** (asked for by the user; the details are Claude's proposal).

- "Open All" on a folder's right-click menu and in the Host menu opens a tab for every host in the folder, including those in its subfolders: ssh for hosts, the console for serial entries.
- Tabs open in the order the sidebar shows them.
- With a filter or tag active, only the hosts currently shown in that folder are opened.
- More than 10 tabs asks first: "Open 14 tabs?".
- Disabled for a folder with no hosts.
- Each tab behaves as if opened on its own: per-host logging, and a stored password still asks for Touch ID per host.

**Imports.**

- Sources with real folders keep them as folders: Royal TSX, SecureCRT, MobaXterm, FileZilla. They are no longer added as tags.
- Ansible groups stay tags, because one host can be in several groups.
- Spreadsheet import gains an optional Folder column holding a path such as `Work/Core switches`.
- Importing into an existing library reuses a folder with the same path instead of making a second one.
- `~/.ssh/config` import is unchanged (top level).

**Backup.**

- The backup format version goes up by one. The snapshot gains a list of folders, and each host gains an optional folder id.
- Older backups restore as before, with every host at the top level.
- Restore adds folders that aren't present (by id) and, as today, never changes hosts that already exist.
- An older 7 Term refuses the newer backup with the existing "made by a newer 7 Term" message.

## Approaches

1. **A folder table, and a folder id on each host (chosen, by Claude).** Empty folders exist, a rename is one row, and moving a subtree is one row. It is a plain relational shape that C# reads the same way.
2. **A path string on each host (`Work/Core switches`).** Smallest change, but empty folders can't exist, and a rename rewrites every host underneath.
3. **Folders as a special kind of tag.** No new table, but it bends tags (many per host, flat) into something they aren't, and every tag feature would need to tell the two apart.

## Storage

Migration `v5-folders`:

- Table `folder`: `id` text primary key, `name` text not null, `parentId` text null referencing `folder`, `createdAt`, `updatedAt`.
- Unique index `folder_sibling_name`: `CREATE UNIQUE INDEX folder_sibling_name ON folder(IFNULL(parentId, ''), name COLLATE NOCASE)`. SQLite treats nulls as distinct in a unique index, so `IFNULL(parentId, '')` makes top-level names unique in the database itself.
- Column `host.folderId` text null, referencing `folder`, set to null if the folder goes.

Deleting a folder is done in code inside one transaction: re-parent its hosts and subfolders to its parent, then delete the row. The foreign key rules are a safety net, not the mechanism.

## Where the work lands

- `SevenTermCore`: folder record and tree building, `HostLibrary` folder operations (create, rename, move, delete, cycle check), `HostFilter` (folder names in matching, tree pruning), `HostDraft` (folder), importers, `BackupSnapshot`. All covered by `swift test`.
- App: `HostSidebar` (tree, drag and drop, menus), `HostDirectory` (open state, selection that may be a folder), `HostFormSheet` (Folder picker), `SpreadsheetImportSheet` (Folder column), menus in `SevenTermApp`.
- Docs: user guide and built-in help, roadmap.

## Left to the builder

- Whether the sidebar uses SwiftUI's `OutlineGroup` or disclosure groups, whichever handles drag and drop and selection cleanly.
- The exact wording of menus and the delete confirmation, in the style of the existing ones.
- How the Folder picker shows nesting (indented menu or path text).
