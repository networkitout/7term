/// Which tabs the window shows: one, or two side by side. `focused` is the
/// current tab (where commands and new tabs go); `beside` is the other
/// visible tab when the window is split. A tab never shows on both sides.
public struct TabLayout<ID: Hashable>: Equatable {
    public private(set) var focused: ID?
    public private(set) var beside: ID?
    /// Whether `beside` is the left pane (so the focused tab is on the right).
    public private(set) var besideOnLeft = true
    /// The tab focused before the current one, for Show Side by Side.
    private var previous: ID?
    /// Which side `previous` was on when the split last ended, so splitting
    /// again with the same pair puts each tab back where it was.
    private var previousWasOnLeft: Bool?

    public init() {}

    public var isSplit: Bool { beside != nil }
    public var left: ID? { isSplit && besideOnLeft ? beside : focused }
    public var right: ID? {
        guard isSplit else { return nil }
        return besideOnLeft ? focused : beside
    }

    /// A tab clicked, or a new tab opened: the other visible tab just takes
    /// the focus; any other tab replaces the focused side.
    public mutating func select(_ id: ID) {
        guard id != focused else { return }
        if id == beside {
            previous = focused
            beside = focused
            besideOnLeft.toggle()
            focused = id
        } else {
            previous = focused
            previousWasOnLeft = nil
            focused = id
        }
    }

    /// Shows a tab beside the current one and focuses it. In one pane the
    /// current tab stays on the left; when split, it replaces the other side.
    public mutating func showBeside(_ id: ID) {
        guard let current = focused, id != current else { return }
        if id == beside { select(id); return }
        besideOnLeft = isSplit ? !besideOnLeft : true
        beside = current
        previous = current
        previousWasOnLeft = nil
        focused = id
    }

    public func canToggleSideBySide(tabs: [ID]) -> Bool {
        isSplit || (focused != nil && tabs.count >= 2)
    }

    /// Back to one pane (keeping the focused tab), or split with the tab used
    /// before the current one, falling back to the next tab. The focus stays
    /// on the current tab. Splitting again with the pair just shown puts each
    /// tab back on its side; otherwise the current tab takes the left.
    public mutating func toggleSideBySide(tabs: [ID]) {
        if isSplit {
            previous = beside
            previousWasOnLeft = besideOnLeft
            beside = nil
            return
        }
        guard let current = focused, let index = tabs.firstIndex(of: current), tabs.count >= 2 else { return }
        if let previous, previous != current, tabs.contains(previous) {
            beside = previous
            besideOnLeft = previousWasOnLeft ?? false
        } else {
            beside = tabs[(index + 1) % tabs.count]
            besideOnLeft = false
        }
    }

    /// A tab was closed. `remaining` is the tab list without it; `index` is
    /// where it was. Closing either visible tab goes back to one pane.
    public mutating func closed(_ id: ID, remaining: [ID], index: Int) {
        if previous == id { previous = nil; previousWasOnLeft = nil }
        if id == beside {
            beside = nil
        } else if id == focused {
            if let other = beside {
                focused = other
                beside = nil
            } else {
                focused = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
            }
        }
    }

    /// The next or previous tab in the focused side, skipping the tab showing
    /// on the other side.
    public mutating func step(by offset: Int, tabs: [ID]) {
        let candidates = tabs.filter { $0 != beside }
        guard !candidates.isEmpty, let current = focused, let index = candidates.firstIndex(of: current) else { return }
        let count = candidates.count
        let next = candidates[((index + offset) % count + count) % count]
        guard next != current else { return }
        previous = current
        previousWasOnLeft = nil
        focused = next
    }
}
