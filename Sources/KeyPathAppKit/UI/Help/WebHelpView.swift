import SwiftUI
import WebKit

/// Loads a help article from the KeyPath website via WKWebView.
struct WebHelpView: NSViewRepresentable {
    let url: URL
    var onHelpLinkClicked: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onHelpLinkClicked: onHelpLinkClicked)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        context.coordinator.currentURL = url
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHelpLinkClicked = onHelpLinkClicked
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onHelpLinkClicked: ((String) -> Void)?
        var currentURL: URL?

        init(onHelpLinkClicked: ((String) -> Void)?) {
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

            // Internal help cross-links: help:resource-name or /guides/resource-name/
            if url.scheme == "help", let resource = url.host {
                onHelpLinkClicked?(resource)
                decisionHandler(.cancel)
                return
            }

            if let host = url.host,
               host.contains("malpern.github.io"),
               url.path.hasPrefix("/KeyPath/guides/") {
                let resource = url.path
                    .replacingOccurrences(of: "/KeyPath/guides/", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !resource.isEmpty {
                    onHelpLinkClicked?(resource)
                    decisionHandler(.cancel)
                    return
                }
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}

