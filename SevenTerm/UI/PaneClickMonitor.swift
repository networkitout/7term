import AppKit
import SwiftUI

/// Reports a mouse click anywhere inside its frame without taking it, so the
/// terminal or list underneath still gets the click. Terminals are AppKit
/// views that consume clicks before SwiftUI gestures see them, hence a local
/// event monitor rather than a tap gesture.
struct PaneClickMonitor: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onClick = onClick
    }

    final class MonitorView: NSView {
        var onClick: (() -> Void)?
        /// Only touched on the main thread; nonisolated so deinit can remove it.
        nonisolated(unsafe) private var monitor: Any?

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    MainActor.assumeIsolated { self?.noticeClick(event) }
                    return event
                }
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func noticeClick(_ event: NSEvent) {
            // A click refused because a sheet is open mustn't move the focus.
            guard let window, event.window === window, window.attachedSheet == nil else { return }
            if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
        }

        // Never the target of a click itself.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
