import Foundation

/// Whether a Full Disk Access state observed on the FDA wizard page should trigger
/// its celebrate + auto-advance flow.
///
/// Only a grant that lands **during** the visit advances. A grant that was already
/// in place when the page appeared is a *review visit* — the Summary row is always
/// navigable, so the user may open the page just to look at it — and must NOT
/// navigate them off a page they never acted on (the bug fixed in #933).
///
/// Extracted as a pure function so this "should I auto-advance" decision is unit
/// testable independent of the view's `@State`, timers, and `onChange` plumbing.
///
/// - Parameters:
///   - isGrantedNow: the freshly-observed FDA state (`hasFullDiskAccess`).
///   - wasGrantedOnAppear: whether FDA was already granted when the page appeared.
public func shouldAdvanceOnFullDiskAccessGrant(
    isGrantedNow: Bool,
    wasGrantedOnAppear: Bool
) -> Bool {
    isGrantedNow && !wasGrantedOnAppear
}
