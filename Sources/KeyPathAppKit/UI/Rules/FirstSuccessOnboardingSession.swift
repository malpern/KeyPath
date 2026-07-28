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
                    "Your keyboard has room to grow",
                    bundle: #bundle,
                    comment: "Title of the Rules discovery handoff at the end of onboarding."
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
                    "You have the pattern: tap, hold, then combine. Rules is where you can discover what else KeyPath can make yours.",
                    bundle: #bundle,
                    comment: "Explanation of the Rules discovery handoff after the guided wins are complete."
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
        case launcherShortcut
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
    var launcherPhase: LessonPhase = .explaining
    var isCapsPracticeMenuPresented = false
    var failure: ActionKind?
    var savedButNotActive: ActionKind?

    var isApplying: Bool {
        capsLockPhase == .applying || hyperPhase == .applying || launcherPhase == .applying
    }

    var isLauncherChoiceEditable: Bool {
        guard savedButNotActive != .launcherShortcut else { return false }
        return launcherPhase == .explaining || launcherPhase == .blocked
    }

    var currentPhase: LessonPhase {
        switch step {
        case .capsLock: capsLockPhase
        case .hyper: hyperPhase
        case .launcher: launcherPhase
        case .rules: .installed
        }
    }

    @discardableResult
    func moveForward() -> Bool {
        guard !isApplying else { return false }
        guard let next = Step(rawValue: step.rawValue + 1) else { return false }
        failure = nil
        savedButNotActive = nil
        step = next
        return true
    }

    @discardableResult
    func moveBack() -> Bool {
        guard !isApplying else { return false }
        guard let previous = Step(rawValue: step.rawValue - 1) else { return false }
        failure = nil
        savedButNotActive = nil
        step = previous
        return true
    }

    @discardableResult
    func begin(_ action: ActionKind) -> Bool {
        guard !isApplying else { return false }
        failure = nil
        savedButNotActive = nil
        switch action {
        case .capsLockEscape: capsLockPhase = .applying
        case .hyper: hyperPhase = .applying
        case .launcherShortcut: launcherPhase = .applying
        }
        return true
    }

    func finish(_ action: ActionKind, result: ActionResult) {
        switch result {
        case .applied, .alreadyConfigured:
            failure = nil
            savedButNotActive = nil
            switch action {
            case .capsLockEscape: capsLockPhase = .installed
            case .hyper: hyperPhase = .installed
            case .launcherShortcut: launcherPhase = .installed
            }
        case .savedButNotActive:
            failure = action
            savedButNotActive = action
            switch action {
            case .capsLockEscape: capsLockPhase = .explaining
            case .hyper: hyperPhase = .explaining
            case .launcherShortcut: launcherPhase = .explaining
            }
        case .needsRules:
            failure = action
            savedButNotActive = nil
            switch action {
            case .capsLockEscape: capsLockPhase = .blocked
            case .hyper: hyperPhase = .blocked
            case .launcherShortcut: launcherPhase = .blocked
            }
        case .failed:
            failure = action
            savedButNotActive = nil
            switch action {
            case .capsLockEscape: capsLockPhase = .explaining
            case .hyper: hyperPhase = .explaining
            case .launcherShortcut: launcherPhase = .explaining
            }
        }
    }

    func markCapsLockPracticed() {
        guard capsLockPhase.isInstalled else { return }
        capsLockPhase = .practiced
    }
}

struct FirstSuccessOnboardingButtonState: Equatable, Sendable {
    var skipTourEnabled: Bool
    var backEnabled: Bool
    var primaryEnabled: Bool
}

/// Owns the single durable onboarding mutation independently of view lifetime.
/// Navigation remains unavailable until the underlying install/reload action
/// returns and its result has been reflected in the presentation session.
@MainActor
@Observable
final class FirstSuccessOnboardingActionCoordinator {
    let session: FirstSuccessOnboardingSession

    private(set) var isActionInFlight = false {
        didSet {
            actionStateDidChange?(isActionInFlight)
        }
    }

    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored var actionStateDidChange: ((Bool) -> Void)?

    init(session: FirstSuccessOnboardingSession = FirstSuccessOnboardingSession()) {
        self.session = session
    }

    var canDismiss: Bool {
        !isActionInFlight && !session.isApplying
    }

    var buttonState: FirstSuccessOnboardingButtonState {
        FirstSuccessOnboardingButtonState(
            skipTourEnabled: canDismiss,
            backEnabled: canDismiss && session.step != .capsLock,
            primaryEnabled: canDismiss
        )
    }

    @discardableResult
    func start(
        _ kind: FirstSuccessOnboardingSession.ActionKind,
        initialPresentationDelay: Duration = .milliseconds(17),
        minimumPresentation: Duration = .milliseconds(520),
        action: @escaping @MainActor @Sendable () async -> FirstSuccessOnboardingSession.ActionResult
    ) -> Bool {
        guard actionTask == nil, !isActionInFlight, session.begin(kind) else {
            return false
        }

        isActionInFlight = true
        actionTask = Task { @MainActor in
            defer {
                actionTask = nil
                isActionInFlight = false
            }

            if initialPresentationDelay > .zero {
                try? await Task<Never, Never>.sleep(for: initialPresentationDelay)
            }

            let clock = ContinuousClock()
            let startedAt = clock.now
            let result = await action()
            let elapsed = startedAt.duration(to: clock.now)
            if elapsed < minimumPresentation {
                try? await Task<Never, Never>.sleep(for: minimumPresentation - elapsed)
            }

            session.finish(kind, result: result)
        }
        return true
    }

    @discardableResult
    func moveForward() -> Bool {
        guard canDismiss else { return false }
        return session.moveForward()
    }

    @discardableResult
    func moveBack() -> Bool {
        guard canDismiss else { return false }
        return session.moveBack()
    }

    @discardableResult
    func requestDismiss(perform dismiss: () -> Void) -> Bool {
        guard canDismiss else { return false }
        dismiss()
        return true
    }
}
