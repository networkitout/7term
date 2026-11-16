# Host Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hosts and serial entries can be organised into nested folders, shown as a tree in the sidebar, kept by imports and backups, and opened a folder at a time.

**Architecture:** A new `folder` table and a nullable `host.folderId` in the existing SQLite library. All rules (naming, cycles, delete-moves-up, tree building, filtering, import paths, backup format 2) live in `SevenTermCore` and are tested with `swift test`; the app layer only renders the tree and calls those operations.

**Tech Stack:** Swift 6, GRDB 7.12.0, Swift Testing, SwiftUI/AppKit (macOS 14+), XcodeGen.

**Spec:** `docs/folders.md`

## Global Constraints

- Work on branch `feature/host-folders`, cut from `main`. Commit per task. Do not push.
- No new dependencies.
- A host is in exactly one folder or at the top level (`folderId == nil`).
- Folder names: trimmed, 1 to 60 characters, no `/`, unique among siblings ignoring case.
- Sort order everywhere: folders first by name, then hosts by name, both with `localizedCaseInsensitiveCompare`.
- Deleting a folder never deletes a host or a subfolder.
- Upgrading must not move, rename or re-tag anything already saved. Imports never move a host that already exists.
- Which folders are open is stored in `UserDefaults` on this Mac only; never in the database or backup.
- Tags behave exactly as before.
- Core tests: `cd Packages/SevenTermCore && swift test`. App build check: `xcodegen generate && xcodebuild -project SevenTerm.xcodeproj -scheme SevenTerm -configuration Debug build` (expect `BUILD SUCCEEDED`).
- Commit messages follow the repo's plain-sentence style and end with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`.

## Review Focus

1. A folder is deleted while a subfolder has the same name as a folder one level up: the delete must succeed, with the moved-up subfolder renamed "<name> 2" (then 3, …). Test in Task 1.
2. A host or folder points at a parent that doesn't exist, or folders form a loop (damaged or hand-edited database): everything still appears, at the top level; building the tree never hangs. Test in Task 2.
3. An imported folder name contains `/`, is longer than 60 characters, or a path has empty or differently-cased segments (`work//Core/`): the import succeeds and reuses existing folders. Test in Task 4.
4. A format 1 backup (no folders) restores with every host at the top level, and a format 2 backup restored into a library that already has a same-named sibling folder reuses it instead of failing. Test in Task 5.
5. Open All with a filter active that hides every host in the folder: the command is disabled, not a no-op confirmation. Test in Task 2 (`HostTree.hosts(in:nodes:)` returns empty) and checked by hand in Task 8.

## File Map

| File | Change |
|---|---|
| `Packages/SevenTermCore/Sources/SevenTermCore/Hosts/HostFolder.swift` | New: the folder record and name rule |
| `…/Hosts/HostLibrary+Folders.swift` | New: folder operations |
| `…/Hosts/HostTree.swift` | New: tree building, pruning, paths |
| `…/Hosts/SavedHost.swift`, `HostLibrary.swift`, `HostDraft.swift`, `HostFilter.swift`, `HostImport.swift` | Modified |
| `…/Import/ForeignHostImport.swift`, `ForeignImporters.swift` | Modified |
| `…/Backup/BackupSnapshot.swift` | Modified |
| `Packages/SevenTermCore/Tests/SevenTermCoreTests/HostFolderTests.swift`, `HostTreeTests.swift` | New |
| `SevenTerm/Hosts/HostDirectory.swift`, `SevenTerm/UI/HostSidebar.swift`, `HostFormSheet.swift`, `SevenTerm/App/SevenTermApp.swift`, `SevenTerm/Sessions/SessionStore.swift`, `SevenTerm/Backup/BackupManager.swift` | Modified |
| `SevenTerm/UI/FolderNameSheet.swift` | New: name prompt for New Folder and Rename |
| `docs/user-guide.md`, `docs/roadmap.md`, `docs/folders.md`, `README.md`, `SevenTerm/Resources/Help/help.html` | Modified |

---

### Task 1: Folder storage and operations

