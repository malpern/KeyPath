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

        print("tapTimeoutReportSchema=roundtrip oldReportsCompatible=true unknownFieldRefused=true unknownStatusRefused=true")
    }
}
