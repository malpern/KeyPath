import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("KeyPath_KeyPath.bundle").path
        let buildPath = "/Volumes/FlashGordon/Dropbox/code/KeyPath/.build-karabiner/arm64-apple-macosx/debug/KeyPath_KeyPath.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}
