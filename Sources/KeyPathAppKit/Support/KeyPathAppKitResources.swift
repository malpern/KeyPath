import Foundation

private final class KeyPathAppKitBundleSentinel {}

/// Resolves this target's SwiftPM resources without using `Bundle.module`.
/// KeyPath wraps a SwiftPM command-line executable in a signed macOS `.app`, so
/// target bundles live in `Contents/Resources` rather than beside the app root
/// where SwiftPM's generated accessor searches.
enum KeyPathAppKitResources {
    static let bundle = resolveBundle(
        mainBundle: .main,
        codeBundle: Bundle(for: KeyPathAppKitBundleSentinel.self)
    )

    static func resolveBundle(mainBundle: Bundle, codeBundle: Bundle) -> Bundle {
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
    }

    static var resourceURL: URL? {
        bundle.resourceURL ?? Bundle.main.resourceURL
    }

    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
}
