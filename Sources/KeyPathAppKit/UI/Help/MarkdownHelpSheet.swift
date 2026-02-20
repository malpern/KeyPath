import SwiftUI
import WebKit

/// A reusable sheet that renders a bundled markdown file via WKWebView.
struct MarkdownHelpSheet: View {
    let resource: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header bar — matches the pattern from the old HomeRowModsHelpView
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("markdown-help-close-button")
                .accessibilityLabel("Close")
            }
            .padding()

            Divider()

            MarkdownWebView(resource: resource, colorScheme: colorScheme)
        }
        .frame(width: 750, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - WKWebView wrapper

struct MarkdownWebView: NSViewRepresentable {
    let resource: String
    let colorScheme: ColorScheme
    /// Called when a `keypath-help://` cross-link is clicked, passing the resource name.
    var onHelpLinkClicked: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(colorScheme: colorScheme, onHelpLinkClicked: onHelpLinkClicked)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Use the parchment background color to avoid white flash and
        // ensure mix-blend-mode: multiply on divider images works correctly.
        let parchment = NSColor(red: 0.98, green: 0.965, blue: 0.94, alpha: 1.0)
        webView.underPageBackgroundColor = parchment
        webView.setValue(false, forKey: "drawsBackground")

        Self.loadResource(resource, into: webView, isDark: colorScheme == .dark)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.colorScheme = colorScheme
        context.coordinator.onHelpLinkClicked = onHelpLinkClicked
        let isDark = colorScheme == .dark
        let className = isDark ? "dark" : ""
        webView.evaluateJavaScript("document.body.className = '\(className)'", completionHandler: nil)
        // Match WKWebView background to the active theme to prevent flash on scheme change
        webView.underPageBackgroundColor = isDark
            ? NSColor(red: 0.165, green: 0.141, blue: 0.125, alpha: 1.0) // #2a2420
            : NSColor(red: 0.98, green: 0.965, blue: 0.94, alpha: 1.0)   // #faf6f0

        // Reload content if the resource changed
        if context.coordinator.currentResource != resource {
            context.coordinator.currentResource = resource
            Self.loadResource(resource, into: webView, isDark: colorScheme == .dark)
        }
    }

    static func loadResource(_ resource: String, into webView: WKWebView, isDark: Bool) {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8),
              let resourceDir = Bundle.module.resourceURL
        else {
            let fallback = MarkdownToHTML.wrapInHTMLDocument(
                body: "<p>Could not load help content.</p>",
                isDark: isDark
            )
            webView.loadHTMLString(fallback, baseURL: nil)
            return
        }

        let bodyHTML = MarkdownToHTML.convert(markdown)
        let fullHTML = MarkdownToHTML.wrapInHTMLDocument(body: bodyHTML, isDark: isDark)

        // Write HTML to a temp file inside the resource bundle directory so
        // loadFileURL can grant read access to sibling images via
        // allowingReadAccessTo:.  loadHTMLString(baseURL:) does NOT grant
        // WKWebView file-read access, which breaks <img src="...png">.
        let tempHTML = resourceDir.appendingPathComponent("_help_\(resource).html")
        do {
            try fullHTML.write(to: tempHTML, atomically: true, encoding: .utf8)
            webView.loadFileURL(tempHTML, allowingReadAccessTo: resourceDir)
        } catch {
            // Fallback: if we can't write (e.g. read-only bundle), use loadHTMLString
            webView.loadHTMLString(fullHTML, baseURL: resourceDir)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var colorScheme: ColorScheme
        var onHelpLinkClicked: ((String) -> Void)?
        var currentResource: String = ""

        init(colorScheme: ColorScheme, onHelpLinkClicked: ((String) -> Void)?) {
            self.colorScheme = colorScheme
            self.onHelpLinkClicked = onHelpLinkClicked
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "keypath-help", let resource = url.host {
                if let callback = onHelpLinkClicked {
                    callback(resource)
                } else {
                    MarkdownWebView.loadResource(resource, into: webView, isDark: colorScheme == .dark)
                }
                decisionHandler(.cancel)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}
