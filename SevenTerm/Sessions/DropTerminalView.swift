import AppKit
import SwiftTerm

/// SwiftTerm's terminal view, accepting drops: Finder items, and rows dragged
/// from the file browser's host pane. What a drop types is decided by
/// `dropText`; a drop it returns nil for is refused. The text goes through
/// `send(txt:)`, the same path as typing, and Return is never added.
final class DropTerminalView: TerminalView {
    /// The text to type for what's on the pasteboard, or nil to refuse it.
    var dropText: ((NSPasteboard) -> String?)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .string])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropText?(sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let text = dropText?(sender.draggingPasteboard), !text.isEmpty else { return false }
        send(txt: text)
        window?.makeFirstResponder(self)
        return true
    }
}
