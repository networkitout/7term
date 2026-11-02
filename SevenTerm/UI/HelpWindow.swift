import AppKit
import SwiftUI
import WebKit

/// Help ▸ 7 Term Help: the user guide, bundled with the app so it works
/// offline, in the current theme's colours.
struct HelpView: View {
    @Environment(Appearance.self) private var appearance

    var body: some View {
        let chrome = Chrome.forPalette(id: appearance.paletteID)
        HelpWebView(chrome: chrome)
            .frame(minWidth: 640, minHeight: 480)
            .background(chrome.background)
            .preferredColorScheme(.dark)
    }
}

private struct HelpWebView: NSViewRepresentable {
    let chrome: Chrome

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.css = cssVariables
        if let url = Bundle.main.url(forResource: "help", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.css = cssVariables
        context.coordinator.apply(to: view)
    }

    /// The page's colours as CSS variables, from the app's current theme.
    private var cssVariables: String {
        func hex(_ color: Color) -> String {
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .red
            return String(format: "#%02X%02X%02X",
                          Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
        return "--accent:\(hex(chrome.accent));--bg:\(hex(chrome.background));--panel:\(hex(chrome.panel))"
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var css = ""

        func apply(to view: WKWebView) {
            let script = "document.documentElement.setAttribute('style', '\(css)')"
            view.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            apply(to: webView)
        }

        /// Links within the guide stay here; anything on the web opens in the browser.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if let url = action.request.url, url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
