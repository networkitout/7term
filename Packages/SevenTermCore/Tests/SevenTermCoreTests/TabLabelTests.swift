import Testing
@testable import SevenTermCore

@Suite struct TabLabelTests {
    // MARK: Default label (unchanged behaviour)

    @Test func savedHostKeepsItsNameOverTheRemoteTitle() {
        let label = TabLabel(kind: .ssh, savedName: "core-sw1", remoteTitle: "admin@sw1: ~", destination: "admin@10.0.0.1")
        #expect(label.title == "core-sw1")
    }

    @Test func quickConnectionFollowsTheRemoteTitle() {
        var label = TabLabel(kind: .ssh, destination: "admin@10.0.0.1")
        #expect(label.title == "admin@10.0.0.1")
        label.remoteTitle = "admin@sw1: ~"
        #expect(label.title == "admin@sw1: ~")
        label.remoteTitle = ""
        #expect(label.title == "admin@10.0.0.1")
    }

    @Test func remoteTitleIsIgnoredOutsideSSH() {
        let label = TabLabel(kind: .sftp, remoteTitle: "ignored", destination: "me@host")
        #expect(label.title == "me@host · sftp")
    }

    @Test(arguments: [
        (TabLabel.Kind.ssh, "web1"),
        (.sftp, "web1 · sftp"),
        (.files, "web1 · files"),
        (.serial, "web1"),
    ])
    func savedHostSuffixes(kind: TabLabel.Kind, expected: String) {
        #expect(TabLabel(kind: kind, savedName: "web1", destination: "x").title == expected)
    }

    @Test func unsavedSerialShowsBaudRate() {
        #expect(TabLabel(kind: .serial, destination: "cu.usbserial", baudRate: 115200).title == "cu.usbserial · 115200")
        #expect(TabLabel(kind: .serial, destination: "cu.usbserial").title == "cu.usbserial · 9600")
    }

    // MARK: Custom title

    @Test(arguments: TabLabel.Kind.allCases)
    func customTitleReplacesTheWholeLabel(kind: TabLabel.Kind) {
        let label = TabLabel(kind: kind, savedName: "web1", remoteTitle: "shell", destination: "me@web1",
                             baudRate: 9600, customTitle: "web1 – tail logs")
        #expect(label.title == "web1 – tail logs")
        #expect(label.isCustom)
        #expect(label.defaultTitle != label.title)
    }

    @Test func customTitleWinsOverTheRemoteTitleAndClearingRestoresIt() {
        var label = TabLabel(kind: .ssh, remoteTitle: "admin@sw1: ~", destination: "admin@10.0.0.1")
        label.customTitle = "sw1 config"
        #expect(label.title == "sw1 config")
        label.remoteTitle = "admin@sw1: /etc"
        #expect(label.title == "sw1 config")
        label.customTitle = "   "
        #expect(!label.isCustom)
        #expect(label.title == "admin@sw1: /etc")
        label.customTitle = nil
        #expect(label.title == "admin@sw1: /etc")
    }

    @Test func emptyNameRestoresTheDefault() {
        let label = TabLabel(kind: .files, savedName: "nas", destination: "x", customTitle: "")
        #expect(label.title == "nas · files")
        #expect(!label.isCustom)
    }

    @Test func normalizesPastedText() {
        #expect(TabLabel.normalizedCustomTitle("  core\n  switch\t1 \r\n") == "core switch 1")
        #expect(TabLabel.normalizedCustomTitle("a\u{1b}[31mb") == "a [31mb")
        #expect(TabLabel.normalizedCustomTitle("\n\t ") == nil)
        #expect(TabLabel.normalizedCustomTitle(nil) == nil)
    }

    @Test func longNamesAreCut() {
        let long = String(repeating: "x", count: 200)
        #expect(TabLabel.normalizedCustomTitle(long)?.count == TabLabel.maxCustomTitleLength)
    }

    // MARK: Colours

    @Test func noneHasNoColourAndTheRestDo() {
        #expect(TabColor.none.rgb == nil)
        for color in TabColor.allCases where color != .none {
            #expect(color.rgb != nil, "\(color)")
        }
    }

    @Test func rawValuesAreStable() {
        #expect(TabColor.allCases.map(\.rawValue) == ["none", "red", "orange", "yellow", "green", "blue", "purple", "pink"])
        #expect(TabColor(rawValue: "blue") == .blue)
    }

    /// The tab strip is always one of the two dark panels; every colour must
    /// stand out against both. WCAG asks 3:1 for graphics; these clear 4.5:1.
    @Test(arguments: TabColor.allCases.filter { $0 != .none })
    func readableOnBothPanels(color: TabColor) throws {
        let rgb = try #require(color.rgb)
        let redPanel = RGB(hex: "#150F0F")
        let greenPanel = RGB(hex: "#0F1511")
        #expect(rgb.contrastRatio(with: redPanel) >= 4.5)
        #expect(rgb.contrastRatio(with: greenPanel) >= 4.5)
    }

    @Test func contrastRatioMatchesWCAG() {
        let black = RGB(hex: "#000000"), white = RGB(hex: "#FFFFFF")
        #expect(abs(black.contrastRatio(with: white) - 21) < 0.001)
        #expect(abs(white.contrastRatio(with: white) - 1) < 0.001)
    }
}
