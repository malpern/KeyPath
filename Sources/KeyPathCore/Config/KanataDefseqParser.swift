//
//  KanataDefseqParser.swift
//  KeyPath
//
//  Created by Claude Code on 2026-01-09.
//  MAL-45: Kanata Sequences (defseq) UI Support
//
//  Parses Kanata defseq blocks from config files following the MAL-36 preservation pattern.
//

import Foundation

/// Parses Kanata defseq blocks from config files (MAL-36 pattern)
public enum KanataDefseqParser {
    /// A parsed sequence from a Kanata config
    public struct ParsedSequence: Equatable, Sendable {
        public let name: String
        public let keys: [String]

        public init(name: String, keys: [String]) {
            self.name = name
            self.keys = keys
        }
    }

    /// Parse all defseq blocks from config content
    ///
    /// Supports both single-sequence and multi-sequence defseq formats:
    /// ```lisp
    /// (defseq window-leader
    ///   (space w))
    ///
    /// (defseq
    ///   window-leader (space w)
    ///   app-leader (space a))
    /// ```
    public static func parseSequences(from content: String) -> [ParsedSequence] {
        var sequences: [ParsedSequence] = []

        // Remove comments first
        let cleanedContent = removeComments(from: content)

        // Pattern 1: Single sequence format
        // (defseq name (key1 key2))
        let singlePattern = #"\(defseq\s+([\w-]+)\s+\(([^)]+)\)\)"#

        if let singleRegex = try? NSRegularExpression(pattern: singlePattern, options: []) {
            let nsString = cleanedContent as NSString
            let matches = singleRegex.matches(in: cleanedContent, range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                guard match.numberOfRanges == 3 else { continue }

                let name = nsString.substring(with: match.range(at: 1))
                let keysString = nsString.substring(with: match.range(at: 2))
                let keys = keysString.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespaces) }

                if !keys.isEmpty {
                    sequences.append(ParsedSequence(name: name, keys: keys))
                }
            }
        }

        // Pattern 2: Multi-sequence format
        // (defseq
        //   name1 (key1 key2)
        //   name2 (key3 key4))
        let multiPattern = #"\(defseq\s+((?:[^\(\)]+\([^\)]+\)\s*)+)\)"#

        if let multiRegex = try? NSRegularExpression(pattern: multiPattern, options: [.dotMatchesLineSeparators]) {
            let nsString = cleanedContent as NSString
            let matches = multiRegex.matches(in: cleanedContent, range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                guard match.numberOfRanges == 2 else { continue }

                let block = nsString.substring(with: match.range(at: 1))

                // Parse individual name (keys) pairs
                let pairPattern = #"([\w-]+)\s+\(([^)]+)\)"#
                if let pairRegex = try? NSRegularExpression(pattern: pairPattern, options: []) {
                    let pairMatches = pairRegex.matches(in: block, range: NSRange(location: 0, length: (block as NSString).length))

                    for pairMatch in pairMatches {
                        guard pairMatch.numberOfRanges == 3 else { continue }

                        let name = (block as NSString).substring(with: pairMatch.range(at: 1))
                        let keysString = (block as NSString).substring(with: pairMatch.range(at: 2))
                        let keys = keysString.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespaces) }

                        if !keys.isEmpty {
                            sequences.append(ParsedSequence(name: name, keys: keys))
                        }
                    }
                }
            }
        }

        // Deduplicate sequences by name and keys (both patterns might match the same defseq)
        var seen = Set<String>()
        var uniqueSequences: [ParsedSequence] = []

        for sequence in sequences {
            let key = "\(sequence.name):\(sequence.keys.joined(separator:","))"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueSequences.append(sequence)
            }
        }

        return uniqueSequences
    }

    /// Remove Lisp-style comments from content
    private static func removeComments(from content: String) -> String {
        var result = ""
        var inBlockComment = false

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var cleanLine = String(line)

            // Handle block comments
            if cleanLine.contains("#|") {
                inBlockComment = true
            }
            if inBlockComment {
                if cleanLine.contains("|#") {
                    inBlockComment = false
                }
                continue
            }

            // Handle line comments
            if let commentIndex = cleanLine.firstIndex(of: ";") {
                cleanLine = String(cleanLine[..<commentIndex])
            }

            result += cleanLine + "\n"
        }

        return result
    }
}