**Files:**
- Create: `Packages/SevenTermCore/Sources/SevenTermCore/Hosts/HostFolder.swift`
- Create: `Packages/SevenTermCore/Sources/SevenTermCore/Hosts/HostLibrary+Folders.swift`
- Modify: `…/Hosts/SavedHost.swift` (add `folderId`), `…/Hosts/HostLibrary.swift` (migration, `database` visibility, errors)
- Test: `Packages/SevenTermCore/Tests/SevenTermCoreTests/HostFolderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct HostFolder: Codable, Hashable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
      public static let databaseTableName = "folder"
      public var id: String
      public var name: String
      public var parentId: String?
      public var createdAt: Date
      public var updatedAt: Date
      public init(id: String = UUID().uuidString, name: String, parentId: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date())
      /// Trimmed name, or nil if empty, over 60 characters, or containing "/".
      public static func cleanName(_ raw: String) -> String?
  }
  // SavedHost gains: public var folderId: String?   (init parameter `folderId: String? = nil`, after `serial`)
  extension HostLibrary {
      public func folders() throws -> [HostFolder]                       // sorted by name
      @discardableResult public func createFolder(name: String, parentId: String?, now: Date = Date()) throws -> HostFolder
      public func renameFolder(id: String, to name: String, now: Date = Date()) throws
      public func moveFolder(id: String, toParent parentId: String?, now: Date = Date()) throws
      public func moveHost(id: String, toFolder folderId: String?, now: Date = Date()) throws
      public func deleteFolder(id: String, now: Date = Date()) throws
      /// Finds or creates each level (names matched ignoring case). Empty path returns nil.
      @discardableResult public func ensureFolder(path: [String], now: Date = Date()) throws -> String?
  }
  // HostLibraryError gains: .invalidFolderName, .duplicateFolderName, .folderNotFound, .folderCycle
  ```
- `HostLibraryError` also conforms to `LocalizedError` with exactly these messages:
  - `.invalidDraft`: "That host can't be saved as it is."
  - `.invalidFolderName`: "Folder names are 1 to 60 characters and can't contain \"/\"."
  - `.duplicateFolderName`: "There's already a folder with that name here."
  - `.folderNotFound`: "That folder no longer exists."
  - `.folderCycle`: "A folder can't be moved into itself."

- [ ] **Step 1: Write the failing tests** in `HostFolderTests.swift` (`@Suite struct HostFolderTests`, each test starts from `try HostLibrary.inMemory()`):

  | Test | Asserts |
  |---|---|
  | `cleanNameRules` | `cleanName("  Lab ") == "Lab"`; nil for `""`, `"   "`, `"a/b"`, and a 61-character string; a 60-character string passes |
  | `createAndList` | create "Work", then "Core" inside it; `folders()` has both; "Core".parentId is Work's id |
  | `siblingNamesAreUniqueIgnoringCase` | creating "work" beside "Work" at top level throws `.duplicateFolderName`; same inside a parent; "Work" inside "Work" is allowed |
  | `createInMissingParentThrows` | `parentId: "nope"` throws `.folderNotFound` |
  | `renameChecksNameAndSiblings` | rename to `"a/b"` throws `.invalidFolderName`; to a sibling's name throws `.duplicateFolderName`; renaming "Work" to "WORK" succeeds |
  | `moveFolderRejectsCycles` | A ▸ B ▸ C: moving A into A, B or C throws `.folderCycle`; moving C to top level succeeds |
  | `moveFolderIntoSiblingNameClashThrows` | moving "Lab" into a parent that already has "lab" throws `.duplicateFolderName` |
  | `moveHost` | save a host, move it into a folder: `entries().first?.host.folderId` is the folder id; move to nil clears it; moving to `"nope"` throws `.folderNotFound` |
  | `deleteMovesContentsUp` | Work ▸ Core with host h1 in Work and h2 in Core; delete Work: Core.parentId is nil, h1.folderId is nil, h2.folderId is still Core, both hosts still exist |
  | `deleteRenamesOnNameClash` | top-level "Lab" and Work ▸ "Lab"; delete Work: both survive at top level, named "Lab" and "Lab 2" |
  | `ensureFolderReusesAndCreates` | `ensureFolder(path: ["Work", "Core"])` twice returns the same id and leaves 2 folders; `["work", "CORE"]` returns that id too; `[]` returns nil |
  | `hostsStartAtTopLevel` | two saved hosts both have `folderId == nil`, and `folders().isEmpty` |
  | `reopeningKeepsFolders` | make a `DatabaseQueue()`, open `HostLibrary` on it, create a folder and move a host in, open a second `HostLibrary` on the same queue: the folder and the host's `folderId` are unchanged (migrations run twice without harm) |

