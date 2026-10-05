import Foundation
import KeyPathCore
@testable import KeyPathPermissions
import Testing

@Suite("Session active tap permissions")
struct SessionActiveTapPermissionTests {
    @Test("AX alone cannot establish keyboard capture; listening and posting must both be granted")
    func authorizationMatrix() {
        let statuses: [PermissionOracle.Status] = [.granted, .denied, .unknown, .error("inert")]
        for accessibility in statuses {
            for listening in statuses {
                for posting in statuses {
                    let permissions = PermissionOracle.sessionPermissionSet(
                        accessibility: accessibility, eventListening: listening,
                        eventPosting: posting, timestamp: Date()
                    )
                    #expect(permissions.accessibility == accessibility)
                    #expect(permissions.inputMonitoring == (listening.isReady ? posting : listening))
                    #expect(permissions.hasAllPermissions == (accessibility.isReady && listening.isReady && posting.isReady))
                    #expect(permissions.source == "current-process.apple-api.listen-and-post-event")
                    let snapshot = PermissionOracle.Snapshot(
                        keyPath: .init(accessibility: .granted, inputMonitoring: .denied,
                                       source: "inert-parent", confidence: .high, timestamp: Date()),
                        kanata: permissions, timestamp: Date(), backend: .session
                    )
                    #expect(snapshot.isSystemReady == permissions.hasAllPermissions)
                    if accessibility == .granted, listening == .denied, posting == .granted {
                        #expect(snapshot.blockingIssue == "Enable Accessibility and Input Monitoring for KeyPath in System Settings, then quit and reopen KeyPath.")
                    }
                }
            }
        }
    }

    @Test("Report preserves denied input readiness and labels its APIs without claiming a tap")
    func reportProvenanceAndLegacyDecode() throws {
        let report = SessionRuntimeReport(
            nonce: "inert", pid: 42, uid: 502, state: .capabilities,
            accessibility: true, effectiveInputAccess: false, tapActive: false,
            tcpPort: 0, inputCount: 0, outputCount: 0,
            inputAccessSource: "current-process.apple-api.listen-and-post-event"
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
