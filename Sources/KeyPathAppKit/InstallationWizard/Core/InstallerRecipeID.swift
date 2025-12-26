import Foundation

/// Centralized recipe IDs to avoid string drift across the InstallerEngine stack.
///
/// Keep this minimal: only IDs that are referenced from multiple files should live here.
enum InstallerRecipeID {
    static let installLaunchDaemonServices = "install-launch-daemon-services"
    static let installBundledKanata = "install-bundled-kanata"
}

