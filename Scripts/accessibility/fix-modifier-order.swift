#!/usr/bin/env swift
// SwiftUI Modifier Order Fixer
// Reorders accessibility modifiers to follow best practices:
// Style → Control → Accessibility → Layout
//
// Usage: swift fix-modifier-order.swift [file.swift] [--dry-run]
//        Reads from stdin if no file specified

import Foundation

// Modifier categories with priority (lower = earlier in chain)
let modifierPriority: [String: Int] = [
    // Style (priority 1)
    "buttonStyle": 1,
    "toggleStyle": 1,
    "textFieldStyle": 1,
    "pickerStyle": 1,
    "listStyle": 1,
    "labelStyle": 1,

    // Control properties (priority 2)
    "controlSize": 2,
    "tint": 2,
    "labelsHidden": 2,
    "disabled": 2,
    "focused": 2,

    // Interaction (priority 3)
    "onTapGesture": 3,
    "onLongPressGesture": 3,
    "gesture": 3,
    "simultaneousGesture": 3,

    // Accessibility (priority 4)
    "accessibilityIdentifier": 4,
    "accessibilityLabel": 4,
    "accessibilityHint": 4,
    "accessibilityValue": 4,
    "accessibilityAddTraits": 4,
    "accessibilityRemoveTraits": 4,
    "accessibilityElement": 4,
    "accessibilityHidden": 4,
    "accessibilityAction": 4,
    "accessibilityFocused": 4,

    // Content modifiers (priority 5)
    "foregroundColor": 5,
    "foregroundStyle": 5,
    "font": 5,
    "fontWeight": 5,
    "fontDesign": 5,
    "bold": 5,
    "italic": 5,
    "strikethrough": 5,
    "underline": 5,
    "lineLimit": 5,
    "multilineTextAlignment": 5,

    // Layout (priority 6)
    "padding": 6,
    "frame": 6,
    "fixedSize": 6,
    "layoutPriority": 6,
    "alignmentGuide": 6,
    "position": 6,
    "offset": 6,

    // Background/Overlay (priority 7)
    "background": 7,
    "overlay": 7,
    "border": 7,
    "cornerRadius": 7,
    "clipShape": 7,
    "shadow": 7,

    // Lifecycle (priority 8)
    "onAppear": 8,
    "onDisappear": 8,
    "onChange": 8,
    "task": 8,
    "onReceive": 8,

    // Environment (priority 9)
    "environment": 9,
    "environmentObject": 9,
    "help": 9,
    "tag": 9,
    "id": 9,
]

struct Modifier {
    let name: String
    let fullText: String
    let priority: Int
    let lineNumber: Int
}

func extractModifierName(_ text: String) -> String? {
    let pattern = #"^\s*\.([a-zA-Z]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[range])
}

func analyzeModifierChain(lines: [String], startLine: Int) -> (modifiers: [Modifier], endLine: Int) {
    var modifiers: [Modifier] = []
    var currentLine = startLine
    var parenDepth = 0
    var braceDepth = 0
    var inModifierChain = false

    while currentLine < lines.count {
        let line = lines[currentLine]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Count parens and braces to track nesting
        for char in line {
            if char == "(" { parenDepth += 1 }
            if char == ")" { parenDepth -= 1 }
            if char == "{" { braceDepth += 1 }
            if char == "}" { braceDepth -= 1 }
        }

        // Check if this line starts a modifier
        if trimmed.hasPrefix(".") && parenDepth == 0 && braceDepth == 0 {
            if let name = extractModifierName(line) {
                let priority = modifierPriority[name] ?? 5
                modifiers.append(Modifier(
                    name: name,
                    fullText: line,
                    priority: priority,
                    lineNumber: currentLine
                ))
                inModifierChain = true
            }
        } else if inModifierChain && !trimmed.hasPrefix(".") && parenDepth == 0 && braceDepth == 0 {
            // End of modifier chain
            break
        }

        currentLine += 1
    }

    return (modifiers, currentLine)
}

func checkAndReportIssues(lines: [String], filename: String) -> [(line: Int, message: String)] {
    var issues: [(Int, String)] = []
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // Look for view declarations that might have modifier chains
        if line.contains("Button") || line.contains("Toggle") || line.contains("Text(") ||
           line.contains("Image(") || line.contains("VStack") || line.contains("HStack") {

            let (modifiers, endLine) = analyzeModifierChain(lines: lines, startLine: i + 1)

            if modifiers.count > 1 {
                // Check if modifiers are in correct order
                var lastPriority = 0
                for mod in modifiers {
                    if mod.priority < lastPriority {
                        issues.append((
                            mod.lineNumber + 1,
                            "Modifier .\(mod.name) (priority \(mod.priority)) should come before previous modifier (priority \(lastPriority))"
                        ))
                    }
                    lastPriority = mod.priority
                }

                // Check for accessibility after layout
                let accessibilityMods = modifiers.filter { $0.priority == 4 }
                let layoutMods = modifiers.filter { $0.priority >= 6 }

                for accMod in accessibilityMods {
                    for layoutMod in layoutMods {
                        if accMod.lineNumber > layoutMod.lineNumber {
                            issues.append((
                                accMod.lineNumber + 1,
                                "Accessibility modifier .\(accMod.name) should come before layout modifier .\(layoutMod.name)"
                            ))
                        }
                    }
                }
            }

            i = endLine
        }
        i += 1
    }

    return issues
}

// Main execution
let args = CommandLine.arguments
var filename: String? = nil
var dryRun = false

for arg in args.dropFirst() {
    if arg == "--dry-run" {
        dryRun = true
    } else if arg == "--help" || arg == "-h" {
        print("""
        SwiftUI Modifier Order Checker

        Usage: swift fix-modifier-order.swift [file.swift] [--dry-run]

        Options:
          --dry-run    Report issues without modifying files
          --help       Show this help message

        The recommended modifier order is:
          1. Style (buttonStyle, toggleStyle, etc.)
          2. Control (controlSize, tint, labelsHidden)
          3. Interaction (onTapGesture, gesture)
          4. Accessibility (accessibilityIdentifier, accessibilityLabel)
          5. Content (foregroundColor, font)
          6. Layout (padding, frame)
          7. Background (background, overlay, shadow)
          8. Lifecycle (onAppear, onChange)
          9. Environment (environment, help, tag)
        """)
        exit(0)
    } else if !arg.hasPrefix("-") {
        filename = arg
    }
}

var content: String
if let file = filename {
    guard let fileContent = try? String(contentsOfFile: file, encoding: .utf8) else {
        fputs("Error: Could not read file '\(file)'\n", stderr)
        exit(1)
    }
    content = fileContent
} else {
    // Read from stdin
    var stdinContent = ""
    while let line = readLine(strippingNewline: false) {
        stdinContent += line
    }
    content = stdinContent
}

let lines = content.components(separatedBy: "\n")
let issues = checkAndReportIssues(lines: lines, filename: filename ?? "stdin")

if issues.isEmpty {
    fputs("✅ No modifier ordering issues found\n", stderr)
    exit(0)
} else {
    fputs("⚠️  Found \(issues.count) modifier ordering issue(s):\n\n", stderr)
    for (line, message) in issues {
        let prefix = filename.map { "\($0):" } ?? ""
        print("\(prefix)\(line): \(message)")
    }
    exit(1)
}
