import SwiftUI
import WebKit

/// Why a help article failed to load, used to tailor the offline/404 fallback copy.
enum HelpLoadError: Equatable {
    /// The device appears to be offline or the host is unreachable.
    case offline
    /// The page loaded but the server returned a not-found / error status.
    case notFound
    /// Any other navigation failure.
    case generic

    var title: String {
        switch self {
        case .offline: "Can't reach the help site"
        case .notFound: "This guide isn't available"
        case .generic: "Couldn't load this guide"
        }
    }

    var message: String {
        switch self {
        case .offline:
            "KeyPath help lives online. Check your internet connection and try again."
        case .notFound:
            "This guide may have moved or isn't published yet. Try opening it in your browser, or report it so we can fix the link."
        case .generic:
            "Something went wrong loading this guide. Try again, or open it in your browser."
        }
    }
}

/// Loads a help article from the KeyPath website, with an offline/404 fallback.
struct WebHelpView: View {
    /// Issues URL for the "Report a broken link" fallback (degenerate file:// fallback avoids a force-unwrap).
    private static let reportIssueURL: URL = .init(string: "https://github.com/malpern/KeyPath/issues")
        ?? URL(fileURLWithPath: "/")

    let url: URL
    var onHelpLinkClicked: ((String) -> Void)?

    @State private var loadError: HelpLoadError?
    /// Bumped to ask the underlying web view to reload the current URL.
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            WebHelpWebView(
                url: url,
                reloadToken: reloadToken,
                onHelpLinkClicked: onHelpLinkClicked,
                onLoadError: { loadError = $0 },
                onLoadSucceeded: { loadError = nil }
            )

            if let loadError {
                fallbackView(loadError)
            }
        }
        // Reset the error when navigating to a different article.
        .onChange(of: url) { _, _ in loadError = nil }
    }

    private func fallbackView(_ error: HelpLoadError) -> some View {
        VStack(spacing: 14) {
            Image(systemName: error == .offline ? "wifi.slash" : "questionmark.folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(error.title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(error.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 10) {
                Button {
                    loadError = nil
                    reloadToken += 1
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("help-fallback-retry-button")

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("help-fallback-open-browser-button")
            }
            .padding(.top, 4)

            if error == .notFound {
                Link("Report a broken link", destination: Self.reportIssueURL)
                    .font(.caption)
                    .accessibilityIdentifier("help-fallback-report-link")
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityIdentifier("help-fallback-view")
    }
}

/// The WKWebView backing `WebHelpView`. Reports navigation failures and error
/// HTTP statuses so the parent can render a fallback instead of a blank page.
private struct WebHelpWebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int
    var onHelpLinkClicked: ((String) -> Void)?
    var onLoadError: ((HelpLoadError) -> Void)?
    var onLoadSucceeded: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onHelpLinkClicked: onHelpLinkClicked,
            onLoadError: onLoadError,
            onLoadSucceeded: onLoadSucceeded
        )
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
        context.coordinator.lastReloadToken = reloadToken
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHelpLinkClicked = onHelpLinkClicked
        context.coordinator.onLoadError = onLoadError
        context.coordinator.onLoadSucceeded = onLoadSucceeded

        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            webView.load(URLRequest(url: url))
        } else if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onHelpLinkClicked: ((String) -> Void)?
        var onLoadError: ((HelpLoadError) -> Void)?
        var onLoadSucceeded: (() -> Void)?
        var currentURL: URL?
        var lastReloadToken = 0

        init(
            onHelpLinkClicked: ((String) -> Void)?,
            onLoadError: ((HelpLoadError) -> Void)?,
            onLoadSucceeded: (() -> Void)?
        ) {
            self.onHelpLinkClicked = onHelpLinkClicked
            self.onLoadError = onLoadError
            self.onLoadSucceeded = onLoadSucceeded
        }

        func webView(
            _: WKWebView,
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
               url.path.hasPrefix("/KeyPath/guides/")
            {
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

        /// Detect HTTP error statuses (e.g. a 404 for an unpublished guide) on the main frame.
        func webView(
            _: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            if navigationResponse.isForMainFrame,
               let http = navigationResponse.response as? HTTPURLResponse,
               http.statusCode >= 400
            {
                onLoadError?(http.statusCode == 404 ? .notFound : .generic)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            onLoadSucceeded?()
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        private static let offlineErrorCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorDNSLookupFailed
        ]

        private func reportFailure(_ error: Error) {
            let nsError = error as NSError
            // Ignore cancellations from our own policy decisions (404 handling, internal links).
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            // WebKitErrorDomain 102 = frame load interrupted by a policy change (our .cancel calls).
            if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }

            if nsError.domain == NSURLErrorDomain, Self.offlineErrorCodes.contains(nsError.code) {
                onLoadError?(.offline)
            } else {
                onLoadError?(.generic)
            }
        }
    }
}
