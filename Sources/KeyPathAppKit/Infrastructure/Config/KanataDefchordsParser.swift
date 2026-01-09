import Foundation

enum KanataDefchordsParser {
    static func parseGroups(from content: String) -> [ChordGroupConfig] {
        let lines = content.components(separatedBy: .newlines)
        var groups: [ChordGroupConfig] = []
        var currentGroup: ChordGroupConfig?
        var depth = 0

        for line in lines {
            let noComment = KanataConfigTokenizer.stripInlineComment(line)
            let trimmed = noComment.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if currentGroup == nil {
                guard trimmed.hasPrefix("(defchords") else { continue }
                let tokens = KanataConfigTokenizer.tokenize(trimmed)
                guard tokens.count >= 3 else { continue }
                let name = tokens[1]
                let timeoutToken = tokens[2].trimmingCharacters(in: CharacterSet(charactersIn: ")"))
                currentGroup = ChordGroupConfig(name: name, timeoutToken: timeoutToken, chords: [])
                depth = parenDelta(in: noComment)
                if depth <= 0, let group = currentGroup {
                    groups.append(group)
                    currentGroup = nil
                }
                continue
            }

            depth += parenDelta(in: noComment)

            if trimmed == ")" {
                if depth <= 0, let group = currentGroup {
                    groups.append(group)
                    currentGroup = nil
                }
                continue
            }

            let tokens = KanataConfigTokenizer.tokenize(trimmed)
            guard tokens.count >= 2 else { continue }
            let chordToken = tokens[0]
            guard chordToken.hasPrefix("("), chordToken.hasSuffix(")") else { continue }
            let chordBody = String(chordToken.dropFirst().dropLast())
            let chordKeys = chordBody.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let action = tokens[1]
            currentGroup?.chords.append(ChordGroupConfig.ChordDefinition(keys: chordKeys, action: action))

            if depth <= 0, let group = currentGroup {
                groups.append(group)
                currentGroup = nil
            }
        }

        return groups
    }

    static func referencedChordGroups(in mappings: [KeyMapping]) -> Set<String> {
        var names: Set<String> = []
        for mapping in mappings {
            guard let name = parseChordGroupName(from: mapping.output) else { continue }
            names.insert(name)
        }
        return names
    }

    private static func parseChordGroupName(from action: String) -> String? {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("(chord "), trimmed.hasSuffix(")") else { return nil }
        let body = trimmed.dropFirst().dropLast()
        let parts = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 3, parts[0] == "chord" else { return nil }
        return parts[1]
    }

    private static func parenDelta(in line: String) -> Int {
        var delta = 0
        for char in line {
            if char == "(" { delta += 1 }
            if char == ")" { delta -= 1 }
        }
        return delta
    }
}
