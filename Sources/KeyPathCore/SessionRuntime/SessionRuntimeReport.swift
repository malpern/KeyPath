import Foundation

/// Private, nonce-bound evidence from the independently launched app process.
/// Contains capabilities and emitted-key cleanup state, never captured input or text.
public struct SessionRuntimeReport: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case capabilities, starting, running, secureInput, stopped, failed
    }

    /// Bounded, compile-gated diagnostics for the tap-timeout experiment.
    /// Values contain no event payload, path, process arguments, or raw error text.
    public struct ExperimentalTapTimeoutDiagnostic: Codable, Sendable, Equatable {
        public enum Initialization: String, Codable, Sendable {
            case notAttempted, initialized, executableUnavailable, identityDigestUnavailable
            case unexpectedFailure
        }

        public enum Preparation: String, Codable, Sendable {
            case notAttempted, identityRefused, directoryRefused, commandUnavailable
            case commandMetadataRefused, commandChangedDuringRead, commandMalformed, commandAdmitted
        }

        public enum CallbackFirstResult: String, Codable, Sendable {
            case notObserved, alreadySpent, commandNotPrepared, triggerCodeMismatch, repeatEvent
            case mappedInput, heldOutputMismatch, environmentStale, secureInput, commandExpired
            case reportAgeInvalid, delayExceedsBudget, workerIdentityChanged, ownerUnavailable
            case directoryChanged, enteredReceiptRefused, delayAdmitted
        }

        public let initialization: Initialization
        public let preparation: Preparation
        public let callbackFirstResult: CallbackFirstResult

        public init(initialization: Initialization, preparation: Preparation,
                    callbackFirstResult: CallbackFirstResult)
        {
            self.initialization = initialization
            self.preparation = preparation
            self.callbackFirstResult = callbackFirstResult
        }

        private enum CodingKeys: String, CodingKey, CaseIterable { case initialization, preparation, callbackFirstResult }
        private struct Field: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue _: Int) { return nil }
        }
        public init(from decoder: Decoder) throws {
            let all = try decoder.container(keyedBy: Field.self)
            guard Set(all.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Unexpected tap-timeout diagnostic fields"))
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            initialization = try values.decode(Initialization.self, forKey: .initialization)
            preparation = try values.decode(Preparation.self, forKey: .preparation)
            callbackFirstResult = try values.decode(CallbackFirstResult.self, forKey: .callbackFirstResult)
        }
    }

    /// Experimental-only observations; no event content or permission inference.
    /// configSHA256 samples the config file immediately after runtime creation.
    /// It does not attest to the parser's in-memory bytes during a concurrent edit.
    public struct ExperimentalTapDiagnostics: Codable, Sendable, Equatable {
        public let rawTapCallbackCount: UInt64
        public let qMapped: Bool
        public let aMapped: Bool
        public let configSHA256: String?
        public let registeredTap: RegisteredTapObservation?

        public init(rawTapCallbackCount: UInt64, qMapped: Bool, aMapped: Bool, configSHA256: String?, registeredTap: RegisteredTapObservation? = nil) {
            self.rawTapCallbackCount = rawTapCallbackCount
            self.qMapped = qMapped
            self.aMapped = aMapped
            self.configSHA256 = configSHA256
            self.registeredTap = registeredTap
        }

        private enum CodingKeys: String, CodingKey { case rawTapCallbackCount, qMapped, aMapped, configSHA256, registeredTap }
        private struct Field: CodingKey {
            let stringValue: String
            var intValue: Int? {
                nil
            }

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue _: Int) {
                nil
            }
        }

        public init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: Field.self)
            let actual = Set(fields.allKeys.map(\.stringValue))
            let required: Set = ["rawTapCallbackCount", "qMapped", "aMapped"]
            guard required.isSubset(of: actual), actual.isSubset(of: required.union(["configSHA256", "registeredTap"])) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected experimental tap diagnostics fields"))
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rawTapCallbackCount = try values.decode(UInt64.self, forKey: .rawTapCallbackCount)
            qMapped = try values.decode(Bool.self, forKey: .qMapped)
            aMapped = try values.decode(Bool.self, forKey: .aMapped)
            configSHA256 = try values.decodeIfPresent(String.self, forKey: .configSHA256)
            registeredTap = try values.decodeIfPresent(RegisteredTapObservation.self, forKey: .registeredTap)
            if let configSHA256, configSHA256.count != 64 || !configSHA256.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) }) {
                throw DecodingError.dataCorruptedError(forKey: .configSHA256, in: values, debugDescription: "Invalid experimental config digest")
            }
        }
    }

    /// One experimental worker-self registration observation; not delivery proof.
    /// CGGetEventTapList resets minimum/maximum latency statistics for all enumerated taps.
    public struct RegisteredTapObservation: Codable, Sendable, Equatable {
        public enum Outcome: String, Codable, Sendable {
            case observed, absent, multiple, apiFailure, capacityExceeded, unexpectedABI
        }

        public struct Row: Codable, Sendable, Equatable {
            public let mask: UInt64
            public let enabled: Bool
            public init(mask: UInt64, enabled: Bool) {
                self.mask = mask; self.enabled = enabled
            }

            private enum CodingKeys: String, CodingKey { case mask, enabled }
            public init(from decoder: Decoder) throws {
                let all = try decoder.container(keyedBy: Field.self)
                guard Set(all.allKeys.map(\.stringValue)) == Set(["mask", "enabled"]) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected registered tap row fields"))
                }
                let c = try decoder.container(keyedBy: CodingKeys.self)
                mask = try c.decode(UInt64.self, forKey: .mask)
                enabled = try c.decode(Bool.self, forKey: .enabled)
            }
        }

        public let outcome: Outcome
        public let requestedMask: UInt64
        public let rows: [Row]
        public let rawAccessibility: String
        public let rawPostEvent: String
        public let rawListenEvent: String
        public let queryLimit: UInt32
        public let enumerationAttempted: Bool

        public init(outcome: Outcome, requestedMask: UInt64, rows: [Row], rawAccessibility: String,
                    rawPostEvent: String, rawListenEvent: String, enumerationAttempted: Bool)
        {
            self.outcome = outcome; self.requestedMask = requestedMask; self.rows = rows
            self.rawAccessibility = rawAccessibility; self.rawPostEvent = rawPostEvent
            self.rawListenEvent = rawListenEvent; queryLimit = 128
            self.enumerationAttempted = enumerationAttempted
        }

        /// Registered bits only; this does not establish enabled state or delivery/readiness.
        public var requestedBitsPresent: Bool {
            outcome == .observed && rows.count == 1 && rows[0].mask & requestedMask == requestedMask
        }

        private enum CodingKeys: String, CodingKey {
            case outcome, requestedMask, rows, rawAccessibility, rawPostEvent, rawListenEvent, queryLimit, enumerationAttempted
        }

        private struct Field: CodingKey {
            let stringValue: String
            var intValue: Int? {
                nil
            }

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue _: Int) {
                nil
            }
        }

        public init(from decoder: Decoder) throws {
            let all = try decoder.container(keyedBy: Field.self)
            guard Set(all.allKeys.map(\.stringValue)) == Set(["outcome", "requestedMask", "rows", "rawAccessibility", "rawPostEvent", "rawListenEvent", "queryLimit", "enumerationAttempted"]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected registered tap observation fields"))
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            outcome = try c.decode(Outcome.self, forKey: .outcome)
            requestedMask = try c.decode(UInt64.self, forKey: .requestedMask)
            rows = try c.decode([Row].self, forKey: .rows)
            rawAccessibility = try c.decode(String.self, forKey: .rawAccessibility)
            rawPostEvent = try c.decode(String.self, forKey: .rawPostEvent)
            rawListenEvent = try c.decode(String.self, forKey: .rawListenEvent)
            queryLimit = try c.decode(UInt32.self, forKey: .queryLimit)
            enumerationAttempted = try c.decode(Bool.self, forKey: .enumerationAttempted)
            let statuses = Set(["granted", "denied", "unknown", "error"])
            guard requestedMask == 7168, queryLimit == 128, rows.count <= 128,
                  enumerationAttempted == (outcome != .unexpectedABI),
                  [rawAccessibility, rawPostEvent, rawListenEvent].allSatisfy({ statuses.contains($0) }),
                  outcome == .observed ? rows.count == 1 : outcome == .multiple ? rows.count > 1 : rows.isEmpty
            else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid registered tap observation")) }
        }
    }

    public let nonce: String
    public let pid: Int32
    public let uid: UInt32
    public let state: State
    public let accessibility: Bool
    /// Effective session output authorization; inputAccessSource identifies the API.
    /// Older reports used ListenEvent; new modifying-tap workers use PostEvent.
    public let effectiveInputAccess: Bool
    public let inputAccessSource: String?
    public let tapActive: Bool
    public let tcpPort: UInt16
    public let inputCount: UInt64
    public let outputCount: UInt64
    public let timestamp: Date
    public let failure: String?
    public let heldOutputUsages: [UInt32]
    public let experimentalTapDiagnostics: ExperimentalTapDiagnostics?
    public let experimentalTapTimeout: ExperimentalTapTimeoutDiagnostic?

    public init(
        nonce: String, pid: Int32, uid: UInt32, state: State,
        accessibility: Bool, effectiveInputAccess: Bool, tapActive: Bool,
        tcpPort: UInt16, inputCount: UInt64, outputCount: UInt64,
        timestamp: Date = Date(), failure: String? = nil, heldOutputUsages: [UInt32] = [],
        inputAccessSource: String? = nil, experimentalTapDiagnostics: ExperimentalTapDiagnostics? = nil,
        experimentalTapTimeout: ExperimentalTapTimeoutDiagnostic? = nil
    ) {
        self.nonce = nonce
        self.pid = pid
        self.uid = uid
        self.state = state
        self.accessibility = accessibility
        self.effectiveInputAccess = effectiveInputAccess
        self.inputAccessSource = inputAccessSource
        self.tapActive = tapActive
        self.tcpPort = tcpPort
        self.inputCount = inputCount
        self.outputCount = outputCount
        self.timestamp = timestamp
        self.failure = failure
        self.heldOutputUsages = heldOutputUsages
        self.experimentalTapDiagnostics = experimentalTapDiagnostics
        self.experimentalTapTimeout = experimentalTapTimeout
    }

    /// Cleanup evidence remains useful after a stalled worker dies. Callers must
    /// confirm termination separately before replaying this launch's ledger.
    public func belongsTo(nonce: String, pid: Int32, uid: UInt32) -> Bool {
        self.nonce == nonce && self.pid == pid && self.uid == uid
    }

    public func isCurrent(nonce: String, pid: Int32, uid: UInt32, now: Date) -> Bool {
        belongsTo(nonce: nonce, pid: pid, uid: uid)
            && timestamp <= now.addingTimeInterval(1)
            && now.timeIntervalSince(timestamp) <= 2
    }

    #if KEYPATH_TAP_TIMEOUT_EXPERIMENT
        /// Formats a bounded terminal-startup record for local diagnostics only.
        /// This never authorizes startup or changes cleanup behavior.
        public func experimentalTerminalStartupDiagnosticJSON(
            parentPID: Int32, expectedWorkerPID: Int32, expectedUID: UInt32,
            expectedNonce: String, launchGeneration: UInt64, now: Date
        ) -> String? {
            let age = now.timeIntervalSince(timestamp)
            guard state == .failed, let failure, !failure.isEmpty,
                  inputCount == 0, outputCount == 0, heldOutputUsages.isEmpty,
                  age >= 0, age <= 2,
                  isCurrent(nonce: expectedNonce, pid: expectedWorkerPID, uid: expectedUID, now: now)
            else { return nil }

            let safeFailure = failure.unicodeScalars.prefix(160).map { scalar in
                let value = scalar.value
                return (0x20 ... 0x7E).contains(value) ? String(scalar) : "_"
            }.joined()
            guard let reportData = try? JSONEncoder().encode(self),
                  let reportObject = try? JSONSerialization.jsonObject(with: reportData) as? [String: Any]
            else { return nil }
            let payload: [String: Any] = [
                "schema": "keypath.session-start-terminal.v1",
                "parentPID": parentPID,
                "workerPID": expectedWorkerPID,
                "uid": expectedUID,
                "launchGeneration": launchGeneration,
                "nonce": expectedNonce,
                "capturedAtUnixMilliseconds": Int64((now.timeIntervalSince1970 * 1000).rounded()),
                "reportTimestampUnixMilliseconds": Int64((timestamp.timeIntervalSince1970 * 1000).rounded()),
                "reportAgeMilliseconds": Int((age * 1000).rounded()),
                "failureSummary": safeFailure,
                "report": reportObject
            ]

            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  data.count <= 16384,
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }
    #endif
}
