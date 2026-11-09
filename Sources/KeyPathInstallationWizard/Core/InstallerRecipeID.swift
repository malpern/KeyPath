import Foundation

/// Centralized recipe IDs to avoid string drift across the InstallerEngine stack.
///
/// Keep this minimal: only IDs that are referenced from multiple files should live here.
public enum InstallerRecipeID {
    public static let startSessionRuntime = "start-session-runtime"
    public static let synchronizeConfigPaths = "synchronize-config-paths"
    public static let verifyPostconditions = "verify-postconditions"
}
