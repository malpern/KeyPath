import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Consolidates onAppear/onDisappear and onReceive notification handlers from LiveKeyboardOverlayView.
struct OverlayNotificationsModifier: ViewModifier {
    let onAppearAction: () -> Void
    let onDisappearAction: () -> Void
    let onLoadCustomRulesState: () -> Void
    let onServiceIssueChange: ([WizardIssue]) -> Void
    let onConfigValidationFailed: (Notification) -> Void
    let onConfigReloadFailed: (Notification) -> Void
    let onConfigReloadRecovered: () -> Void
    let onSwitchToAppRulesTab: () -> Void
    let onSwitchToMapperTab: (Notification) -> Void
    let onMapperKeySelected: (Notification) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                onAppearAction()
            }
            .onDisappear {
                onDisappearAction()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appKeymapsDidChange)) { _ in
                onLoadCustomRulesState()
            }
            // Also reload when global rules change (e.g., via mapper saving an "Everywhere" rule)
            .onReceive(NotificationCenter.default.publisher(for: .ruleCollectionsChanged)) { _ in
                onLoadCustomRulesState()
            }
            // Keep overlay behavior aligned with legacy main-window alerts.
            .onChange(of: MainAppStateController.shared.issues) { _, newIssues in
                onServiceIssueChange(newIssues)
            }
            .onReceive(NotificationCenter.default.publisher(for: .configValidationFailed)) { notification in
                onConfigValidationFailed(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .configReloadFailed)) { notification in
                onConfigReloadFailed(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .configReloadRecovered)) { _ in
                onConfigReloadRecovered()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToAppRulesTab)) { _ in
                onSwitchToAppRulesTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToMapperTab)) { notification in
                onSwitchToMapperTab(notification)
            }
            // Switch to Mapper tab when a key is clicked while in Rules tab
            .onReceive(NotificationCenter.default.publisher(for: .mapperDrawerKeySelected)) { notification in
                onMapperKeySelected(notification)
            }
    }
}