- [ ] **Step 2: Run** `cd Packages/SevenTermCore && swift test --filter HostFolderTests`. Expected: build fails (`HostFolder` not defined).

- [ ] **Step 3: Implement.**
  - In `HostLibrary.swift`: change `private let database` to `let database`. Register migration `"v5-folders"` after v4:
    - table `folder`: `id` text primary key; `name` text not null; `parentId` text, references `folder`, on delete set null, indexed; `createdAt`, `updatedAt` datetime not null.
    - `CREATE UNIQUE INDEX folder_sibling_name ON folder(IFNULL(parentId, ''), name COLLATE NOCASE)` (raw SQL; this covers the top level, where `parentId` is null).
    - `host.folderId` text, references `folder`, on delete set null, indexed.
  - Operations check names and siblings in code first so they throw the errors above; the index is the backstop.
  - `deleteFolder` runs in one `database.write`: re-parent child folders (renaming with " 2", " 3", … while a sibling at the destination has that name, ignoring case), re-parent hosts, then delete the row.
  - Cycle check for `moveFolder`: walk `parentId` from the destination up to the root; throw `.folderCycle` if the moved id is met (or the destination is the moved id).

- [ ] **Step 4: Run** `swift test`. Expected: all suites pass, including the existing ones.

- [ ] **Step 5: Commit** `git commit -am "Host folders: storage and operations"` (after `git add` of the new files).

---

### Task 2: Tree building and filtering

**Files:**
- Create: `…/Hosts/HostTree.swift`
- Modify: `…/Hosts/HostFilter.swift`
- Test: `…/Tests/SevenTermCoreTests/HostTreeTests.swift`

**Interfaces:**
- Consumes: `HostFolder`, `SavedHost.folderId` (Task 1).
- Produces:
  ```swift
  public enum HostTreeNode: Hashable, Sendable, Identifiable {
      case folder(HostFolder, children: [HostTreeNode])
      case host(HostEntry)
      public var id: String              // the folder's or host's own id (both are UUID strings)
      public var children: [HostTreeNode]?   // nil for a host
  }
  public enum HostTree {
      /// Everything, folders first then hosts at each level.
      public static func build(folders: [HostFolder], entries: [HostEntry]) -> [HostTreeNode]
      /// Only hosts matching `query` and `tag`, inside their folders; folders left empty are dropped.
      public static func filtered(folders: [HostFolder], entries: [HostEntry], query: String, tag: String?) -> [HostTreeNode]
      /// Hosts under a folder, subfolders included, in sidebar order.
      public static func hosts(in folderId: String, nodes: [HostTreeNode]) -> [HostEntry]
      /// Folder names from the top level down to `folderId`; [] for nil or unknown.
      public static func path(of folderId: String?, folders: [HostFolder]) -> [String]
      /// Every folder as (folder, depth), in sidebar order; for pickers and menus.
      public static func flattened(folders: [HostFolder]) -> [(folder: HostFolder, depth: Int)]
  }
  // HostFilter: matches(_ entry: HostEntry, query: String, folderPath: [String] = []) -> Bool
  //   folder names count as extra searchable fields.
  ```

