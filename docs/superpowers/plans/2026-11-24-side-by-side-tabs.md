# Side-by-side Tabs Implementation Plan

> Executed inline (one session).

**Goal:** Show any two tabs side by side in the window, as the approved design describes.

**Spec:** `docs/superpowers/specs/2026-11-24-side-by-side-tabs-design.md`

## Global Constraints

- Branch `feature/side-by-side-tabs`, on top of `feature/tab-drag-hover` (PR #5). Pull request when done.
- Core tests: `cd Packages/SevenTermCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. App build as for PR #4 (unsigned Debug build), expect `BUILD SUCCEEDED` and no warnings from `SevenTerm/`.
- One tab never shows on both sides. `SessionStore.selected` keeps meaning the focused tab, so existing commands are unchanged.

## Review Focus

1. Closing the focused tab while split: the other visible tab takes the focus and the window goes back to one pane. (Task 1 test.)
2. Closing a tab that isn't visible while split: the split and focus stay. (Task 1 test.)
3. Stepping tabs while split never lands on the tab showing on the other side. (Task 1 test.)
4. Show Side by Side when the previous tab has been closed: falls back to the next tab, never to a closed one. (Task 1 test.)
5. Switching between one and two panes must not lose a terminal's scrollback or detach it from its session. (Task 2, by hand.)

### Task 1: The pane rules, in core

- `public struct TabLayout<ID: Hashable>: Equatable` in `Packages/SevenTermCore/Sources/SevenTermCore/Tabs/TabLayout.swift`:
  `focused`, `beside`, `besideOnLeft`, `left`, `right`, `isSplit`;
  `select(_:)` (a tab click or a new tab: the visible other tab swaps focus, a hidden tab replaces the focused side),
  `showBeside(_:)`, `canToggleSideBySide(tabs:)`, `toggleSideBySide(tabs:)` (the previously focused tab if still open, else the next tab), `closed(_:remaining:index:)`, `step(by:tabs:)`.
- Tests `TabLayoutTests` for each rule in the design and the Review Focus items 1 to 4.
- Commit `"Side-by-side tabs: pane rules"`.

### Task 2: The app

- `SessionStore`: `layout: TabLayout<TerminalSession.ID>`; `selectedID` read-only from it; `select(_:)`, `showBeside(_:)`, `toggleSideBySide()`, `canToggleSideBySide`, `beside`; open, close and step go through the layout.
- `MainView.SessionArea`: one pane, or an `HSplitView` of two (each at least 320 points wide, reset to the middle on each split); a click anywhere in a pane focuses it.
- `TabStrip`: dimmer underline for the other visible tab; **Show Beside** in the tab menu for hidden tabs; tab clicks go through `select(_:)`.
- `SevenTermApp`: View ▸ Show Side by Side / Show One Tab (⌥⌘S).
- Build. Commit `"Side-by-side tabs"`.

### Task 3: Docs

- User guide (a "Two tabs side by side" section under Connecting; shortcuts table), help page.
- Commit `"Side-by-side tabs: documentation"`.
