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

private struct MarkdownWebView: NSViewRepresentable {
    let resource: String
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator { Coordinator(colorScheme: colorScheme) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        Self.loadResource(resource, into: webView, isDark: colorScheme == .dark)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.colorScheme = colorScheme
        let className = colorScheme == .dark ? "dark" : ""
        webView.evaluateJavaScript("document.body.className = '\(className)'", completionHandler: nil)
    }

    static func loadResource(_ resource: String, into webView: WKWebView, isDark: Bool) {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8)
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
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var colorScheme: ColorScheme

        init(colorScheme: ColorScheme) {
            self.colorScheme = colorScheme
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
                MarkdownWebView.loadResource(resource, into: webView, isDark: colorScheme == .dark)
                decisionHandler(.cancel)
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}
