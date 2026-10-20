import Foundation

/// Something a rule needs from its environment — the runtime backend, the Mac —
/// rather than from another rule. Kept apart from `RuleCapability`, which is
/// provided by one rule and consumed by another: no rule can provide these.
///
/// Phase 2 of docs/architecture/rules-admission-review.md: inferred from a
/// rule's mappings where possible; declared (`Pack.requires`) only otherwise.
public enum RuleEnvironmentNeed: Hashable, Sendable {
    /// A Kanata keystroke output the backend must be able to emit (e.g. `volu`).
    case emits(key: String)
    /// The rule captures physical Caps Lock as an input.
    case capsLockInput
    /// The rule targets specific keyboards (`macos-dev-names-*`).
    case deviceTargeting
    /// An app that must be installed, by bundle path. Not inferable from rules.
    case externalApp(name: String, path: String)
}
