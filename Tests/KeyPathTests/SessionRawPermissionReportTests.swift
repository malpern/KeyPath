import Foundation
import KeyPathCore
@testable import KeyPathPermissions
import XCTest

final class SessionRawPermissionReportTests: XCTestCase {
    typealias Status = PermissionOracle.Status

    private func snapshot(_ ax: Status, _ listen: Status, _ post: Status) -> PermissionOracle.SessionCapabilitySnapshot {
        PermissionOracle.sampleSessionCapabilities(accessibility: { ax }, eventListening: { listen }, eventPosting: { post })
    }

    private func report(_ raw: SessionRuntimeReport.RawPermissions? = nil) -> SessionRuntimeReport {
        SessionRuntimeReport(nonce: "test", pid: 123, uid: 502, state: .capabilities,
                             accessibility: false, effectiveInputAccess: false, tapActive: false,
                             tcpPort: 0, inputCount: 0, outputCount: 0, rawPermissions: raw)
    }

    func testUnknownAndErrorAreNotEvidenceOfDenial() throws {
        let sample = snapshot(.denied, .unknown, .error("private diagnostic detail"))
        XCTAssertEqual(sample.rawPermissions.accessibility, .denied)
        XCTAssertEqual(sample.rawPermissions.eventListening, .unknown)
        XCTAssertEqual(sample.rawPermissions.eventPosting, .error)
        let data = try JSONEncoder().encode(report(sample.rawPermissions))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("private diagnostic detail"))
        XCTAssertEqual(try JSONDecoder().decode(SessionRuntimeReport.self, from: data).rawPermissions, sample.rawPermissions)
    }

    func testPostingDenialDoesNotMisreportListeningDenial() {
        let sample = snapshot(.granted, .granted, .denied)
        XCTAssertEqual(sample.rawPermissions.eventListening, .granted)
        XCTAssertEqual(sample.rawPermissions.eventPosting, .denied)
        XCTAssertFalse(sample.effective.inputMonitoring.isReady)
        XCTAssertFalse(sample.effective.hasAllPermissions)
    }

    func testEachPassiveReaderRunsExactlyOnceInOrder() {
        var calls: [String] = []
        let sample = PermissionOracle.sampleSessionCapabilities(
            accessibility: { calls.append("AX"); return .denied },
            eventListening: { calls.append("listen"); return .denied },
            eventPosting: { calls.append("post"); return .denied }
        )
        XCTAssertEqual(calls, ["AX", "listen", "post"])
        XCTAssertEqual(sample.rawPermissions, .init(accessibility: .denied, eventListening: .denied, eventPosting: .denied))
        XCTAssertFalse(sample.effective.hasAllPermissions)
    }

    func testExistingEffectivePermissionPolicyIsUnchangedForEveryCombination() {
        let statuses: [Status] = [.granted, .denied, .unknown, .error("test error")]
        for ax in statuses {
            for listen in statuses {
                for post in statuses {
                    let sample = snapshot(ax, listen, post)
                    let previous = PermissionOracle.sessionPermissionSet(
                        accessibility: ax, eventListening: listen, eventPosting: post,
                        timestamp: sample.effective.timestamp
                    )
                    XCTAssertEqual(sample.effective.accessibility, previous.accessibility)
                    XCTAssertEqual(sample.effective.inputMonitoring, previous.inputMonitoring)
                    XCTAssertEqual(sample.effective.source, previous.source)
                    XCTAssertEqual(sample.effective.confidence, previous.confidence)
                    XCTAssertEqual(sample.effective.hasAllPermissions, previous.hasAllPermissions)
                }
            }
        }
        let granted = snapshot(.granted, .granted, .granted)
        XCTAssertTrue(granted.effective.hasAllPermissions)
        XCTAssertEqual(granted.rawPermissions, .init(accessibility: .granted, eventListening: .granted, eventPosting: .granted))
    }

    func testLegacyReportWithoutRawFactsRemainsDecodableButNotExplicitDenial() throws {
        let data = try JSONEncoder().encode(report())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["rawPermissions"])
        XCTAssertNil(try JSONDecoder().decode(SessionRuntimeReport.self, from: data).rawPermissions)
    }

    func testUnknownWireStatusAndMissingRawFieldAreRejected() throws {
        let raw = snapshot(.denied, .denied, .denied).rawPermissions
        let data = try JSONEncoder().encode(report(raw))
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for replacement: Any? in ["future-status", nil] {
            var object = base
            var facts = try XCTUnwrap(object["rawPermissions"] as? [String: Any])
            facts["eventListening"] = replacement
            object["rawPermissions"] = facts
            XCTAssertThrowsError(try JSONDecoder().decode(SessionRuntimeReport.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }
}
