import Foundation

/// Pure decision logic for the guidance the Input Monitoring wizard page should
/// present for **KeyPath.app's own** Input Monitoring grant. Extracted so the
/// escalation behavior can be unit-tested without a running UI (mirrors the pure
/// resolvers added for the Oracle signal in #931/#937).
///
/// Background (#931): clicking "Turn On" fires `IOHIDRequestAccess`, but on
/// macOS 26/27 tccd can silently produce nothing — no system prompt, no TCC row,
/// and the app never appears in the Input Monitoring list. The page used to leave
/// a bare "Turn On" button pointing at a Settings entry that does not exist, so a
/// fresh install dead-ended here at `unknown`/`denied` with no accurate guidance.
///
/// This resolver drives an escalation: try the automatic prompt first, and if the
/// grant has not landed within a short wait window, switch to explicit manual
/// "add it yourself in System Settings" instructions so the user is never
/// stranded.
public enum InputMonitoringGuidance: Equatable, Sendable {
    /// KeyPath.app already has Input Monitoring — no guidance needed.
    case granted
    /// No automatic request has been attempted yet — offer the one-click "Turn On".
    case offerAutomatic
    /// A request was attempted and we are still within the wait window — treat as
    /// a transient "waiting for the grant to register" state, not a dead-end.
    case awaitingGrant
    /// The automatic request did not register within the wait window — show
    /// explicit manual instructions so the user is never stranded (#931).
    case manualFallback
}

/// Inputs for `resolveInputMonitoringGuidance`. All fields describe KeyPath.app's
/// own Input Monitoring state and the automatic-prompt attempt against it.
public struct InputMonitoringGuidanceInput: Equatable, Sendable {
    /// Whether KeyPath.app's own Input Monitoring is granted (Oracle `isReady`).
    public var keyPathReady: Bool
    /// Whether the user has triggered the automatic `IOHIDRequestAccess` prompt.
    public var requestAttempted: Bool
    /// Seconds elapsed since the most recent automatic request, or nil if none /
    /// unknown. `nil` while `requestAttempted` is true is treated as "elapsed".
    public var secondsSinceRequest: TimeInterval?
    /// How long to wait for an automatic grant before escalating to manual steps.
    public var waitWindow: TimeInterval

    public init(
        keyPathReady: Bool,
        requestAttempted: Bool,
        secondsSinceRequest: TimeInterval?,
        waitWindow: TimeInterval = 6
    ) {
        self.keyPathReady = keyPathReady
        self.requestAttempted = requestAttempted
        self.secondsSinceRequest = secondsSinceRequest
        self.waitWindow = waitWindow
    }
}

/// Resolve what the Input Monitoring page should show for KeyPath.app's own grant.
///
/// - A granted app short-circuits to `.granted` regardless of any prior attempt.
/// - Before any attempt, the automatic one-click path is offered.
/// - After an attempt we allow a brief window for the grant to register before
///   escalating to manual instructions, so a normally-working prompt isn't
///   immediately buried under fallback copy.
public func resolveInputMonitoringGuidance(
    _ input: InputMonitoringGuidanceInput
) -> InputMonitoringGuidance {
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
