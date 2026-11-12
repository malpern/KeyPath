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
        case let .conflict(key, layer, parties, details):
            let names = parties.map { displayName($0, name) }
            let who = names.count == 2
                ? String(localized: "\(names[0]) and \(names[1])", comment: "Two rule names joined, e.g. 'Vim Navigation and Home Row Mods'")
                : names.joined(separator: ", ")
            let label = keyLabel(key)
            let explanation = details.isEmpty
                ? String(localized: "\(who) both map \(label) on the \(layer) layer. Only one can win.")
                : String(localized: "\(who) both map \(label) on the \(layer) layer (\(details.joined(separator: "; "))). Only one can win.")
            return AdmissionPresentation(
                title: String(localized: "Key conflict on \(label)"),
                explanation: explanation,
                options: verdict.fixes.map { option($0, name) }
            )
        case let .unmetNeed(need):
            return AdmissionPresentation(
                title: String(localized: "\(subject) can't run here"),
                explanation: explain(need, subject: subject),
                options: verdict.fixes.map { option($0, name) }
            )
        case let .reservedKey(key):
            if case let .moveCapsIntermediate(candidates)? = verdict.fixes.first, let next = candidates.first {
                return AdmissionPresentation(
                    title: String(localized: "Caps Lock will use \(next.uppercased())"),
                    explanation: String(localized: "\(subject) uses \(key.uppercased()), which KeyPath had reserved for Caps Lock. Caps Lock will use \(next.uppercased()) instead."),
                    options: []
                )
            }
            return AdmissionPresentation(
                title: String(localized: "\(key.uppercased()) is reserved for Caps Lock"),
                explanation: String(localized: "\(subject) uses \(key.uppercased()), and every alternative (F13–F20) is already taken."),
                options: verdict.fixes.map { option($0, name) }
            )
        case let .capsLockHeldByOtherApp(app):
            return AdmissionPresentation(
                title: String(localized: "\(app) already remaps Caps Lock"),
                explanation: String(localized: "\(subject) needs Caps Lock, but \(app) is remapping it. Turn that off first."),
                options: []
            )
        case let .packConflict(otherPackID, description):
            let other = name(.pack(otherPackID))
            return AdmissionPresentation(
                title: String(localized: "\(subject) and \(other) can't both be installed"),
                explanation: description,
                options: verdict.fixes.map { option($0, name) }
            )
        }
    }

    /// One whole sentence per need, so each translates as a sentence.
    static func explain(_ need: RuleEnvironmentNeed, subject: String) -> String {
        switch need {
        case let .emits(key):
            String(localized: "\(subject) sends \(keyLabel(key)), which the current backend can't send.")
        case .capsLockInput:
            String(localized: "\(subject) needs Caps Lock as an input.")
        case .deviceTargeting:
            String(localized: "\(subject) targets specific keyboards, which isn't supported in driverless mode.")
        case let .externalApp(app, _):
            String(localized: "\(subject) needs \(app) installed.")
        }
    }

    /// Media keys and Caps Lock by their names; everything else as Kanata says it.
    static func keyLabel(_ kanataKey: String) -> String {
        if kanataKey.lowercased() == "caps" { return String(localized: "Caps Lock") }
        return LayerMappingBuilder.mediaKeyDisplayLabel(kanataKey) ?? kanataKey
    }

    private static func displayName(_ subject: AdmissionSubject, _ name: (AdmissionSubject) -> String) -> String {
        if case let .named(text) = subject { return text }
        return name(subject)
    }

    private static func option(_ fix: AdmissionVerdict.Fix, _ name: (AdmissionSubject) -> String) -> AdmissionPresentation.Option {
        switch fix {
        case let .disable(subject):
            if case .pack = subject {
                return .init(subject: subject, label: String(localized: "Remove \(displayName(subject, name))"), fix: fix)
            }
            return .init(subject: subject, label: String(localized: "Turn off \(displayName(subject, name))"), fix: fix)
        case let .installApp(app, _):
            return .init(subject: .named(app), label: String(localized: "Install \(app)"), fix: fix)
        case let .moveCapsIntermediate(candidates):
            return .init(subject: .named("caps"), label: String(localized: "Use \((candidates.first ?? "").uppercased()) for Caps Lock"), fix: fix)
        }
    }
}
