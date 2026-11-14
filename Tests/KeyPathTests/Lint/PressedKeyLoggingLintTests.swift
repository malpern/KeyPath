import Foundation
import XCTest

/// Release builds must never write the keys a user presses (PRIVACY.md).
/// In the files that see key presses, any log line that interpolates a key
/// name or a raw engine line goes through `AppLogger.pressedKey`, which is
/// compiled out of release builds. A plain `log`, `info`, `debug` or `warn`
/// call there would write it, since `KEYPATH_LOG_LEVEL` works in release.
final class PressedKeyLoggingLintTests: XCTestCase {
    private static let files = [
        "Sources/KeyPathAppKit/Services/KeyboardCapture/KeyboardCapture.swift",
        "Sources/KeyPathAppKit/Services/KeyboardCapture/KeyboardCapture+TCP.swift",
        "Sources/KeyPathAppKit/Services/Monitoring/KanataEventListener.swift",
        "Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel+TCP.swift",
    ]
    /// Interpolations that carry a pressed key or an engine frame.
    /// Any interpolation whose expression names a key (`key`, `keys`, `keyName`,
    /// `keyPress.baseKey`, `pressedKeyCodes`, ...) or a raw engine `line`.
    private static let keyInterpolation = try! NSRegularExpression(
        pattern: #"\\\([^)]*([kK]ey|\bline\b)[^)]*\)"#
    )
    /// A comment on the line before marks a key that comes from the config, not a press.
    private static let configMarker = "not a key press"

    static func violations(in source: String) -> [Int] {
        let lines = source.components(separatedBy: "\n")
        var found: [Int] = []
        // The logger call a line belongs to: the nearest preceding line that opens one.
        var currentCall: String?
        var markedFromConfig = false
        for (index, line) in lines.enumerated() {
            if let range = line.range(of: #"AppLogger\.shared\.(\w+)\("#, options: .regularExpression) {
                currentCall = String(line[range])
                markedFromConfig = index > 0 && lines[index - 1].contains(configMarker)
            }
            let range = NSRange(line.startIndex..., in: line)
            // A length (`key.utf8.count`) says nothing about which key it was.
            let namesAKey = keyInterpolation.matches(in: line, range: range).contains { match in
                Range(match.range, in: line).map { !line[$0].contains(".count") } ?? false
            }
            guard let call = currentCall, namesAKey else {
                if line.trimmingCharacters(in: .whitespaces).hasSuffix(")") { currentCall = nil }
                continue
            }
            if !call.contains("pressedKey("), !markedFromConfig { found.append(index + 1) }
            if line.trimmingCharacters(in: .whitespaces).hasSuffix(")") { currentCall = nil }
        }
        return found
    }

    func testKeyPressLogsAreReleaseSilent() throws {
        var problems: [String] = []
        for file in Self.files {
            let source = try String(contentsOf: LintScanner.path(file), encoding: .utf8)
            problems += Self.violations(in: source).map { "\(file):\($0)" }
        }
        XCTAssertTrue(problems.isEmpty, """
        These log lines name a pressed key outside AppLogger.pressedKey, so release builds can write them:
        \(problems.joined(separator: "\n"))
        """)
    }

    func testTheCheckCatchesPlainLogCalls() {
        XCTAssertEqual(Self.violations(in: #"AppLogger.shared.log("keyDown: \(keyName)")"#), [1])
        XCTAssertEqual(Self.violations(in: "AppLogger.shared.log(\n    \"keyDown: \\(keyName) code\"\n)"), [2])
        XCTAssertEqual(Self.violations(in: #"AppLogger.shared.debug("Received line: '\(line)'")"#), [1])
        XCTAssertEqual(Self.violations(in: #"AppLogger.shared.pressedKey("keyDown: \(keyName)")"#), [])
        XCTAssertEqual(Self.violations(in: "// from the config, not a key press\nAppLogger.shared.warn(\"x \\(key)\")"), [])
        XCTAssertEqual(Self.violations(in: #"AppLogger.shared.debug("x \(keyPress.baseKey)")"#), [1])
        XCTAssertEqual(Self.violations(in: #"AppLogger.shared.debug("x \(pressedKeyCodes)")"#), [1])
        XCTAssertEqual(Self.violations(in: #"AppLogger.shared.debug("x (\(key.utf8.count) bytes)")"#), [])
    }
}
