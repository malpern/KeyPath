import Foundation

/// Shared, user-facing language for timing controls.
///
/// Keep this focused on what a person experiences rather than the renderer's
/// serialized field names. The same stored timeout can have a different clock
/// and outcome in another dual-role variant.
enum TimingCopy {
    enum DualRoleVariant: CaseIterable {
        case basic
        case holdOnOtherKeyPress
        case holdOnOtherKeyRelease
        case customTapKeys
        case releaseOrder
        case oppositeHandPress
        case oppositeHandRelease

        var primaryWindowLabel: String {
            switch self {
            case .releaseOrder:
                "Typing grace period"
            default:
                "Repeat-tap window"
            }
        }

        var primaryWindowExplanation: String {
            switch self {
            case .releaseOrder:
                "After you press this key, another key released during this period makes it a hold."
            default:
                "After you press this key, another key can still change how it resolves during this period."
            }
        }

        var usesHoldActivationDelay: Bool {
            switch self {
            case .releaseOrder, .oppositeHandPress, .oppositeHandRelease:
                false
            default:
                true
            }
        }
    }

    static let holdActivationDelay = "Hold activation delay"
    static let holdActivationDelayExplanation = "How long to hold this key before its hold action activates."
    static let leaderHoldDelay = LocalizedStringResource(
        "Leader hold delay",
        bundle: #bundle,
        comment: "Label for the setting that controls how long the Leader key must be held."
    )
    static let leaderHoldDelayExplanation = LocalizedStringResource(
        "How long to hold the Leader key before KeyPath shows the Shortcut List. Default is Long (300 ms). Medium (200 ms) matches previous behavior.",
        bundle: #bundle,
        comment: "Explains the Leader hold delay and its default and compatibility presets."
    )
    static let customLeaderHoldDelayAccessibilityLabel = LocalizedStringResource(
        "Custom Leader hold delay in milliseconds",
        bundle: #bundle,
        comment: "Accessibility label for the custom Leader hold delay field."
    )
    static let multiTapWindow = "Multi-tap window"
    static let multiTapWindowExplanation = "After every tap, the window starts again. When it expires, KeyPath resolves the tap count."
    static let activateHoldOnOtherKeyPress = "Activate hold when another key is pressed"
    static let activateHoldOnOtherKeyRelease = "Activate hold after another key is released"

    static func dualRoleVariant(
        activateHoldOnOtherKey: Bool,
        quickTap: Bool,
        useReleaseOrder: Bool
    ) -> DualRoleVariant {
        if useReleaseOrder { return .releaseOrder }
        if activateHoldOnOtherKey { return .holdOnOtherKeyPress }
        if quickTap { return .holdOnOtherKeyRelease }
        return .basic
    }

    static func dualRoleVariant(for holdBehavior: AdvancedBehaviorManager.HoldBehaviorType) -> DualRoleVariant {
        switch holdBehavior {
        case .basic: .basic
        case .triggerEarly: .holdOnOtherKeyPress
        case .quickTap: .holdOnOtherKeyRelease
        case .customKeys: .customTapKeys
        }
    }

    static func showsHoldActivationDelay(
        for variant: DualRoleVariant,
        isEditingTapDance: Bool
    ) -> Bool {
        !isEditingTapDance && variant.usesHoldActivationDelay
    }
}
