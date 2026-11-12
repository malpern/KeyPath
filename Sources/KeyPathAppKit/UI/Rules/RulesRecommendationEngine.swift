import Foundation
import KeyPathRulesCore

struct RuleRecommendation: Equatable {
    let collectionId: UUID
    let reason: String
}

enum RulesRecommendationEngine {
    static func recommendations(from collections: [RuleCollection]) -> [RuleRecommendation] {
        var results: [RuleRecommendation] = []
        var seen = Set<UUID>()
        let byId = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })

        func isEnabled(_ id: UUID) -> Bool {
            byId[id]?.isEnabled == true
        }

        func maybeAdd(_ id: UUID, reason: String) {
            guard let collection = byId[id], !collection.isEnabled else { return }
            guard !seen.contains(id) else { return }
            seen.insert(id)
            results.append(RuleRecommendation(collectionId: id, reason: reason))
        }

        // --- Always-eligible popular starters ---

        maybeAdd(
            RuleCollectionIdentifier.homeRowArrows,
            reason: String(localized: "Arrow keys under your right hand — hold F, press I/J/K/L. No more reaching.")
        )
        maybeAdd(
            RuleCollectionIdentifier.capsLockRemap,
            reason: String(localized: "Most popular: turn Caps Lock into Escape + Hyper for instant shortcuts.")
        )
        maybeAdd(
            RuleCollectionIdentifier.windowSnapping,
            reason: String(localized: "Snap windows to halves, thirds, and corners without reaching for the mouse.")
        )
        maybeAdd(
            RuleCollectionIdentifier.homeRowMods,
            reason: String(localized: "Hold home row keys for modifiers — keep your fingers where they type.")
        )
        maybeAdd(
            RuleCollectionIdentifier.launcher,
            reason: String(localized: "Launch apps and open URLs with a single key tap.")
        )

        // --- Contextual: based on what's already enabled ---

        // Vim user → suggest window snapping and mission control
        if isEnabled(RuleCollectionIdentifier.vimNavigation) {
            maybeAdd(
                RuleCollectionIdentifier.windowSnapping,
                reason: String(localized: "Pairs well with Vim navigation for fast window management.")
            )
            maybeAdd(
                RuleCollectionIdentifier.missionControl,
                reason: String(localized: "Quick access to Mission Control and Exposé alongside Vim keys.")
            )
        }

        // Has caps lock remap → suggest backup caps lock
        if isEnabled(RuleCollectionIdentifier.capsLockRemap) {
            maybeAdd(
                RuleCollectionIdentifier.backupCapsLock,
                reason: String(localized: "Get Caps Lock back via Both Shifts since your Caps Lock key is remapped.")
            )
        }

        // Has window snapping → suggest mission control
        if isEnabled(RuleCollectionIdentifier.windowSnapping) {
            maybeAdd(
                RuleCollectionIdentifier.missionControl,
                reason: String(localized: "Complements window snapping with Mission Control and desktop switching.")
            )
        }

        // Power user (3+ productivity rules) → suggest leader key and layers
        let enabledProductivityCount = collections.filter { $0.category == .productivity && $0.isEnabled }.count
        if enabledProductivityCount >= 3 {
            maybeAdd(
                RuleCollectionIdentifier.leaderKey,
                reason: String(localized: "Organize your shortcuts under a leader key as your setup grows.")
            )
        }

        // Has home row mods → suggest vim navigation
        if isEnabled(RuleCollectionIdentifier.homeRowMods) {
            maybeAdd(
                RuleCollectionIdentifier.vimNavigation,
                reason: String(localized: "Add H/J/K/L arrow navigation — natural complement to home row mods.")
            )
        }

        // Coding-focused: suggest symbol layer and auto-shift
        if isEnabled(RuleCollectionIdentifier.homeRowMods) || isEnabled(RuleCollectionIdentifier.vimNavigation) {
            maybeAdd(
                RuleCollectionIdentifier.symbolLayer,
                reason: String(localized: "Quick access to brackets, operators, and symbols for coding.")
            )
            maybeAdd(
                RuleCollectionIdentifier.autoShiftSymbols,
                reason: String(localized: "Hold letter keys briefly to type their shifted symbol — no Shift key needed.")
            )
        }

        // Has layers → suggest numpad and function layer
        let hasLayers = isEnabled(RuleCollectionIdentifier.symbolLayer)
            || isEnabled(RuleCollectionIdentifier.vimNavigation)
        if hasLayers {
            maybeAdd(
                RuleCollectionIdentifier.numpadLayer,
                reason: String(localized: "A full numpad under your right hand — great alongside other layers.")
            )
            maybeAdd(
                RuleCollectionIdentifier.funLayer,
                reason: String(localized: "Quick access to F-keys and media controls on a dedicated layer.")
            )
        }

        return results
    }
}
