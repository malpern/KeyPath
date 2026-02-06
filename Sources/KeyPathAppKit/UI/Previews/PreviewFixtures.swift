#if DEBUG
    import Foundation
    import KeyPathCore
    import KeyPathWizardCore

    /// Shared deterministic fixtures used by SwiftUI previews.
    enum PreviewFixtures {
        static let customRulesPopulated: [CustomRule] = [
            CustomRule(title: "Home Row Down", input: "j", output: "down", isEnabled: true, notes: "Vim navigation"),
            CustomRule(title: "Home Row Up", input: "k", output: "up", isEnabled: true),
            CustomRule(title: "Legacy Escape", input: "caps", output: "esc", isEnabled: false)
        ]

        static let appKeymapsPopulated: [AppKeymap] = [
            AppKeymap(
                mapping: AppKeyMapping(bundleIdentifier: "com.apple.Safari", displayName: "Safari", virtualKeyName: "vk_safari"),
                overrides: [
                    AppKeyOverride(inputKey: "j", outputAction: "down"),
                    AppKeyOverride(inputKey: "k", outputAction: "up")
                ]
            ),
            AppKeymap(
                mapping: AppKeyMapping(bundleIdentifier: "com.openai.chat", displayName: "ChatGPT", virtualKeyName: "vk_chatgpt"),
                overrides: [
                    AppKeyOverride(inputKey: "h", outputAction: "left")
                ]
            )
        ]

        static var noIssues: [WizardIssue] {
            []
        }

        static func permissionIssue(_ permission: PermissionRequirement, title: String, description: String) -> WizardIssue {
            WizardIssue(
                identifier: .permission(permission),
                severity: .critical,
                category: .permissions,
                title: title,
                description: description,
                autoFixAction: nil,
                userAction: "Grant permission in System Settings"
            )
        }
    }
#endif
