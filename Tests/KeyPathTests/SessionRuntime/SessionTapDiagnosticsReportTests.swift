import Foundation
import KeyPathCore
import Testing
#if KEYPATH_TAP_TIMEOUT_EXPERIMENT
    import Darwin
    @testable import KeyPathAppKit
#endif

struct SessionTapDiagnosticsReportTests {
    private func report(_ diagnostics: SessionRuntimeReport.ExperimentalTapDiagnostics? = nil) -> SessionRuntimeReport {
        SessionRuntimeReport(
            nonce: "inert", pid: 42, uid: 502, state: .running,
            accessibility: true, effectiveInputAccess: true, tapActive: true,
            tcpPort: 37001, inputCount: 0, outputCount: 0,
            experimentalTapDiagnostics: diagnostics
        )
    }

    @Test("Callback observations remain distinct from mapped input and output")
    func callbackWithoutMappedInput() throws {
        let value = report(.init(rawTapCallbackCount: 74, qMapped: false, aMapped: true, configSHA256: String(repeating: "a", count: 64)))
        let decoded = try JSONDecoder().decode(SessionRuntimeReport.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        #expect(decoded.inputCount == 0 && decoded.outputCount == 0)
        #expect(decoded.experimentalTapDiagnostics?.rawTapCallbackCount == 74)
        #expect(decoded.experimentalTapDiagnostics?.qMapped == false)
        #expect(decoded.isCurrent(nonce: "inert", pid: 42, uid: 502, now: value.timestamp))
    }

    @Test("Normal and historical reports omit diagnostics without changing admission")
    func historicalDecode() throws {
        let value = report()
        let encoded = try JSONEncoder().encode(value)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["experimentalTapDiagnostics"] == nil)
        let decoded = try JSONDecoder().decode(SessionRuntimeReport.self, from: encoded)
        #expect(decoded.experimentalTapDiagnostics == nil)
        #expect(decoded.belongsTo(nonce: "inert", pid: 42, uid: 502))
    }

