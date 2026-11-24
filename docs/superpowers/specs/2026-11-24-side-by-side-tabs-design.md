# Side-by-side tabs: design

Status: proposed, waiting for the user's approval.

## Why

Only one tab shows at a time, so you can't watch two sessions at once, and a row dragged from a file browser tab has to hover over a terminal's tab to reach it. The user wants "the ability to see two different sessions at once": any two tabs, side by side.

## Chosen approach (user's choice: A)

Two panes in the one window, left and right, with a divider. Not separate windows (B) and not free splitting (C).

## Behaviour

All of this is Claude's proposal for the user to approve.

**Splitting**
- Right-click a tab that isn't showing ▸ **Show Beside**: the window splits, the tab you were on stays on the left, and the clicked tab opens on the right with the focus.
- **View ▸ Show Side by Side** (⌥⌘S) does the same with the tab you used before the current one. With only one tab open it's greyed out.
- **View ▸ Show One Tab** (⌥⌘S again, the same command toggling) goes back to one pane, keeping the focused tab.
- A tab can only show on one side at a time.

**The focused side**
- Clicking anywhere in a pane focuses it; the focused pane's tab is "the current tab".
- Everything that acts on the current tab acts on the focused side: ⌘W, ⇧⌘R, ⇧⌘L logging and the Log button, ⌘F, ⌘B Send Break, text-size changes are already global.
- New tabs (double-clicking a host, Quick Connect) open in the focused side.
- ⇧⌘] and ⇧⌘[ step the focused side through the tabs, skipping the one showing on the other side.

**The tab bar**
- Stays one row for all tabs. The focused side's tab has the usual accent underline; the other visible tab has a thinner, dimmer one, so you can see which two are showing.
- Clicking a tab that isn't showing puts it in the focused side. Clicking the other visible tab focuses its side.

**Closing**
- Closing either visible tab goes back to one pane, showing the other.

**The divider**
- Starts in the middle and can be dragged; each side keeps at least 320 points. It resets to the middle each time you split.

**Unchanged**
- Drag and drop between the sides works directly (it already works on any visible terminal). Hover-to-open in the tab bar still works and puts the tab in the focused side.
- Nothing about splits is saved between launches (tabs aren't either).

## Non-goals

Top and bottom splits, more than two panes, splits in separate windows, saved layouts.

## Where it lands

- `SessionStore`: which tab is on each side and which side has focus; `selected` keeps meaning the focused tab, so existing commands need no change. Selection, stepping, opening and closing learn about the second side.
- `MainView`'s session area: one pane or two with a divider, each pane hosting a terminal or a file browser; clicking a pane focuses it.
- `TabStrip`: the second underline, **Show Beside** in the tab menu, click rules.
- `SevenTermApp`: the View menu command.
- Docs: user guide (Connecting), shortcuts table, help page.
- `TerminalHost` currently moves a session's terminal view into whichever container shows it; two hosts showing two different sessions is fine, but the code must never show one session in both.

## Left to the builder

- Whether the divider is SwiftUI's `HSplitView` or a custom one, whichever keeps the terminal views stable when the split changes.
- How "the tab used before the current one" is tracked (a short history is enough).