- [ ] **Step 1: Write the failing tests** (`@Suite struct HostTreeTests`; build folders and entries in memory, no database):

  | Test | Asserts |
  |---|---|
  | `foldersFirstThenHostsByName` | folders "Work", "home lab" and top-level hosts "zeta", "Alpha" give ids in order: home lab, Work, Alpha, zeta |
  | `nesting` | Work ▸ Core ▸ sw1: the Work node's children hold Core, whose children hold sw1 |
  | `orphansShowAtTopLevel` | a host with `folderId: "gone"` and a folder with `parentId: "gone"` both appear at the top level |
  | `loopsDoNotHang` | folders A (parent B) and B (parent A): `build` returns, and both appear at the top level exactly once |
  | `filteredPrunesEmptyFolders` | Work ▸ {sw1, fw1}, Lab ▸ {pi}: query "sw" gives only Work ▸ sw1 |
  | `filterMatchesFolderName` | query "work" returns both hosts under Work; `HostFilter.matches(entry, query: "core sw", folderPath: ["Work", "Core"])` is true |
  | `tagFilterStillApplies` | `filtered(…, query: "", tag: "prod")` keeps only tagged hosts, in their folders |
  | `hostsInFolderIncludeSubfolders` | Work ▸ {Core ▸ {sw2, sw1}, fw1}: `hosts(in: work)` names are sw1, sw2, fw1 |
  | `hostsInFolderRespectFilter` | with `filtered(query: "zzz")` nodes, `hosts(in: work, nodes:)` is empty |
  | `pathAndFlattened` | `path(of: core)` is `["Work", "Core"]`; `path(of: nil)` is `[]`; `flattened` gives (Lab,0), (Work,0), (Core,1) |

- [ ] **Step 2: Run** `swift test --filter HostTreeTests`. Expected: build fails (`HostTree` not defined).
- [ ] **Step 3: Implement.** Build children maps keyed by parent id; treat a parent id that isn't in `folders`, or a folder reachable only through a loop, as top level (detect loops by walking up with a visited set).
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `"Host folders: tree and filter"`.

---

### Task 3: Folder on the host draft

**Files:**
- Modify: `…/Hosts/HostDraft.swift`, `…/Hosts/HostLibrary.swift` (`save`, `saveSerial`, `duplicate`)
- Test: `…/Tests/SevenTermCoreTests/HostFolderTests.swift`

**Interfaces:**
- Produces: `HostDraft.folderId: String?` (default nil; `init(entry:)` copies `entry.host.folderId`). `HostLibrary.save` writes it for ssh and serial hosts; an id that isn't a folder is saved as nil.

- [ ] **Step 1: Add failing tests** to `HostFolderTests`:
  - `saveKeepsFolder`: draft with `folderId` of an existing folder saves with it; editing the same host through `HostDraft(entry:)` and saving keeps it.
  - `saveSerialKeepsFolder`: the same for `kind = .serial` with `serialPath = "/dev/cu.usbserial-1"`.
  - `saveWithUnknownFolderGoesToTopLevel`: `folderId = "nope"` saves with `folderId == nil`, no throw.
  - `duplicateStaysInFolder`: `duplicate(id:)` of a host in a folder returns an entry with the same `folderId`.
- [ ] **Step 2: Run** `swift test --filter HostFolderTests`. Expected: build fails (`folderId` not a member of `HostDraft`).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `"Host folders: folder on the host draft"`.

---

### Task 4: Imports keep folders

**Files:**
- Modify: `…/Import/ForeignHostImport.swift`, `…/Import/ForeignImporters.swift`, `…/Hosts/HostImport.swift`
- Test: `…/Tests/SevenTermCoreTests/ForeignImportTests.swift`, `HostImportTests.swift`

