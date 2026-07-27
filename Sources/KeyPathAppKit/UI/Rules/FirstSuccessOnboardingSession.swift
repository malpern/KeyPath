import Foundation
import Observation

/// Presentation state for the optional first-success journey.
///
/// Durable keyboard state remains owned by the catalog and rule collections.
/// This model deliberately stores only the moment the person is seeing and
/// whether each guided action has been applied or practiced in this window.
@MainActor
@Observable
final class FirstSuccessOnboardingSession {
    enum Step: Int, CaseIterable, Equatable, Sendable {
        case capsLock
        case hyper
        case launcher
        case rules

        var ordinal: Int {
            rawValue + 1
        }

        var eyebrow: LocalizedStringResource {
            switch self {
            case .capsLock:
                LocalizedStringResource(
                    "FIRST SUCCESS",
                    bundle: #bundle,
                    comment: "Eyebrow above the first onboarding lesson."
                )
            case .hyper:
                LocalizedStringResource(
                    "SECOND WIN",
                    bundle: #bundle,
                    comment: "Eyebrow above the Hyper onboarding lesson."
                )
            case .launcher:
                LocalizedStringResource(
                    "THIRD WIN",
                    bundle: #bundle,
                    comment: "Eyebrow above the Quick Launcher onboarding lesson."
                )
            case .rules:
                LocalizedStringResource(
                    "MAKE IT YOURS",
                    bundle: #bundle,
                    comment: "Eyebrow above the Rules handoff at the end of onboarding."
                )
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .capsLock:
                LocalizedStringResource(
                    "Make a useful key yours",
                    bundle: #bundle,
                    comment: "Title of the Caps Lock to Escape onboarding lesson."
                )
            case .hyper:
                LocalizedStringResource(
                    "Make shortcuts that stay yours",
                    bundle: #bundle,
                    comment: "Title of the Hyper onboarding lesson."
                )
            case .launcher:
                LocalizedStringResource(
                    "Put a favorite app on a letter",
                    bundle: #bundle,
                    comment: "Title of the Quick Launcher onboarding lesson."
                )
            case .rules:
                LocalizedStringResource(
                    "Choose the shortcut you will actually use",
                    bundle: #bundle,
                    comment: "Title of the handoff to the real Quick Launcher controls."
                )
            }
        }

        var summary: LocalizedStringResource {
            switch self {
            case .capsLock:
                LocalizedStringResource(
                    "Reclaim a rarely used key for Escape. A small change. A big upgrade.",
                    bundle: #bundle,
                    comment: "Short motivation for moving Escape to Caps Lock."
                )
            case .hyper:
                LocalizedStringResource(
                    "Hold Caps Lock to prepare a clean shortcut prefix that other apps are unlikely to own.",
                    bundle: #bundle,
                    comment: "Short motivation for assigning Hyper to held Caps Lock."
                )
            case .launcher:
                LocalizedStringResource(
                    "Hold Caps Lock, press a letter you choose, and your app opens.",
                    bundle: #bundle,
                    comment: "Short explanation of the Quick Launcher interaction."
                )
            case .rules:
                LocalizedStringResource(
                    "Quick Launcher is ready. Pick a real app and key in the controls you will use later.",
                    bundle: #bundle,
                    comment: "Explanation of the handoff into the Quick Launcher controls."
                )
            }
        }
    }

    enum LessonPhase: Equatable, Sendable {
        case explaining
        case applying
        case installed
        case practiced
        case blocked

        var isInstalled: Bool {
            self == .installed || self == .practiced
        }
    }

    enum ActionKind: Equatable, Sendable {
        case capsLockEscape
        case hyper
    }

    enum ActionResult: Equatable, Sendable {
        case applied
        case alreadyConfigured
        case savedButNotActive
        case needsRules
        case failed
    }

    var step: Step = .capsLock
    var capsLockPhase: LessonPhase = .explaining
    var hyperPhase: LessonPhase = .explaining
    var isCapsPracticeMenuPresented = false
    var failure: ActionKind?
    var savedButNotActive: ActionKind?

    var isApplying: Bool {
        capsLockPhase == .applying || hyperPhase == .applying
    }

    var currentPhase: LessonPhase {
        switch step {
        case .capsLock: capsLockPhase
        case .hyper: hyperPhase
        case .launcher, .rules: .installed
        }
    }

    func moveForward() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        failure = nil
        savedButNotActive = nil
        step = next
    }

    func moveBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        failure = nil
        savedButNotActive = nil
        step = previous
    }

    func begin(_ action: ActionKind) {
        failure = nil
        savedButNotActive = nil
        switch action {
        case .capsLockEscape: capsLockPhase = .applying
        case .hyper: hyperPhase = .applying
        }
    }

    func finish(_ action: ActionKind, result: ActionResult) {
        switch result {
        case .applied, .alreadyConfigured:
            failure = nil
            savedButNotActive = nil
            switch action {
            case .capsLockEscape: capsLockPhase = .installed
            case .hyper: hyperPhase = .installed
            }
        case .savedButNotActive:
            failure = action
            savedButNotActive = action
            switch action {
            case .capsLockEscape: capsLockPhase = .explaining
            case .hyper: hyperPhase = .explaining
            }
        case .needsRules:
            failure = action
            savedButNotActive = nil
            switch action {
            case .capsLockEscape: capsLockPhase = .blocked
            case .hyper: hyperPhase = .blocked
            }
        case .failed:
            failure = action
            savedButNotActive = nil
            switch action {
            case .capsLockEscape: capsLockPhase = .explaining
            case .hyper: hyperPhase = .explaining
            }
        }
    }

    /// Return presentation state to a safe retry point when the optional tour
    /// is interrupted. The catalog operation remains authoritative if it has
    /// already crossed its durable commit point; a later retry will resolve as
    /// already configured.
    func cancelApplyingAction() {
        if capsLockPhase == .applying {
            capsLockPhase = .explaining
        }
        if hyperPhase == .applying {
            hyperPhase = .explaining
        }
        failure = nil
        savedButNotActive = nil
    }

    func markCapsLockPracticed() {
        guard capsLockPhase.isInstalled else { return }
        capsLockPhase = .practiced
    }
}
