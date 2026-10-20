// Compiled with the production Help view/store by test-offline-help.sh.
import AppKit
import SwiftUI
import WebKit

@MainActor
private struct HelpPreview: View {
    let store: OfflineHelpStore
    @State private var resource = "tap-hold"
    var body: some View {
        VStack {
            HStack {
                ForEach(["tap-hold", "installation-wizard", "privacy"], id: \.self) { name in
                    Button(name) { resource = name }.accessibilityIdentifier("qa-help-\(name)")
                }
            }.padding(8)
            WebHelpView(url: URL(string: "https://malpern.github.io/KeyPath/guides/\(resource)/")!,
                        contentStore: store, onHelpLinkClicked: { resource = $0 })
                .id(resource)
        }
    }
}

@MainActor
private final class OfflineProbe: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 850, height: 650), configuration: {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        return config
    }())
    var pending: CheckedContinuation<String, Error>?

    func run(root: URL, report: URL) async {
        do {
            web.navigationDelegate = self
            let rules = """
            [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
            """
            let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "KeyPathOfflineHelpQA", encodedContentRuleList: rules)
            if let list { web.configuration.userContentController.add(list) }
            var pages = [[String: Any]]()
            let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("articles"), includingPropertiesForKeys: nil)
            for file in files.sorted(by: { $0.path < $1.path }) where file.pathExtension == "html" {
                let result: String = try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    web.loadFileURL(file, allowingReadAccessTo: root)
                }
                let object = try JSONSerialization.jsonObject(with: Data(result.utf8)) as! [String: Any]
                try JSONSerialization.data(withJSONObject: ["article": file.lastPathComponent, "result": object], options: [.prettyPrinted])
                    .write(to: report.deletingLastPathComponent().appendingPathComponent("last-page.json"))
                let images = object["images"] as! [[String: Any]]
                let resources = object["resources"] as! [String]
                guard (object["textLength"] as? Int ?? 0) > 0,
                      (object["background"] as? String)?.replacingOccurrences(of: " ", with: "") == "rgb(250,246,240)",
                      images.allSatisfy({ ($0["width"] as? Int ?? 0) > 0 }),
                      resources.allSatisfy({ !$0.hasPrefix("http") }) else { throw HelpContentError.invalidPackage }
                pages.append(["article": file.lastPathComponent, "images": images.count, "passed": true])
            }
            try JSONSerialization.data(
                withJSONObject: ["passed": true, "articles": pages, "network": "All HTTP(S) blocked; fresh nonpersistent WebKit data store"],
                options: [.prettyPrinted, .sortedKeys]
            ).write(to: report)
            print("PASS: \(pages.count) offline articles, local CSS and every image loaded")
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "error": String(describing: error)]).write(to: report)
            print("FAIL: \(error)")
        }
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        let script = """
        JSON.stringify({textLength: document.body.innerText.length,
          background: getComputedStyle(document.body).backgroundColor,
          images: Array.from(document.images).map(i => ({width:i.naturalWidth,src:i.src})),
          resources: performance.getEntriesByType('resource').map(r => r.name)})
        """
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            guard let continuation = self?.pending else { return }
            self?.pending = nil
            switch result {
            case let .success(value):
                if let string = value as? String { continuation.resume(returning: string) }
                else { continuation.resume(throwing: HelpContentError.invalidPackage) }
            case let .failure(error): continuation.resume(throwing: error)
            }
        }
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        pending?.resume(throwing: error)
        pending = nil
    }
}

@main
@MainActor
struct OfflineHelpQA {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let root = Bundle.main.resourceURL!.appendingPathComponent("OfflineHelp")
        let report = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("offline-report.json")
        let store = OfflineHelpStore(bundledRoot: root, storageRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                     appVersion: "1.0", updateBase: URL(string: "https://offline.invalid/")!,
                                     fetch: { _ in throw URLError(.notConnectedToInternet) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "KeyPath Help — Offline QA"
        window.contentView = NSHostingView(rootView: HelpPreview(store: store))
        window.center(); window.makeKeyAndOrderFront(nil)
        let menu = NSMenu(); let item = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit Offline QA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); app.mainMenu = menu
        app.activate(ignoringOtherApps: true)
        let probe = OfflineProbe()
        Task { await probe.run(root: root, report: report) }
        app.run()
    }
}
