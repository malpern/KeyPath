import Foundation
import KeyPathCore
@testable import KeyPathPermissions
import Testing

@Suite("Session active tap permissions")
struct SessionActiveTapPermissionTests {
    @Test("Modifying tap and posting require their own current-process authorization")
    func authorizationMatrix() {
        let statuses: [PermissionOracle.Status] = [.granted, .denied, .unknown, .error("inert")]
        for accessibility in statuses {
            for posting in statuses {
                let permissions = PermissionOracle.sessionPermissionSet(
                    accessibility: accessibility, eventPosting: posting, timestamp: Date()
                )
                #expect(permissions.accessibility == accessibility)
                #expect(permissions.inputMonitoring == posting)
                #expect(permissions.hasAllPermissions == (accessibility.isReady && posting.isReady))
                #expect(permissions.source == "current-process.apple-api.modifying-tap-post-event")
            }
        }
    }

    @Test("Report preserves denied posting and labels its API without claiming a tap")
    func reportProvenanceAndLegacyDecode() throws {
        let report = SessionRuntimeReport(
            nonce: "inert", pid: 42, uid: 502, state: .capabilities,
            accessibility: true, effectiveInputAccess: false, tapActive: false,
            tcpPort: 0, inputCount: 0, outputCount: 0,
            inputAccessSource: "current-process.apple-api.modifying-tap-post-event"
        )
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(SessionRuntimeReport.self, from: encoded)
        #expect(decoded == report)
        #expect(!decoded.effectiveInputAccess && !decoded.tapActive)
        var historical = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        historical.removeValue(forKey: "inputAccessSource")
        let legacy = try JSONDecoder().decode(
            SessionRuntimeReport.self, from: JSONSerialization.data(withJSONObject: historical)
        )
        #expect(legacy.inputAccessSource == nil)
        #expect(!legacy.effectiveInputAccess && legacy.accessibility)
    }
}
