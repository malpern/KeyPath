import Foundation

@main
enum SessionTerminalDiagnosticRunner {
    static func main() {
        let now = Date(timeIntervalSince1970: 2000)
        let nonce = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let valid = report(now: now, nonce: nonce, failure: "modifying-tap-missing-requested-events")
        guard let json = valid.experimentalTerminalStartupDiagnosticJSON(
            parentPID: 101, expectedWorkerPID: 202, expectedUID: 502,
            expectedNonce: nonce, launchGeneration: 7, now: now
        ) else { fail("valid terminal failure was refused") }

        guard let envelope = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let nested = envelope["report"] as? [String: Any],
              json.utf8.count <= 16384,
              envelope["schema"] as? String == "keypath.session-start-terminal.v1",
              envelope["parentPID"] as? Int == 101,
              envelope["workerPID"] as? Int == 202,
              envelope["uid"] as? Int == 502,
              envelope["launchGeneration"] as? Int == 7,
              envelope["nonce"] as? String == nonce,
              envelope["capturedAtUnixMilliseconds"] as? Int64 == 2_000_000,
              envelope["reportTimestampUnixMilliseconds"] as? Int64 == 2_000_000,
              envelope["reportAgeMilliseconds"] as? Int == 0,
              nested["state"] as? String == "failed",
              nested["inputCount"] as? Int == 0,
              nested["outputCount"] as? Int == 0,
              !json.contains("eventText")
        else { fail("terminal JSON envelope contract failed") }

        let oversizedFailure = report(now: now, nonce: nonce, failure: String(repeating: "x", count: 10000))
        guard let boundedJSON = oversizedFailure.experimentalTerminalStartupDiagnosticJSON(
            parentPID: 101, expectedWorkerPID: 202, expectedUID: 502,
            expectedNonce: nonce, launchGeneration: 7, now: now
        ), let bounded = try? JSONSerialization.jsonObject(with: Data(boundedJSON.utf8)) as? [String: Any],
        (bounded["failureSummary"] as? String)?.count == 160,
        boundedJSON.utf8.count <= 16384
        else { fail("terminal diagnostic size or failure-summary bound failed") }

        let rejected: [(String, SessionRuntimeReport, String, Int32, UInt32, Date)] = [
            ("foreign nonce", valid, "foreign", 202, 502, now),
            ("foreign pid", valid, nonce, 999, 502, now),
            ("foreign uid", valid, nonce, 202, 999, now),
            ("stale report", report(now: now, nonce: nonce, failure: "failed", age: 2.001), nonce, 202, 502, now),
            ("future report", valid, nonce, 202, 502, now.addingTimeInterval(-0.01)),
            ("nonfailed state", report(now: now, nonce: nonce, failure: "failed", state: .running), nonce, 202, 502, now),
            ("missing failure", report(now: now, nonce: nonce, failure: nil), nonce, 202, 502, now),
            ("input observed", report(now: now, nonce: nonce, failure: "failed", inputCount: 1), nonce, 202, 502, now),
            ("output emitted", report(now: now, nonce: nonce, failure: "failed", outputCount: 1), nonce, 202, 502, now),
            ("held outputs", report(now: now, nonce: nonce, failure: "failed", held: [4]), nonce, 202, 502, now)
        ]
        for (label, value, expectedNonce, pid, uid, captureTime) in rejected {
            guard value.experimentalTerminalStartupDiagnosticJSON(
                parentPID: 101, expectedWorkerPID: pid, expectedUID: uid,
                expectedNonce: expectedNonce, launchGeneration: 7, now: captureTime
            ) == nil else { fail("formatter accepted \(label)") }
        }

        print("SessionTerminalDiagnosticRunner: PASS")
    }

    private static func report(
        now: Date, nonce: String, failure: String?, state: SessionRuntimeReport.State = .failed,
        age: TimeInterval = 0, inputCount: UInt64 = 0, outputCount: UInt64 = 0,
        held: [UInt32] = []
    ) -> SessionRuntimeReport {
        SessionRuntimeReport(
            nonce: nonce, pid: 202, uid: 502, state: state,
            accessibility: true, effectiveInputAccess: true, tapActive: false,
            tcpPort: 37001, inputCount: inputCount, outputCount: outputCount,
            timestamp: now.addingTimeInterval(-age), failure: failure, heldOutputUsages: held
        )
    }

    private static func fail(_ message: String) -> Never {
        fputs("SessionTerminalDiagnosticRunner: FAIL: \(message)\n", stderr)
        exit(1)
    }
}
