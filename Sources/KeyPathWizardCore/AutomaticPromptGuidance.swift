import Foundation

/// Pure decision logic for how a wizard permission page should guide **KeyPath.app's
/// own** grant of a permission it can request via an automatic system prompt
/// (Input Monitoring via `IOHIDRequestAccess`, Accessibility via the AX prompt).
/// Extracted so the escalation behavior can be unit-tested without a running UI
/// (mirrors the pure resolvers added for the Oracle signal in #931/#937).
///
/// The logic is permission-agnostic — it only reasons about "is it granted", "was
/// the automatic prompt attempted", and "how long ago" — so a single resolver backs
/// both the Input Monitoring and Accessibility pages (#933).
///
/// Background (#931): clicking "Turn On" fires the automatic prompt, but on
/// macOS 26/27 tccd can silently produce nothing — no system prompt, no TCC row,
/// and the app never appears in the privacy list. The page used to leave a bare
/// "Turn On" button pointing at a Settings entry that does not exist, so a fresh
/// install dead-ended at `unknown`/`denied` with no accurate guidance.
///
/// This resolver drives an escalation: try the automatic prompt first, and if the
/// grant has not landed within a short wait window, switch to explicit manual
/// "add it yourself in System Settings" guidance so the user is never stranded.
public enum AutomaticPromptGuidance: Equatable, Sendable {
    /// KeyPath.app already has the permission — no guidance needed.
    case granted
    /// No automatic request has been attempted yet — offer the one-click "Turn On".
    case offerAutomatic
    /// A request was attempted and we are still within the wait window — treat as
    /// a transient "waiting for the grant to register" state, not a dead-end.
    case awaitingGrant
    /// The automatic request did not register within the wait window — show
    /// explicit manual guidance so the user is never stranded (#931).
    case manualFallback
}

/// Inputs for `resolveAutomaticPromptGuidance`. All fields describe KeyPath.app's
/// own state for one permission and the automatic-prompt attempt against it.
public struct AutomaticPromptGuidanceInput: Equatable, Sendable {
    /// Whether KeyPath.app's own permission is granted (Oracle `isReady`).
    public var keyPathReady: Bool
    /// Whether the user has triggered the automatic system prompt.
    public var requestAttempted: Bool
    /// Seconds elapsed since the most recent automatic request, or nil if none /
    /// unknown. `nil` while `requestAttempted` is true is treated as "elapsed".
    public var secondsSinceRequest: TimeInterval?
    /// How long to wait for an automatic grant before escalating to manual steps.
    ///
    /// Tuned to outlast a *working* system prompt: when the automatic request does
    /// show the macOS dialog, a first-run user often takes several seconds to read
    /// and click "Allow". The window must be long enough that we don't flash
    /// "Didn't see a prompt?" while that real dialog is still on screen, yet short
    /// enough that a genuinely stuck user (macOS 26/27, no dialog at all) isn't
    /// stranded. 12s balances the two.
    public var waitWindow: TimeInterval

    public init(
        keyPathReady: Bool,
        requestAttempted: Bool,
        secondsSinceRequest: TimeInterval?,
        waitWindow: TimeInterval = 12
    ) {
        self.keyPathReady = keyPathReady
        self.requestAttempted = requestAttempted
        self.secondsSinceRequest = secondsSinceRequest
        self.waitWindow = waitWindow
    }
}

/// Resolve what a permission page should show for KeyPath.app's own grant.
///
/// - A granted app short-circuits to `.granted` regardless of any prior attempt.
/// - Before any attempt, the automatic one-click path is offered.
/// - After an attempt we allow a brief window for the grant to register before
///   escalating to manual instructions, so a normally-working prompt isn't
///   immediately buried under fallback copy.
public func resolveAutomaticPromptGuidance(
    _ input: AutomaticPromptGuidanceInput
) -> AutomaticPromptGuidance {
    if input.keyPathReady {
        return .granted
    }
    guard input.requestAttempted else {
        return .offerAutomatic
    }
    // Only keep waiting for a well-formed elapsed time inside the window. A nil
    // (unknown) or negative (wall-clock moved backwards) elapsed must escalate
    // rather than strand the user in an endless "waiting" state — the whole point
    // of #931 is that guidance is always eventually reached.
    if let elapsed = input.secondsSinceRequest, elapsed >= 0, elapsed < input.waitWindow {
        return .awaitingGrant
    }
    return .manualFallback
}

/// Advance the "how long has this permission been unverified" clock from a
/// fresh status observation (#931, kanata-launcher row). Pure so the wizard
/// page's escalation timing is unit-testable without a running UI.
///
/// - The clock starts at `now` on the first `.unknown` observation and is
///   deliberately NOT refreshed while the status stays `.unknown` — the window
///   measures total time stranded, not time since the last poll.
/// - Any conclusive status (granted/denied/error) clears it, so a later return
///   to `.unknown` restarts the wait window from scratch.
public func advanceUnverifiedClock(
    previous: Date?, statusIsUnknown: Bool, now: Date
) -> Date? {
    guard statusIsUnknown else { return nil }
    return previous ?? now
}
