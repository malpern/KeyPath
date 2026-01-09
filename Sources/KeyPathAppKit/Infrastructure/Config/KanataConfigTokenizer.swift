import Foundation

enum KanataConfigTokenizer {
    static func stripInlineComment(_ line: String) -> String {
        guard let index = line.firstIndex(of: ";") else { return line }
        return String(line[..<index])
    }

    /// Tokenize a Kanata config line while keeping parenthesized expressions intact.
    static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0

        for char in line {
            if char == "(" {
                depth += 1
                current.append(char)
            } else if char == ")" {
                depth = max(0, depth - 1)
                current.append(char)
                if depth == 0, !current.isEmpty {
                    tokens.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            } else if char.isWhitespace, depth == 0 {
                if !current.isEmpty {
                    tokens.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current.trimmingCharacters(in: .whitespaces))
        }

        return tokens
    }
}
