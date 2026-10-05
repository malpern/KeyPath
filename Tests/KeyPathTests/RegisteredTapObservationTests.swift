import Foundation
@testable import KeyPathCore
import Testing
#if KEYPATH_TAP_TIMEOUT_EXPERIMENT
    import CoreGraphics
    @testable import KeyPathAppKit
#endif

struct RegisteredTapObservationTests {
    typealias Observation = SessionRuntimeReport.RegisteredTapObservation
    func observation(_ outcome: Observation.Outcome = .observed, rows: [Observation.Row] = [.init(mask: 7168, enabled: true)]) -> Observation {
        Observation(outcome: outcome, requestedMask: 7168, rows: rows, rawAccessibility: "granted",
                    rawPostEvent: "granted", rawListenEvent: "denied", enumerationAttempted: outcome != .unexpectedABI)
    }

    @Test func missingKeyboardBitsAreDifferentFromRegistrationFailure() throws {
        #expect(observation().requestedBitsPresent)
        let clipped = observation(rows: [.init(mask: 4096, enabled: true)])
        #expect(!clipped.requestedBitsPresent)
        #expect(clipped.outcome == .observed)
        #expect(clipped.rawListenEvent == "denied")
        for outcome in [Observation.Outcome.absent, .apiFailure, .capacityExceeded, .unexpectedABI] {
            let value = observation(outcome, rows: [])
            #expect(!value.requestedBitsPresent)
            #expect(try JSONDecoder().decode(Observation.self, from: JSONEncoder().encode(value)) == value)
        }
        #expect(!observation(.multiple, rows: [.init(mask: 7168, enabled: true), .init(mask: 4096, enabled: true)]).requestedBitsPresent)
    }

    @Test func historicalDiagnosticsDecodeAndStrictNewEvidenceRoundTrips() throws {
        let old = Data(#"{"rawTapCallbackCount":0,"qMapped":true,"aMapped":true}"#.utf8)
        #expect(try JSONDecoder().decode(SessionRuntimeReport.ExperimentalTapDiagnostics.self, from: old).registeredTap == nil)
        let value = SessionRuntimeReport.ExperimentalTapDiagnostics(rawTapCallbackCount: 4, qMapped: true, aMapped: true, configSHA256: nil, registeredTap: observation())
        #expect(try JSONDecoder().decode(SessionRuntimeReport.ExperimentalTapDiagnostics.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func invalidAmbiguousOrUnknownEvidenceRefuses() throws {
        let raw = try JSONEncoder().encode(observation())
        let base = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        for change in [
            ["outcome": "absent"],
            ["rawListenEvent": "allowed"],
            ["queryLimit": 129],
            ["enumerationAttempted": false],
            ["requestedMask": 4096],
            ["extra": true],
            ["rows": [["mask": 4096, "enabled": true, "pid": 123]]]
        ] as [[String: Any]] {
            var value = base
            value.merge(change) { _, new in new }
            let data = try JSONSerialization.data(withJSONObject: value)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(Observation.self, from: data) }
        }
    }

    #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
        @Test @MainActor func actualQueryAssemblyFiltersAndClassifies() {
            typealias O = Observation

            func tap(_ pid: Int32 = 42, _ location: CGEventTapLocation = .cgSessionEventTap, _ options: CGEventTapOptions = .defaultTap) -> CGEventTapInformation {
                var row = CGEventTapInformation(); row.tappingProcess = pid; row.tapPoint = location; row.options = options; row.eventsOfInterest = 7168; row.enabled = true; return row
            }
            func classify(_ rows: [CGEventTapInformation], _ count: UInt32? = nil, _ error: CGError = .success, _ abi: Bool = true) -> O {
                SessionRuntimeWorker.classifyRegisteredTaps(
                    requestedMask: 7168,
                    taps: rows,
                    count: count ?? UInt32(rows.count),
                    error: error,
                    abiIsExpected: abi,
                    ownPID: 42,
                    accessibility: "granted",
                    posting: "granted",
                    listening: "denied"
                )
            }
            precondition(classify([tap(9), tap(42, .cghidEventTap), tap(42, .cgSessionEventTap, .listenOnly)]).outcome == .absent)
            precondition(classify([tap(9), tap()]).rows == [.init(mask: 7168, enabled: true)])
            precondition(classify([tap(), tap()]).outcome == .multiple)
            precondition(classify([]).outcome == .absent)
            precondition(classify([], 0, .failure).outcome == .apiFailure)
            precondition(classify([], 129).outcome == .capacityExceeded)
            precondition(classify([], 1).outcome == .capacityExceeded)
            let noQuery = classify([], 0, .failure, false); precondition(noQuery.outcome == .unexpectedABI && !noQuery.enumerationAttempted)
        }

        @Test @MainActor func startupAdmissionDistinguishesClippedUnverifiedAndDisabledRegistration() {
            #expect(SessionRuntimeWorker.registeredTapStartupFailure(observation()) == nil)
            #expect(SessionRuntimeWorker.registeredTapStartupFailure(observation(rows: [.init(mask: 4096, enabled: true)])) == "modifying-tap-missing-requested-events")
            let disabled = observation(rows: [.init(mask: 7168, enabled: false)])
            #expect(disabled.requestedBitsPresent)
            #expect(SessionRuntimeWorker.registeredTapStartupFailure(disabled) == "modifying-tap-not-enabled")
            for outcome in [Observation.Outcome.absent, .apiFailure, .capacityExceeded, .unexpectedABI] {
                #expect(SessionRuntimeWorker.registeredTapStartupFailure(observation(outcome, rows: [])) == "modifying-tap-registration-unverified")
            }
            #expect(SessionRuntimeWorker
                .registeredTapStartupFailure(observation(.multiple, rows: [.init(mask: 7168, enabled: true), .init(mask: 7168, enabled: true)])) == "modifying-tap-registration-unverified")
            #expect(SessionRuntimeWorker.registeredTapStartupFailure(nil) == "modifying-tap-registration-unavailable")
        }

        @Test @MainActor func startupAdmissionUsesRegisteredMaskInsteadOfListenPermission() {
            let fullListenDenied = observation()
            #expect(fullListenDenied.rawListenEvent == "denied")
            #expect(SessionRuntimeWorker.registeredTapStartupFailure(fullListenDenied) == nil)
            let clippedListenGranted = Observation(outcome: .observed, requestedMask: 7168,
                                                   rows: [.init(mask: 4096, enabled: true)], rawAccessibility: "granted", rawPostEvent: "granted",
                                                   rawListenEvent: "granted", enumerationAttempted: true)
            #expect(SessionRuntimeWorker.registeredTapStartupFailure(clippedListenGranted) == "modifying-tap-missing-requested-events")
        }

        @Test @MainActor func actualSDKLayoutMatchesCheckedWorkerABI() {
            #expect(SessionRuntimeWorker.experimentalTapABIIsExpected)
        }
    #endif
}
