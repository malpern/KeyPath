import Foundation
@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathPermissions
import XCTest

final class SessionCapabilityProbeTests: XCTestCase {
    @MainActor
    func testActualCapabilityPathWritesOnlyInactiveEvidenceFromOnePassiveSample() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = directory.appendingPathComponent("keypath.kbd")
        let original = Data("untouched configuration".utf8)
        try original.write(to: configuration)
        let reportURL = directory.appendingPathComponent("capability.json")
        let nonce = UUID().uuidString
        var reads = 0
        await SessionRuntimeWorker.writeCapabilityReport(
            reportURL: reportURL, nonce: nonce, ownerPID: 0, port: 0,
            snapshotProvider: {
                reads += 1
                return PermissionOracle.sampleSessionCapabilities(
                    accessibility: { .denied }, eventListening: { .unknown },
                    eventPosting: { .error("must not be serialized") }
                )
            }
        )
        let report = try JSONDecoder().decode(SessionRuntimeReport.self, from: Data(contentsOf: reportURL))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(report.state, .capabilities)
        XCTAssertEqual(report.nonce, nonce)
        XCTAssertEqual(report.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertFalse(report.accessibility)
        XCTAssertFalse(report.effectiveInputAccess)
        XCTAssertEqual(report.inputAccessSource, "current-process.apple-api.listen-and-post-event")
        XCTAssertEqual(report.rawPermissions, .init(accessibility: .denied, eventListening: .unknown, eventPosting: .error))
        XCTAssertFalse(report.tapActive)
        XCTAssertEqual(report.inputCount, 0)
        XCTAssertEqual(report.outputCount, 0)
        XCTAssertEqual(report.tcpPort, 0)
        XCTAssertEqual(report.heldOutputUsages, [])
        XCTAssertNil(report.managedCapsGeneration)
        XCTAssertEqual(try Data(contentsOf: configuration), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: reportURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)), ["keypath.kbd", "capability.json"])
    }
}
