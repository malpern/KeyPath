import KeyPathCore
import SwiftUI

// MARK: - Launcher Welcome

extension LiveKeyboardOverlayView {
    /// Check if welcome should be shown for current build
    var hasSeenLauncherWelcomeForCurrentBuild: Bool {
        let currentBuild = BuildInfo.current().date
        return launcherWelcomeSeenForBuild == currentBuild
    }

    /// Mark welcome as seen for current build
    func markLauncherWelcomeAsSeen() {
        launcherWelcomeSeenForBuild = BuildInfo.current().date
    }

    /// Check if launcher welcome dialog should be shown
    func checkLauncherWelcome() {
        guard !hasSeenLauncherWelcomeForCurrentBuild else { return }

        Task {
            // Load the launcher config to pass to welcome dialog
            let collections = await services.ruleCollectionStore.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig
            {
                await MainActor.run {
                    pendingLauncherConfig = config
                    showLauncherWelcomeWindow()
                }
            }
        }
    }

    /// Show the launcher welcome dialog as an independent centered window
    func showLauncherWelcomeWindow() {
        guard let config = pendingLauncherConfig else { return }

        LauncherWelcomeWindowController.show(
            config: Binding(
                get: { [self] in pendingLauncherConfig ?? config },
                set: { [self] in pendingLauncherConfig = $0 }
            ),
            onComplete: { [self] finalConfig, _ in
                handleLauncherWelcomeComplete(finalConfig)
            },
            onDismiss: { [self] in
                // User closed without completing - still mark as seen for this build
                markLauncherWelcomeAsSeen()
                pendingLauncherConfig = nil
            }
        )
    }

    /// Handle launcher welcome dialog completion
    func handleLauncherWelcomeComplete(_ finalConfig: LauncherGridConfig) {
        var updatedConfig = finalConfig
        updatedConfig.hasSeenWelcome = true
        markLauncherWelcomeAsSeen()

        // Save the updated config
        Task {
            let collections = await services.ruleCollectionStore.loadCollections()
            if var launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                launcherCollection.configuration = .launcherGrid(updatedConfig)
                // Update the collections array and save
                var allCollections = collections
                if let index = allCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                    allCollections[index] = launcherCollection
                    try? await services.ruleCollectionStore.saveCollections(allCollections)
                }
            }
        }

        pendingLauncherConfig = nil
    }
}
