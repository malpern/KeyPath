import Foundation
import KeyPathCore

/// The one sentence for "this configuration cannot run" (phase 4e). Startup,
/// reload, the save gate and the setup screen all render the bridge's result
/// here, with the admission engine's attribution in front when it has one —
/// so the message names the rule, not just the key the validator tripped on.
enum SessionConfigurationRefusal {
    static let preserved = "existing rules were preserved."

    /// `attribution`: the engine's blocking sentences for the rules the
    /// profile was generated from, e.g. "Louder sends volu, which the current
    /// backend can't send." Empty when the engine found nothing (an edit made
    /// outside KeyPath, or a limit only the validator knows).
    static func message(_ result: KanataHostBridgeValidationResult, attribution: [String] = []) -> String? {
        switch result {
        case .valid:
            nil
        case let .invalid(reason):
            attribution.isEmpty
                ? "This configuration cannot run in the driverless session: \(reason). Edit the configuration and retry; \(preserved)"
                : "This configuration cannot run in the driverless session. \(attribution.joined(separator: " ")) "
                + "Turn that rule off or change it, then retry; \(preserved) (Validator: \(reason).)"
        case let .unavailable(reason):
            "Driverless configuration validation is unavailable: \(reason). Retry once validation is available; \(preserved)"
        }
    }
}
