import Testing
@testable import SevenTermCore

@Suite struct TabLayoutTests {
    private let tabs = ["a", "b", "c", "d"]

    private func layout(focused: String) -> TabLayout<String> {
        var layout = TabLayout<String>()
        layout.select(focused)
        return layout
    }

    @Test func singlePaneShowsTheFocusedTab() {
        let l = layout(focused: "a")
        #expect(l.left == "a")
        #expect(l.right == nil)
        #expect(!l.isSplit)
    }

    @Test func showBesideKeepsCurrentOnLeftAndFocusesTheNewTab() {
        var l = layout(focused: "a")
        l.showBeside("c")
        #expect(l.left == "a")
        #expect(l.right == "c")
        #expect(l.focused == "c")
        #expect(l.beside == "a")
    }

    @Test func showBesideTheFocusedTabDoesNothing() {
        var l = layout(focused: "a")
        l.showBeside("a")
        #expect(!l.isSplit)
    }

    @Test func clickingTheOtherVisibleTabMovesFocusNotTabs() {
        var l = layout(focused: "a")
        l.showBeside("c")
        l.select("a")
        #expect(l.focused == "a")
        #expect(l.left == "a")
        #expect(l.right == "c")
    }

    @Test func clickingAHiddenTabReplacesTheFocusedSide() {
        var l = layout(focused: "a")
        l.showBeside("c")          // a | c*, focus right
        l.select("d")
        #expect(l.left == "a")
        #expect(l.right == "d")
        #expect(l.focused == "d")
        l.select("a")              // focus left
        l.select("b")
        #expect(l.left == "b")
        #expect(l.right == "d")
    }

    @Test func toggleSplitsWithThePreviousTabAndBack() {
        var l = layout(focused: "a")
        l.select("c")              // previous is a
        let tabs = ["a", "b", "c", "d"]
        #expect(l.canToggleSideBySide(tabs: tabs))
        l.toggleSideBySide(tabs: tabs)
        #expect(l.isSplit)
        #expect(Set([l.left, l.right]) == Set(["a", "c"]))
        #expect(l.focused == "c")
        l.toggleSideBySide(tabs: tabs)
        #expect(!l.isSplit)
        #expect(l.focused == "c")
    }

    @Test func toggleFallsBackWhenThePreviousTabIsGone() {
        var l = layout(focused: "a")
        l.select("c")              // previous is a
        l.closed("a", remaining: ["b", "c", "d"], index: 0)
        l.toggleSideBySide(tabs: ["b", "c", "d"])
        #expect(l.isSplit)
        #expect(l.beside != "a")
        #expect(l.beside == "d")   // the next tab after c
    }

    @Test func toggleNeedsTwoTabs() {
        let l = layout(focused: "a")
        #expect(!l.canToggleSideBySide(tabs: ["a"]))
        #expect(l.canToggleSideBySide(tabs: ["a", "b"]))
    }

    @Test func closingTheFocusedVisibleTabUnsplitsAndFocusesTheOther() {
        var l = layout(focused: "a")
        l.showBeside("c")          // a | c*
        l.closed("c", remaining: ["a", "b", "d"], index: 2)
        #expect(!l.isSplit)
        #expect(l.focused == "a")
    }

    @Test func closingTheOtherVisibleTabUnsplitsKeepingFocus() {
        var l = layout(focused: "a")
        l.showBeside("c")          // a | c*
        l.closed("a", remaining: ["b", "c", "d"], index: 0)
        #expect(!l.isSplit)
        #expect(l.focused == "c")
    }

    @Test func closingAHiddenTabKeepsTheSplit() {
        var l = layout(focused: "a")
        l.showBeside("c")
        l.closed("b", remaining: ["a", "c", "d"], index: 1)
        #expect(l.left == "a")
        #expect(l.right == "c")
        #expect(l.focused == "c")
    }

    @Test func closingTheOnlyFocusedTabPicksANeighbour() {
        var l = layout(focused: "b")
        l.closed("b", remaining: ["a", "c"], index: 1)
        #expect(l.focused == "c")
        var last = layout(focused: "c")
        last.closed("c", remaining: ["a", "b"], index: 2)
        #expect(last.focused == "b")
        var only = layout(focused: "a")
        only.closed("a", remaining: [], index: 0)
        #expect(only.focused == nil)
    }

    @Test func steppingSkipsTheOtherVisibleTab() {
        var l = layout(focused: "a")
        l.showBeside("b")          // a | b*
        let tabs = ["a", "b", "c", "d"]
        l.step(by: 1, tabs: tabs)
        #expect(l.focused == "c")
        #expect(l.left == "a")
        l.step(by: 1, tabs: tabs)
        #expect(l.focused == "d")
        l.step(by: 1, tabs: tabs)  // wraps past a, which is showing on the left
        #expect(l.focused == "b")
        l.step(by: -1, tabs: tabs)
        #expect(l.focused == "d")
    }

    @Test func steppingInOnePaneVisitsEveryTab() {
        var l = layout(focused: "d")
        l.step(by: 1, tabs: ["a", "b", "c", "d"])
        #expect(l.focused == "a")
    }

    @Test func toggleTwiceBringsBackTheSamePairAfterSwappingFocus() {
        var l = layout(focused: "a")
        l.showBeside("c")          // a | c*
        l.select("a")              // a* | c
        l.toggleSideBySide(tabs: tabs)
        #expect(!l.isSplit)
        #expect(l.focused == "a")
        l.toggleSideBySide(tabs: tabs)
        #expect(l.left == "a")
        #expect(l.right == "c")
        #expect(l.focused == "a")
    }

    @Test func toggleTwiceKeepsEachTabOnItsSide() {
        var l = layout(focused: "a")
        l.showBeside("c")          // a | c*
        l.toggleSideBySide(tabs: tabs)
        #expect(l.focused == "c")
        l.toggleSideBySide(tabs: tabs)
        #expect(l.left == "a")
        #expect(l.right == "c")
        #expect(l.focused == "c")
    }

    @Test func showBesideWhileSplitReplacesTheOtherSide() {
        var l = layout(focused: "a")
        l.showBeside("c")          // a | c*
        l.showBeside("d")          // the focused c stays on the right, d replaces a
        #expect(l.left == "d")
        #expect(l.right == "c")
        #expect(l.focused == "d")
    }

    @Test func closingThePreviousTabWhileSplitKeepsTheSplit() {
        var l = layout(focused: "a")
        l.select("b")              // previous a
        l.showBeside("c")          // b | c*, previous b
        l.closed("a", remaining: ["b", "c", "d"], index: 0)
        #expect(l.left == "b")
        #expect(l.right == "c")
        #expect(l.focused == "c")
    }
}