    @Test("Experimental diagnostics reject wrong types, missing fields and event content")
    func malformedDiagnostics() throws {
        let good: [String: Any] = ["rawTapCallbackCount": 0, "qMapped": true, "aMapped": true]
        var variants: [[String: Any]] = []
        for (key, value) in [("rawTapCallbackCount", "0" as Any), ("rawTapCallbackCount", -1), ("qMapped", 1), ("aMapped", "true"), ("configSHA256", "PRIVATE_CONFIG_CONTENT"), ("eventText", "q")] {
            var bad = good; bad[key] = value; variants.append(bad)
        }
        for key in good.keys {
            var bad = good; bad.removeValue(forKey: key); variants.append(bad)
        }
        for bad in variants {
            var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report())) as? [String: Any])
            fields["experimentalTapDiagnostics"] = bad
            let encoded = try JSONSerialization.data(withJSONObject: fields)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SessionRuntimeReport.self, from: encoded) }
        }
    }

    #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
        @Test("Config digest samples regular files within the byte cap and omits oversized files")
        func boundedConfigDigest() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("controlled.kbd")
            try Data("(defcfg)\n(defsrc q a)\n(deflayer base a a)\n".utf8).write(to: path)
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: path.path) == "4cf78f9e44b5fe0e58c4bfce714b619e82d018268465acf6e660bba771a91631")
            try Data(repeating: 97, count: 65536).write(to: path)
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: path.path) != nil)
            try Data(repeating: 97, count: 65537).write(to: path)
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: path.path) == nil)
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: directory.path) == nil)
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: directory.appendingPathComponent("absent").path) == nil)
        }

        @Test("Diagnostic sampling refuses a no-writer FIFO promptly and omits symlink hashes")
        func unsupportedFileKindsDoNotBlock() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let fifo = directory.appendingPathComponent("no-writer.fifo")
            #expect(mkfifo(fifo.path, 0o600) == 0)
            let started = Date()
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: fifo.path) == nil)
            #expect(Date().timeIntervalSince(started) < 1)
            let regular = directory.appendingPathComponent("regular.kbd")
            try Data("(defcfg)\n(defsrc q a)\n(deflayer base a a)\n".utf8).write(to: regular)
            let link = directory.appendingPathComponent("linked.kbd")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: regular)
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: regular.path) != nil)
            #expect(SessionRuntimeWorker.experimentalConfigSHA256(configPath: link.path) == nil)
        }

        @Test("Terminal startup diagnostic includes bounded, correlated report evidence")
        func terminalStartupDiagnosticContainsReport() throws {
            let now = Date(timeIntervalSince1970: 2000)
            let nonce = "01234567-89AB-CDEF-0123-456789ABCDEF"
            let tap = SessionRuntimeReport.RegisteredTapObservation(
                outcome: .observed, requestedMask: 7168,
                rows: [.init(mask: 4096, enabled: true)],
                rawAccessibility: "granted", rawPostEvent: "granted", rawListenEvent: "denied",
                enumerationAttempted: true
            )
            let value = terminalReport(
                now: now, nonce: nonce, failure: "modifying-tap-missing-requested-events",
                diagnostics: .init(rawTapCallbackCount: 0, qMapped: true, aMapped: true,
                                   configSHA256: nil, registeredTap: tap)
            )

            let json = try #require(value.experimentalTerminalStartupDiagnosticJSON(
                parentPID: 101, expectedWorkerPID: 202, expectedUID: 502,
                expectedNonce: nonce, launchGeneration: 7, now: now
            ))
            let envelope = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            let report = try #require(envelope["report"] as? [String: Any])
            let diagnostics = try #require(report["experimentalTapDiagnostics"] as? [String: Any])
            let registeredTap = try #require(diagnostics["registeredTap"] as? [String: Any])

            #expect(envelope["schema"] as? String == "keypath.session-start-terminal.v1")
            #expect(envelope["parentPID"] as? Int == 101)
            #expect(envelope["workerPID"] as? Int == 202)
            #expect(envelope["uid"] as? Int == 502)
            #expect(envelope["launchGeneration"] as? Int == 7)
            #expect(envelope["nonce"] as? String == nonce)
            #expect(envelope["capturedAtUnixMilliseconds"] as? Int64 == 2_000_000)
            #expect(envelope["reportTimestampUnixMilliseconds"] as? Int64 == 2_000_000)
            #expect(envelope["reportAgeMilliseconds"] as? Int == 0)
            #expect(report["state"] as? String == "failed")
            #expect(report["failure"] as? String == "modifying-tap-missing-requested-events")
            #expect(registeredTap["requestedMask"] as? Int == 7168)
            #expect(registeredTap["rawListenEvent"] as? String == "denied")
            #expect(json.utf8.count <= 16384)
            #expect(!json.contains("eventText"))
        }

        @Test("Terminal startup diagnostic rejects foreign, stale, nonfailed, and nonidle reports")
        func terminalStartupDiagnosticRejectsInvalidEvidence() {
            let now = Date(timeIntervalSince1970: 2000)
            let nonce = "01234567-89AB-CDEF-0123-456789ABCDEF"
            let valid = terminalReport(now: now, nonce: nonce, failure: "modifying-tap-not-enabled")
            func format(_ report: SessionRuntimeReport, nonce: String, pid: Int32, uid: UInt32, time: Date) -> String? {
                report.experimentalTerminalStartupDiagnosticJSON(
                    parentPID: 101, expectedWorkerPID: pid, expectedUID: uid,
                    expectedNonce: nonce, launchGeneration: 7, now: time
                )
            }

            #expect(format(valid, nonce: "foreign", pid: 202, uid: 502, time: now) == nil)
            #expect(format(valid, nonce: nonce, pid: 999, uid: 502, time: now) == nil)
            #expect(format(valid, nonce: nonce, pid: 202, uid: 999, time: now) == nil)
            #expect(format(terminalReport(now: now, nonce: nonce, failure: "failed", age: 2.001), nonce: nonce, pid: 202, uid: 502, time: now) == nil)
            #expect(format(valid, nonce: nonce, pid: 202, uid: 502, time: now.addingTimeInterval(-0.01)) == nil)
            #expect(format(terminalReport(now: now, nonce: nonce, failure: "failed", state: .running), nonce: nonce, pid: 202, uid: 502, time: now) == nil)
            #expect(format(terminalReport(now: now, nonce: nonce, failure: nil), nonce: nonce, pid: 202, uid: 502, time: now) == nil)
            #expect(format(terminalReport(now: now, nonce: nonce, failure: "failed", inputCount: 1), nonce: nonce, pid: 202, uid: 502, time: now) == nil)
            #expect(format(terminalReport(now: now, nonce: nonce, failure: "failed", outputCount: 1), nonce: nonce, pid: 202, uid: 502, time: now) == nil)
            #expect(format(terminalReport(now: now, nonce: nonce, failure: "failed", held: [4]), nonce: nonce, pid: 202, uid: 502, time: now) == nil)
        }

        @Test("Terminal startup diagnostic bounds the logged failure summary and payload")
        func terminalStartupDiagnosticIsBounded() throws {
            let now = Date(timeIntervalSince1970: 2000)
            let value = terminalReport(
                now: now, nonce: "01234567-89AB-CDEF-0123-456789ABCDEF",
                failure: String(repeating: "x", count: 10000)
            )
            let json = try #require(value.experimentalTerminalStartupDiagnosticJSON(
                parentPID: 101, expectedWorkerPID: 202, expectedUID: 502,
                expectedNonce: value.nonce, launchGeneration: 7, now: now
            ))
            let envelope = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect((envelope["failureSummary"] as? String)?.count == 160)
            #expect(json.utf8.count <= 16384)
        }

        private func terminalReport(
            now: Date, nonce: String, failure: String?, state: SessionRuntimeReport.State = .failed,
            age: TimeInterval = 0, inputCount: UInt64 = 0, outputCount: UInt64 = 0,
            held: [UInt32] = [], diagnostics: SessionRuntimeReport.ExperimentalTapDiagnostics? = nil
        ) -> SessionRuntimeReport {
            SessionRuntimeReport(
                nonce: nonce, pid: 202, uid: 502, state: state,
                accessibility: true, effectiveInputAccess: true, tapActive: false,
                tcpPort: 37001, inputCount: inputCount, outputCount: outputCount,
                timestamp: now.addingTimeInterval(-age), failure: failure,
                heldOutputUsages: held, inputAccessSource: "current-process.apple-api.modifying-tap-post-event",
                experimentalTapDiagnostics: diagnostics
            )
        }
    #endif
}