**Interfaces:**
- Consumes: `HostLibrary.ensureFolder(path:)`, `HostFolder.cleanName` (Task 1).
- Produces:
  - `ImportedHost.folder: [String]` (outermost first; new init parameter `folder: [String] = []` after `tags`).
  - `HostImportColumn.folder`, title "Folder". Header words `folder`, `folders`, `path` move to it (removed from `.tags`).
  - `HostImportCandidate.folderPath: [String]`.
  - `ForeignImportResult.table` header becomes `["Name", "Host", "Port", "User", "Tags", "Folder", "Key file"]`, the folder cell joined with `/`.
  - `static func HostImportTable.folderPath(from cell: String) -> [String]`: split on `/` and `\`, trim each part, drop empty parts, cut each to 60 characters.

- [ ] **Step 1: Update and add failing tests.**
  - In `ForeignImportTests`, for Royal TSX, SecureCRT, MobaXterm and FileZilla: change the existing expectations so the folder path is in `.folder` and `.tags` is `[]`. Ansible and Tabby expectations are unchanged (tags).
  - `folderNameWithSlashIsCleaned`: a SecureCRT or FileZilla folder named `DC/East` arrives as `"DC-East"`.
  - In `HostImportTests`:
    - `folderColumnIsRecognised`: header `Name,Host,Folder` maps the third column to `.folder`.
    - `folderPathParsing`: `folderPath(from: " Work //Core\\Edge/ ")` is `["Work", "Core", "Edge"]`; a 70-character part is cut to 60.
    - `importCreatesAndReusesFolders`: library already has "work"; importing two rows with folder `Work/Core` leaves exactly 2 folders ("work", "Core") and both hosts in Core.
    - `importNeverMovesExistingHost`: a saved top-level host matched by a row with folder `Work`, `updateExisting: true`: the host's `folderId` is still nil.
- [ ] **Step 2: Run** `swift test --filter "ForeignImportTests|HostImportTests"`. Expected: fails to build (`folder` not a member).
- [ ] **Step 3: Implement.** Importers replace `/` in a source folder name with `-`. `importHosts` sets `draft.folderId = try ensureFolder(path: candidate.folderPath)` for new hosts only. Change the hints: Royal TSX ends "…folders are kept."; nothing else in the hints mentions tags for folder sources.
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `"Host folders: imports keep folders"`.

---

### Task 5: Backup format 2

**Files:**
- Modify: `…/Backup/BackupSnapshot.swift`, `…/Hosts/HostLibrary.swift` (`restore`)
- Test: `…/Tests/SevenTermCoreTests/BackupTests.swift`

**Interfaces:**
- Produces:
  ```swift
  // BackupSnapshot
  public static let currentFormat = 2
  public struct Folder: Codable, Equatable, Sendable { id, name, parentId: String?, createdAt, updatedAt; init(_ folder: HostFolder) }
  public var folders: [Folder]?            // nil when read from a format 1 backup
  // BackupSnapshot.Host gains: public var folderId: String?
  public init(exportedAt: Date = Date(), appVersion: String, hosts: [HostEntry], folders: [HostFolder], settings: Settings, importedPalettes: [TerminalPalette])
  // HostLibrary
  @discardableResult public func restore(_ hosts: [BackupSnapshot.Host], folders: [BackupSnapshot.Folder] = []) throws -> Int
  ```

- [ ] **Step 1: Add failing tests** to `BackupTests`:
  - `roundTripKeepsFolders`: snapshot of Work ▸ Core with a host in Core, encoded, decoded, restored into an empty library: same folder ids, names and parent; the host's `folderId` is Core.
  - `formatOneStillRestores`: a JSON literal with `"formatVersion": 1`, no `folders` key and no `folderId` on hosts decodes; restoring gives hosts with `folderId == nil`.
  - `formatThreeIsRefused`: `"formatVersion": 3` throws `ReadError.newerFormat(3)`.
  - `restoreReusesSameNamedSibling`: library has top-level "Work" (id X); backup has top-level "Work" (id Y) holding a host: after restore there is one "Work", and the host's `folderId` is X.
  - `restoreNeverChangesExistingHosts`: a host already present by id keeps its current folder even if the backup puts it elsewhere.
- [ ] **Step 2: Run** `swift test --filter BackupTests`. Expected: build fails.
- [ ] **Step 3: Implement.** In `restore`, insert folders parents-first inside the same write; keep a map from backup folder id to the id actually used (its own, or the existing same-named sibling's); a host's `folderId` goes through the map, and to nil if unmapped.
- [ ] **Step 4: Run** `swift test`. Expected: pass.
- [ ] **Step 5: Commit** `"Host folders: backup format 2"`.

---

### Task 6: Sidebar tree and folder actions

**Files:**
- Modify: `SevenTerm/Hosts/HostDirectory.swift`, `SevenTerm/UI/HostSidebar.swift`, `SevenTerm/App/SevenTermApp.swift`, `SevenTerm/Backup/BackupManager.swift`
- Create: `SevenTerm/UI/FolderNameSheet.swift`

**Interfaces:**
- Consumes: Tasks 1, 2, 5.
- Produces, on `HostDirectory`:
  ```swift
  private(set) var folders: [HostFolder]
  var selectedID: String?                    // renamed from selectedHostID; a host or folder id
  var selectedFolder: HostFolder? { get }
  var isFiltering: Bool { get }              // query non-empty or tagFilter != nil
  var tree: [HostTreeNode] { get }           // HostTree.filtered when isFiltering, else HostTree.build
  var expandedFolderIDs: Set<String>         // saved to UserDefaults key "expandedFolders" on change
  func isExpanded(_ folderID: String) -> Bool   // always true while isFiltering
  var folderForNewItems: String? { get }     // selected folder's id, else selected host's folderId
  var folderNameRequest: FolderNameRequest?  // enum: .new(parentId: String?), .rename(HostFolder); Identifiable
  var pendingFolderDelete: HostFolder?
  func createFolder(name: String, parentId: String?) -> String?   // error message or nil; expands the parent
  func renameFolder(_ folder: HostFolder, to name: String) -> String?
  func deleteFolder(_ folder: HostFolder)
  func move(itemID: String, toFolder folderID: String?)           // host or folder, by id
  func hosts(in folder: HostFolder) -> [HostEntry]                // HostTree.hosts(in:nodes: tree)
  ```
  `reload()` also loads `folders` and drops ids from `expandedFolderIDs` that no longer exist. `restore` takes and passes the snapshot's folders. `BackupManager` passes `hosts.folders` into `BackupSnapshot(…)` and `snapshot.folders ?? []` into restore.

- [ ] **Step 1: Implement `HostDirectory` changes** and rename `selectedHostID` to `selectedID` at every use (`grep -rn selectedHostID SevenTerm`).
- [ ] **Step 2: Implement the sidebar tree** in `HostSidebar.swift`.
  - Rows come from `hosts.tree`; a folder row shows a folder icon and its name in `Brand.mono(13, weight: .medium)`, and its expansion is bound to `hosts.expandedFolderIDs` through `isExpanded` (so plain `OutlineGroup`, which owns its own expansion state, doesn't fit).
  - Host rows are the existing `HostRow`, unchanged.
  - Double-click or Return on a folder toggles it; on a host it connects, as now.
  - Drag a host or folder row (its id as the payload); drop on a folder row moves it there; drop on the list's empty area moves it to the top level. Errors from the library (`.folderCycle`, `.duplicateFolderName`) show in the existing `errorMessage` line.
  - Empty state: unchanged condition, but "no results" shows when `hosts.tree.isEmpty` and there are entries.
- [ ] **Step 3: Menus.**
  - Folder right-click: `New Host…`, `New Folder…`, divider, `Rename…`, `Move to ▸`, divider, `Delete…`.
  - Host right-click gains `Move to ▸` after `Duplicate`.
  - Empty-area right-click gains `New Folder…`.
  - `Move to ▸` lists `Top Level`, a divider, then `HostTree.flattened(folders:)` indented by depth; for a folder, itself and its descendants are left out.
  - `SevenTermApp` Host menu gains `New Folder…` (⇧⌘N) at the top; the existing host items are disabled when the selection is a folder.
  - `FolderNameSheet`: one text field, title "New Folder" or "Rename Folder", default button "Create" or "Rename", disabled while `HostFolder.cleanName` is nil; shows the returned error message under the field.
  - Delete confirmation, exact copy: title `Delete the folder "<name>"?`, message `Its hosts and folders move up one level. Nothing else is removed.`, button `Delete Folder`.
- [ ] **Step 4: Build** with the app build command. Expected: `BUILD SUCCEEDED`.
- [ ] **Step 5: Check by hand** in the running app: create nested folders; drag a host in and out; try dragging a folder into its own child (refused with the message); quit and reopen (open/closed state kept); type a filter (folders open, empty ones hidden) and clear it (state restored); delete a folder holding a host and a subfolder (both move up).
- [ ] **Step 6: Commit** `"Host folders: sidebar tree, folder actions"`.

---

### Task 7: Folder in the host form and the import sheet

**Files:**
- Modify: `SevenTerm/UI/HostFormSheet.swift`, `SevenTerm/UI/HostSidebar.swift` (sheet call), `SevenTerm/UI/SpreadsheetImportSheet.swift`

**Interfaces:**
- Consumes: `HostDraft.folderId` (Task 3), `HostDirectory.folders`, `folderForNewItems` (Task 6), `HostImportColumn.folder` (Task 4).
- Produces: `HostFormSheet(entry:folders:initialFolderID:onSave:)`.

- [ ] **Step 1:** Add a `Folder` picker directly under the Tags field in both the ssh and serial sections of `HostFormSheet`: `Top Level`, then `HostTree.flattened(folders:)` indented by depth. A new host starts with `initialFolderID`; an edited host starts with its own.
- [ ] **Step 2:** In `SpreadsheetImportSheet`, make sure `Folder` appears in each column's menu and in the preview (it is driven by `HostImportColumn.allCases`; fix any switch that is no longer exhaustive). Under the preview add the line `Folders are written as a path, for example Work/Core switches.` when a column is mapped to Folder.
- [ ] **Step 3: Build.** Expected: `BUILD SUCCEEDED`.
- [ ] **Step 4: Check by hand:** New Host with a folder selected starts in that folder; changing the picker moves the host; pasting `Name,Host,Folder` rows creates the folders; importing `Royaltsxfilled.rtsz` from the repo root keeps its folders as folders.
- [ ] **Step 5: Commit** `"Host folders: folder picker, import column"`.

---

### Task 8: Open All

**Files:**
- Modify: `SevenTerm/Sessions/SessionStore.swift`, `SevenTerm/Hosts/HostDirectory.swift`, `SevenTerm/UI/HostSidebar.swift`, `SevenTerm/App/SevenTermApp.swift`

**Interfaces:**
- Consumes: `HostDirectory.hosts(in:)` (Task 6), `SessionStore.open(_:kind:)`.
- Produces: `SessionStore.openAll(_ entries: [HostEntry])` (calls `open(entry, kind: .ssh)` for each, in order; serial entries already open as consoles through that call). `HostDirectory.pendingOpenAll: [HostEntry]?`. `static let HostDirectory.openAllConfirmThreshold = 10`.

- [ ] **Step 1:** Add `Open All` as the first item of the folder right-click menu and, after a divider, in the Host menu (enabled when a folder is selected). Both are disabled when `hosts.hosts(in: folder).isEmpty`.
- [ ] **Step 2:** With 10 or fewer hosts, open at once. With more, set `pendingOpenAll` and confirm; exact copy: title `Open <n> tabs?`, message `One tab for each host in "<name>", including its folders.`, button `Open <n> Tabs`.
- [ ] **Step 3: Build.** Expected: `BUILD SUCCEEDED`.
- [ ] **Step 4: Check by hand:** a folder of 3 opens 3 tabs in sidebar order, subfolder hosts included; a folder of 11 asks first; with a filter that hides every host in the folder, Open All is disabled; with a filter that leaves 2, exactly those 2 open.
- [ ] **Step 5: Commit** `"Host folders: Open All"`.

---

### Task 9: Documentation

**Files:**
- Modify: `docs/user-guide.md`, `SevenTerm/Resources/Help/help.html` (regenerate with `python3 tools/build_help.py`; read the script's header first for its arguments), `docs/roadmap.md`, `README.md`, `docs/folders.md`

- [ ] **Step 1:** User guide: a "Folders" section after the tags/filter section covering creating, renaming, moving (drag, Move to, the form), deleting (contents move up), filtering by folder name, and Open All; add `Folder` to the host form table and the spreadsheet column list; in the import table rename the "Becomes tags" column to "Folders or groups become" with `folders` for Royal TSX, SecureCRT, MobaXterm, FileZilla and `tags` for Ansible; add folders to the backup "Included" line.
- [ ] **Step 2:** Roadmap: add milestone 14, "Folders for hosts, Open All ([design](folders.md))", Done. README features: extend the "Saved hosts" bullet to "…with folders, tags, a filter…". `docs/folders.md`: status line to "Status: built.", and replace the Storage note about checking top-level uniqueness in code with the `IFNULL(parentId, '')` index actually used.
- [ ] **Step 3:** Regenerate the help and confirm `git diff --stat` shows `help.html` changed.
- [ ] **Step 4:** Run `cd Packages/SevenTermCore && swift test` and the app build one last time. Expected: all tests pass, `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit** `"Host folders: documentation"`.
