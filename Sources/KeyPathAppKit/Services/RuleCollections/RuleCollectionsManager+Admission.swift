import Foundation
import KeyPathCore
import KeyPathRulesCore

/// What the admission engine says about one change the user is about to
/// make, in words (phase 4d). Conflicts are not here: they keep their
/// dialog (`conflictInfo`, `onConflictResolution`). This covers what the
/// backend cannot emit, a foreign Caps Lock owner, and the reserved Caps
/// intermediate — which is moved, not refused, and only mentioned.
struct AdmissionReview: Equatable, Sendable {
    let verdicts: [AdmissionVerdict]
    /// The first blocking verdict as a sentence; nil when the change may proceed.
    let refusal: String?
    /// Automatic resolutions worth one line afterwards ("Caps Lock will use F19 instead.").
    let notes: [String]

    static let clear = AdmissionReview(verdicts: [], refusal: nil, notes: [])
}

extension RuleCollectionsManager {
    /// The engine's input for the current rules plus the live environment.
    func admissionState(collections: [RuleCollection], customRules: [CustomRule],
                        installedPackIDs: Set<String> = []) -> AdmissionEngine.State
    {
        AdmissionEngine.State(collections: collections, customRules: customRules,
                              leaderKey: preferencesService.leaderKeyPreference,
                              installedPackIDs: installedPackIDs, environment: admissionEnvironment)
    }

    /// Review saving `rule` (enabled) alongside everything else that is on.
    func reviewAdmission(forProposed rule: CustomRule, profile: BackendCapabilityProfile = .shared) -> AdmissionReview {
        var proposed = rule
        proposed.isEnabled = true
        let others = customRules.filter { $0.id != rule.id }
        let state = admissionState(collections: ruleCollections, customRules: others + [proposed])
        return review(subject: .customRule(rule.id), state: state, profile: profile)
    }

    /// Review turning `collection` on alongside everything else that is on.
    func reviewAdmission(forEnabling collection: RuleCollection, profile: BackendCapabilityProfile = .shared) -> AdmissionReview {
        var proposed = collection
        proposed.isEnabled = true
        let others = ruleCollections.filter { $0.id != collection.id }
        let state = admissionState(collections: others + [proposed], customRules: customRules)
        return review(subject: .collection(collection.id), state: state, profile: profile)
    }

    private func review(subject: AdmissionSubject, state: AdmissionEngine.State,
                        profile: BackendCapabilityProfile) -> AdmissionReview
    {
        let name = Self.nameLookup(state)
        let verdicts = AdmissionEngine.evaluate(state, profile: profile).filter { verdict in
            guard verdict.subject == subject else { return false }
            if case .conflict = verdict.reason { return false }
            return true
        }
        guard !verdicts.isEmpty else { return .clear }
        let refusal = verdicts.first { $0.severity == .blocking }
            .map { AdmissionVerdictPresenter.present($0, name: name).explanation }
        let notes = verdicts.filter { $0.severity == .automatic }
            .map { AdmissionVerdictPresenter.present($0, name: name).explanation }
        return AdmissionReview(verdicts: verdicts, refusal: refusal, notes: notes)
    }
}
