import AppKit
import Foundation
import KeyPathCore

/// Manages app condition (precondition) selection for per-app key mappings.
///
/// Extracted from MapperViewModel to improve separation of concerns.
/// This component handles:
/// - Running apps discovery for picker
/// - App selection via file picker
/// - App condition state management
@MainActor
public final class AppConditionManager: ObservableObject {
    // MARK: - State

    /// Selected app precondition - rule only applies when this app is frontmost
    @Published public var selectedAppCondition: AppConditionInfo?

    // MARK: - Initialization

    public init() {}

    // MARK: - Running Apps Discovery

    /// Get list of currently running apps for the condition picker
    public func getRunningApps() -> [AppConditionInfo] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        return runningApps.compactMap { app -> AppConditionInfo? in
            // Only include regular apps (not background agents, daemons, etc.)
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  let name = app.localizedName
            else {
                return nil
            }

            // Get app icon
            let icon = app.icon ?? NSWorkspace.shared.icon(forFileType: "app")
            icon.size = NSSize(width: 24, height: 24)

            return AppConditionInfo(
                bundleIdentifier: bundleId,
                displayName: name,
                icon: icon
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - App Selection

    /// Open file picker to select an app for the condition (precondition)
    public func pickAppCondition() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application for this rule's condition"
        panel.prompt = "Select"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                self?.handleSelectedAppCondition(at: url)
            }
        }
    }

    /// Process the selected app condition from a URL
    public func handleSelectedAppCondition(at url: URL) {
        let appName = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        guard let bundleId = bundle?.bundleIdentifier else {
            AppLogger.shared.warn("⚠️ [AppConditionManager] Selected app has no bundle identifier: \(url)")
            return
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 24, height: 24)

        let conditionInfo = AppConditionInfo(
            bundleIdentifier: bundleId,
            displayName: appName,
            icon: icon
        )

        selectedAppCondition = conditionInfo
        AppLogger.shared.log("🎯 [AppConditionManager] Selected app condition: \(appName) (\(bundleId))")
    }

    /// Set app condition from an AppConditionInfo (e.g., from running apps picker)
    public func setCondition(_ condition: AppConditionInfo) {
        selectedAppCondition = condition
        AppLogger.shared.log("🎯 [AppConditionManager] Set app condition: \(condition.displayName) (\(condition.bundleIdentifier))")
    }

    // MARK: - Clear

    /// Clear the app condition
    public func clearAppCondition() {
        selectedAppCondition = nil
        AppLogger.shared.log("🎯 [AppConditionManager] Cleared app condition")
    }

    // MARK: - Reset

    /// Reset all state
    public func reset() {
        selectedAppCondition = nil
    }

    // MARK: - Convenience

    /// Whether an app condition is set
    public var hasCondition: Bool {
        selectedAppCondition != nil
    }
}
