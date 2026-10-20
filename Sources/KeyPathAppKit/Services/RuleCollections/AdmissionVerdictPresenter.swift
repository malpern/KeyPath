import Foundation
import KeyPathRulesCore

/// How an `AdmissionVerdict` reads to a person: one title, one explanation, and
/// the choices its fixes offer. Dialogs, toasts and the CLI all render from this,
/// so a reason is worded once (phase 4b of the admission review).
public struct AdmissionPresentation: Equatable, Sendable {
    public struct Option: Equatable, Identifiable, Sendable {
        public let subject: AdmissionSubject
        public let label: String
        public let fix: AdmissionVerdict.Fix
        public var id: String {
            "\(subject)|\(label)"
        }
    }

    public let title: String
    public let explanation: String
    public let options: [Option]
}

enum AdmissionVerdictPresenter {
    /// `name` resolves a subject to what the user calls it (collection or rule
    /// title, pack name); synthetic parties already carry their name.
    static func present(_ verdict: AdmissionVerdict, name: (AdmissionSubject) -> String) -> AdmissionPresentation {
        let subject = displayName(verdict.subject, name)
        switch verdict.reason {
        case let .conflict(key, layer, parties):
            let names = parties.map { displayName($0, name) }
            let who = names.count == 2 ? "\(names[0]) and \(names[1])" : names.joined(separator: ", ")
            return AdmissionPresentation(
                title: "Key conflict on \(key)",
                explanation: "\(who) both map \(key) on the \(layer) layer. Only one can win.",
                options: verdict.fixes.map { option($0, name) }
            )
        case let .unmetNeed(need):
            return AdmissionPresentation(
                title: "\(subject) can't run here",
                explanation: "\(subject) \(describe(need)).",
                options: verdict.fixes.map { option($0, name) }
            )
        case let .reservedKey(key):
            if case let .moveCapsIntermediate(candidates)? = verdict.fixes.first, let next = candidates.first {
                return AdmissionPresentation(
                    title: "Caps Lock will use \(next.uppercased())",
                    explanation: "\(subject) uses \(key.uppercased()), which KeyPath had reserved for Caps Lock. Caps Lock will use \(next.uppercased()) instead.",
                    options: []
                )
            }
            return AdmissionPresentation(
                title: "\(key.uppercased()) is reserved for Caps Lock",
                explanation: "\(subject) uses \(key.uppercased()), and every alternative (F13–F20) is already taken.",
                options: verdict.fixes.map { option($0, name) }
            )
        case let .capsLockHeldByOtherApp(app):
            return AdmissionPresentation(
                title: "\(app) already remaps Caps Lock",
                explanation: "\(subject) needs Caps Lock, but \(app) is remapping it. Turn that off first.",
                options: []
            )
        case let .packConflict(otherPackID, description):
            let other = name(.pack(otherPackID))
            return AdmissionPresentation(
                title: "\(subject) and \(other) can't both be installed",
                explanation: description,
                options: verdict.fixes.map { option($0, name) }
            )
        }
    }

    /// For `automatic` verdicts: the one line worth showing afterwards.
    static func oneLine(_ verdict: AdmissionVerdict, name: (AdmissionSubject) -> String) -> String {
        let presentation = present(verdict, name: name)
        return verdict.severity == .automatic ? presentation.explanation : presentation.title
    }

    static func describe(_ need: RuleEnvironmentNeed) -> String {
        switch need {
        case let .emits(key): "sends \(key), which the current backend can't send"
        case .capsLockInput: "needs Caps Lock as an input"
        case .deviceTargeting: "targets specific keyboards, which isn't supported in driverless mode"
        case let .externalApp(app, _): "needs \(app) installed"
        }
    }

    private static func displayName(_ subject: AdmissionSubject, _ name: (AdmissionSubject) -> String) -> String {
        if case let .named(text) = subject { return text }
        return name(subject)
    }

    private static func option(_ fix: AdmissionVerdict.Fix, _ name: (AdmissionSubject) -> String) -> AdmissionPresentation.Option {
        switch fix {
        case let .disable(subject):
            if case .pack = subject {
                return .init(subject: subject, label: "Remove \(displayName(subject, name))", fix: fix)
            }
            return .init(subject: subject, label: "Turn off \(displayName(subject, name))", fix: fix)
        case let .installApp(app, _):
            return .init(subject: .named(app), label: "Install \(app)", fix: fix)
        case let .moveCapsIntermediate(candidates):
            return .init(subject: .named("caps"), label: "Use \((candidates.first ?? "").uppercased()) for Caps Lock", fix: fix)
        }
    }
}
