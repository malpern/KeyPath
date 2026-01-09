import Foundation

public struct ChordGroupConfig: Codable, Equatable, Sendable {
    public struct ChordDefinition: Codable, Equatable, Sendable {
        public var keys: [String]
        public var action: String

        public init(keys: [String], action: String) {
            self.keys = keys
            self.action = action
        }
    }

    public var name: String
    public var timeoutToken: String
    public var chords: [ChordDefinition]

    public init(name: String, timeoutToken: String, chords: [ChordDefinition]) {
        self.name = name
        self.timeoutToken = timeoutToken
        self.chords = chords
    }

    public var keySet: Set<String> {
        Set(chords.flatMap { $0.keys })
    }
}
