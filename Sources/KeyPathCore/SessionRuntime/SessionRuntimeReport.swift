import Foundation

/// Private, nonce-bound evidence from the independently launched app process.
/// Contains capabilities and emitted-key cleanup state, never captured input or text.
public struct SessionRuntimeReport: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable {
        case capabilities, starting, running, secureInput, stopped, failed
    }

    /// Experimental-only observations; no event content or permission inference.
    /// configSHA256 samples the config file immediately after runtime creation.
    /// It does not attest to the parser's in-memory bytes during a concurrent edit.
    public struct ExperimentalTapDiagnostics: Codable, Sendable, Equatable {
        public let rawTapCallbackCount: UInt64
        public let qMapped: Bool
        public let aMapped: Bool
        public let configSHA256: String?

        public init(rawTapCallbackCount: UInt64, qMapped: Bool, aMapped: Bool, configSHA256: String?) {
            self.rawTapCallbackCount = rawTapCallbackCount
            self.qMapped = qMapped
            self.aMapped = aMapped
            self.configSHA256 = configSHA256
        }

        private enum CodingKeys: String, CodingKey { case rawTapCallbackCount, qMapped, aMapped, configSHA256 }
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
            guard required.isSubset(of: actual), actual.isSubset(of: required.union(["configSHA256"])) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected experimental tap diagnostics fields"))
            }
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rawTapCallbackCount = try values.decode(UInt64.self, forKey: .rawTapCallbackCount)
            qMapped = try values.decode(Bool.self, forKey: .qMapped)
            aMapped = try values.decode(Bool.self, forKey: .aMapped)
            configSHA256 = try values.decodeIfPresent(String.self, forKey: .configSHA256)
            if let configSHA256, configSHA256.count != 64 || !configSHA256.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 102).contains($0) }) {
                throw DecodingError.dataCorruptedError(forKey: .configSHA256, in: values, debugDescription: "Invalid experimental config digest")
            }
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

    public init(
        nonce: String, pid: Int32, uid: UInt32, state: State,
        accessibility: Bool, effectiveInputAccess: Bool, tapActive: Bool,
        tcpPort: UInt16, inputCount: UInt64, outputCount: UInt64,
        timestamp: Date = Date(), failure: String? = nil, heldOutputUsages: [UInt32] = [],
        inputAccessSource: String? = nil, experimentalTapDiagnostics: ExperimentalTapDiagnostics? = nil
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
}
