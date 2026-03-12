import AppKit

enum KindaVimDetector {
    static let bundleIdentifier = "mo.com.sleeplessmind.kindaVim"
    static let downloadURL = URL(string: "https://kindavim.app")!

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) != nil
    }
}
