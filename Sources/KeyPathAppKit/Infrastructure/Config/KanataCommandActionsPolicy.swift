import Foundation
import KeyPathCore

/// Policy for whether KeyPath-written configs grant kanata permission to execute
/// shell commands (`danger-enable-cmd yes` in `defcfg`).
///
/// KeyPath itself never emits `(cmd ...)` actions: launchers, URL/folder/script
/// actions, system actions, notifications, and layer signals are all
/// `(push-msg ...)` TCP messages executed app-side by `ActionDispatcher`, and
/// kanata does not gate `push-msg` behind `danger-enable-cmd`. The flag only
/// matters for hand-written `(cmd ...)` actions in a user-edited config — so it
/// defaults to OFF. Kanata runs as root under the LaunchDaemon; an unused grant
/// of arbitrary command execution is pure attack surface.
///
/// Users who hand-wrote `(cmd ...)` actions before this default changed are
/// grandfathered: the first load of a pre-existing config that *uses* cmd
/// actions records the policy as enabled, so regeneration keeps emitting the
/// header line. The presence of `danger-enable-cmd yes` alone does NOT
/// grandfather — every legacy generated config carries that line (it used to be
/// hardcoded) without using `(cmd ...)`.
///
/// Backed by `UserDefaults` directly (not `@MainActor`) because config
/// generation runs off the main actor.
public enum KanataCommandActionsPolicy {
    static let defaultsKey = "KeyPath.Security.ConfigCommandActionsEnabled"

    /// Whether generated configs should include `danger-enable-cmd yes`.
    /// Defaults to `false` when the user has never decided.
    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    /// True once the user (or the grandfathering migration) has recorded a decision.
    public static func hasRecordedDecision(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) != nil
    }

    public static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
        AppLogger.shared.log(
            "🔐 [CommandActionsPolicy] Config command actions \(enabled ? "ENABLED" : "DISABLED")"
        )
    }

    /// True when the config *uses* command-execution actions, as opposed to merely
    /// carrying the `danger-enable-cmd` defcfg line. Matches the kanata action
    /// family that `danger-enable-cmd` gates — `cmd`, `cmd-log`,
    /// `cmd-output-keys`, and the clipboard cmd variants — all of which appear as
    /// `(cmd…` at use sites. `danger-enable-cmd yes` itself never matches (no
    /// opening paren before `cmd`).
    public static func configUsesCommandActions(_ content: String) -> Bool {
        content.range(of: #"\(\s*cmd[\s)-]"#, options: .regularExpression) != nil
    }

    /// One-time migration run when an existing config is first loaded after the
    /// default flipped to OFF. Records `true` when the config actually uses
    /// `(cmd ...)` actions (preserving the user's mappings across regeneration)
    /// and `false` otherwise. No-op once a decision has been recorded, so a later
    /// explicit Settings choice is never overridden.
    public static func grandfatherIfNeeded(
        configContent: String,
        defaults: UserDefaults = .standard
    ) {
        guard !hasRecordedDecision(defaults: defaults) else { return }
        let usesCommands = configUsesCommandActions(configContent)
        setEnabled(usesCommands, defaults: defaults)
        if usesCommands {
            AppLogger.shared.log(
                "🔐 [CommandActionsPolicy] Existing config uses (cmd ...) actions — grandfathering command actions ON"
            )
        }
    }
}
