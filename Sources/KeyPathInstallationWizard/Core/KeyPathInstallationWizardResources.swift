import Foundation

private final class KeyPathInstallationWizardBundleSentinel {}

/// Resolves this target's SwiftPM resource bundle from both local builds and
/// KeyPath's signed macOS app layout. Packaged bundles live in
/// `Contents/Resources`; SwiftPM's generated `Bundle.module` accessor does not
/// search there when a command-line executable is wrapped in an `.app`.
enum KeyPathInstallationWizardResources {
    static let bundle = resolveBundle(
        mainBundle: .main,
        codeBundle: Bundle(for: KeyPathInstallationWizardBundleSentinel.self)
    )

    static func resolveBundle(mainBundle: Bundle, codeBundle: Bundle) -> Bundle {
        let bundleName = "KeyPath_KeyPathInstallationWizard.bundle"
        let candidates = [
            mainBundle.resourceURL?.appendingPathComponent(bundleName),
            codeBundle.resourceURL?.appendingPathComponent(bundleName),
            mainBundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
            codeBundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName),
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
}
