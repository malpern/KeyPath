import Testing
@testable import KeyPathPermissions

struct AccessibilityRefreshTests {
    @Test func trustedProcessDoesNotNeedCrossProcessProbe() {
        var probed = false
        #expect(PermissionOracle.resolveAccessibilityStatus(trusted: true) {
            probed = true
            return false
        } == .granted)
        #expect(!probed)
    }

    @Test func successfulProbeDoesNotRewriteRawTrustEvidence() {
        let sample = PermissionOracle.sampleSessionCapabilities(
            accessibility: { .denied }, eventListening: { .denied },
            eventPosting: { .granted }, verifyExternalAccess: { true }
        )
        #expect(sample.rawPermissions.accessibility == .denied)
        #expect(sample.effective.accessibility == .granted)
    }

    @Test func staleNegativeRequiresSuccessfulExternalAccess() {
        #expect(PermissionOracle.resolveAccessibilityStatus(trusted: false) { true } == .granted)
        #expect(PermissionOracle.resolveAccessibilityStatus(trusted: false) { false } == .denied)
    }
}
