import Foundation

@main
struct TapTimeoutReportSchemaTests {
    static func main() throws {
        typealias Diagnostic = SessionRuntimeReport.ExperimentalTapTimeoutDiagnostic
        let diagnostic = Diagnostic(initialization: .identityDigestUnavailable,
                                   preparation: .commandChangedDuringRead,
                                   callbackFirstResult: .reportAgeInvalid)
        let report = SessionRuntimeReport(
            nonce: "inert", pid: 10, uid: 502, state: .running,
            accessibility: true, effectiveInputAccess: true, tapActive: true,
            tcpPort: 37001, inputCount: 0, outputCount: 0,
            experimentalTapTimeout: diagnostic
        )
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(SessionRuntimeReport.self, from: encoded)
        precondition(decoded.experimentalTapTimeout == diagnostic)

        let oldReport = SessionRuntimeReport(
            nonce: "old", pid: 11, uid: 502, state: .running,
            accessibility: true, effectiveInputAccess: true, tapActive: true,
            tcpPort: 37001, inputCount: 0, outputCount: 0
        )
        let oldData = try JSONEncoder().encode(oldReport)
        let decodedOld = try JSONDecoder().decode(SessionRuntimeReport.self, from: oldData)
        precondition(decodedOld.experimentalTapTimeout == nil)
        let oldObject = try JSONSerialization.jsonObject(with: oldData) as! [String: Any]
        precondition(oldObject["experimentalTapTimeout"] == nil)

        var root = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var nested = root["experimentalTapTimeout"] as! [String: Any]
        nested["eventText"] = "q"
        root["experimentalTapTimeout"] = nested
        let withUnknownField = try JSONSerialization.data(withJSONObject: root)
        do {
            _ = try JSONDecoder().decode(SessionRuntimeReport.self, from: withUnknownField)
            fatalError("unknown diagnostic field accepted")
        } catch {}

        nested.removeValue(forKey: "eventText")
        for field in ["initialization", "preparation", "callbackFirstResult"] {
            var missing = nested
            missing.removeValue(forKey: field)
            var candidate = root; candidate["experimentalTapTimeout"] = missing
            let data = try JSONSerialization.data(withJSONObject: candidate)
            do {
                _ = try JSONDecoder().decode(SessionRuntimeReport.self, from: data)
                fatalError("missing required diagnostic field accepted: \(field)")
            } catch {}

            for wrongValue: Any in [NSNull(), 1] {
                var wrongType = nested; wrongType[field] = wrongValue
                candidate["experimentalTapTimeout"] = wrongType
                let bad = try JSONSerialization.data(withJSONObject: candidate)
                do {
                    _ = try JSONDecoder().decode(SessionRuntimeReport.self, from: bad)
                    fatalError("wrong diagnostic field type accepted: \(field)")
                } catch {}
            }
        }

        for (field, unknownStatus) in [("initialization", "unknown"), ("preparation", "unknown"),
                                       ("callbackFirstResult", "unknown")] {
            var badStatus = nested; badStatus[field] = unknownStatus
            root["experimentalTapTimeout"] = badStatus
            let data = try JSONSerialization.data(withJSONObject: root)
            do {
                _ = try JSONDecoder().decode(SessionRuntimeReport.self, from: data)
                fatalError("unknown diagnostic status accepted: \(field)")
            } catch {}
        }

        let timing = SessionRuntimeReport.RegisteredTapObservation.Row.Timing(
            eventTapID: 27, options: 0, minUsecLatency: 10, avgUsecLatency: 250, maxUsecLatency: 1_003_625
        )
        let tap = SessionRuntimeReport.RegisteredTapObservation(
            outcome: .observed, requestedMask: 7168, rows: [.init(mask: 7168, enabled: false, timing: timing)],
            rawAccessibility: "granted", rawPostEvent: "granted", rawListenEvent: "granted", enumerationAttempted: true
        )
        let evidence = SessionRuntimeReport.ExperimentalTapDiagnostics(
            rawTapCallbackCount: 9, qMapped: true, aMapped: false, configSHA256: nil, registeredTap: tap,
            postDelayRegisteredTap: tap, postDelayQueryUptimeNanos: 1_234_567,
            rawTimeoutCallbackCount: 1, rawUserInputDisabledCallbackCount: 0
        )
        let evidenceData = try JSONEncoder().encode(evidence)
        let decodedEvidence = try JSONDecoder().decode(SessionRuntimeReport.ExperimentalTapDiagnostics.self, from: evidenceData)
        precondition(decodedEvidence == evidence)
        let historical = Data(#"{"rawTapCallbackCount":0,"qMapped":true,"aMapped":false,"registeredTap":{"outcome":"observed","requestedMask":7168,"rows":[{"mask":7168,"enabled":true}],"rawAccessibility":"granted","rawPostEvent":"granted","rawListenEvent":"granted","queryLimit":128,"enumerationAttempted":true}}"#.utf8)
        let legacy = try JSONDecoder().decode(SessionRuntimeReport.ExperimentalTapDiagnostics.self, from: historical)
        precondition(legacy.registeredTap?.rows.first?.timing == nil && legacy.postDelayRegisteredTap == nil)
        let timingObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(timing)) as! [String: Any]
        for change in [["maxUsecLatency": -1], ["options": -1], ["eventText": "b"]] as [[String: Any]] {
            var badTiming = timingObject; badTiming.merge(change) { _, new in new }
            do {
                _ = try JSONDecoder().decode(SessionRuntimeReport.RegisteredTapObservation.Row.Timing.self,
                                             from: JSONSerialization.data(withJSONObject: badTiming))
                fatalError("invalid tap timing accepted")
            } catch {}
        }

        print("tapTimeoutReportSchema=roundtrip oldReportsCompatible=true unknownFieldRefused=true unknownStatusRefused=true")
    }
}
