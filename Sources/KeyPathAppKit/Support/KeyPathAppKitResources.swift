import Foundation

private final class KeyPathAppKitBundleSentinel {}

enum KeyPathAppKitResources {
    static let bundle: Bundle = {
        let mainBundle = Bundle.main
        let codeBundle = Bundle(for: KeyPathAppKitBundleSentinel.self)
        let candidates = [
            mainBundle.resourceURL?.appendingPathComponent("KeyPath_KeyPathAppKit.bundle"),
            codeBundle.resourceURL?.appendingPathComponent("KeyPath_KeyPathAppKit.bundle"),
            mainBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("KeyPath_KeyPathAppKit.bundle"),
            codeBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("KeyPath_KeyPathAppKit.bundle"),
            mainBundle.resourceURL,
            codeBundle.resourceURL,
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return mainBundle
    }()

    static var resourceURL: URL? {
        bundle.resourceURL ?? Bundle.main.resourceURL
    }

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
