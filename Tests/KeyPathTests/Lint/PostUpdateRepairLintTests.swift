import Foundation
@preconcurrency import XCTest

/// Guards Phase 1 Workstream 3's post-update repair boundary.
///
/// Sparkle relaunch callbacks are detection/surfacing hooks, not user repair
/// gestures. After an update, KeyPath may inspect system state and refresh the
/// status UI, but it must not run `InstallerEngine.run(intent: .repair)` or
/// `runSingleAction` automatically. Users start repair explicitly from the
/// normal status/wizard/CLI surfaces.
final class PostUpdateRepairLintTests: XCTestCase {
    func testSparkleWaitsForRuntimeShutdownBeforeInstallingUpdate() throws {
        let updateService = phase1W3RepositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/UpdateService.swift")
        let contents = try String(contentsOf: updateService, encoding: .utf8)

        guard let postponementBody = extractFunctionBody(
            containing: "shouldPostponeRelaunchForUpdate item",
            from: contents
        ), let preparationBody = extractFunctionBody(
            containing: "private func prepareForUpdate(version:",
            from: contents
        ), let willInstallBody = extractFunctionBody(
            containing: "willInstallUpdate item",
            from: contents
        ) else {
            return
        }

        XCTAssertTrue(postponementBody.contains("await prepareForUpdate(version: version)"))
        XCTAssertTrue(postponementBody.contains("defer"))
        XCTAssertTrue(postponementBody.contains("handler.invoke()"))
        XCTAssertTrue(postponementBody.contains("return true"))
        XCTAssertTrue(preparationBody.contains("runSingleAction(.terminateConflictingProcesses"))
        XCTAssertFalse(preparationBody.contains("run(intent: .repair"))
        XCTAssertFalse(
            willInstallBody.contains("prepareForUpdate"),
            "Sparkle does not await willInstallUpdate; preparation must happen in its postponement callback."
        )
    }

    func testPostUpdateFinalizeDoesNotRunAutomaticRepair() throws {
        let updateService = phase1W3RepositoryRoot()
            .appendingPathComponent("Sources/KeyPathAppKit/Services/UpdateService.swift")
        let contents = try String(contentsOf: updateService, encoding: .utf8)

        guard let finalizeBody = extractFunctionBody(
            named: "finalizeUpdate",
            from: contents
        ) else {
            return
        }

        let forbiddenPatterns = [
            #"run\s*\(\s*intent:\s*\.repair"#,
            #"runSingleAction\s*\("#,
            #"PrivilegeBroker\s*\("#
        ]
        let violations = try forbiddenPatterns.flatMap { pattern -> [String] in
            let regex = try NSRegularExpression(pattern: pattern)
            return finalizeBody.components(separatedBy: .newlines).enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { return nil }
                let range = NSRange(line.startIndex..., in: line)
                guard regex.firstMatch(in: line, range: range) != nil else { return nil }
                return "finalizeUpdate:\(index + 1): \(trimmed)"
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            Post-update detection must not mutate installer/system services. \
            Surface degraded state and require an explicit user repair action:
            \(violations.sorted().joined(separator: "\n"))
            """
        )
    }
}

private func extractFunctionBody(
    containing signatureFragment: String,
    from contents: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> String? {
    guard let signatureRange = contents.range(of: signatureFragment) else {
        XCTFail("Could not find function containing \(signatureFragment)", file: file, line: line)
        return nil
    }
    guard let openBrace = contents[signatureRange.lowerBound...].firstIndex(of: "{") else {
        XCTFail("Could not find opening brace for \(signatureFragment)", file: file, line: line)
        return nil
    }

    var depth = 0
    var cursor = openBrace
    while cursor < contents.endIndex {
        let char = contents[cursor]
        if char == "{" {
            depth += 1
        } else if char == "}" {
            depth -= 1
            if depth == 0 {
                let bodyStart = contents.index(after: openBrace)
                return String(contents[bodyStart ..< cursor])
            }
        }
        cursor = contents.index(after: cursor)
    }

    XCTFail("Could not find closing brace for \(signatureFragment)", file: file, line: line)
    return nil
}

private func extractFunctionBody(
    named functionName: String,
    from contents: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> String? {
    guard let nameRange = contents.range(of: "func \(functionName)") else {
        XCTFail("Could not find func \(functionName)", file: file, line: line)
        return nil
    }
    guard let openBrace = contents[nameRange.lowerBound...].firstIndex(of: "{") else {
        XCTFail("Could not find opening brace for \(functionName)", file: file, line: line)
        return nil
    }

    var depth = 0
    var cursor = openBrace
    while cursor < contents.endIndex {
        let char = contents[cursor]
        if char == "{" {
            depth += 1
        } else if char == "}" {
            depth -= 1
            if depth == 0 {
                let bodyStart = contents.index(after: openBrace)
                return String(contents[bodyStart ..< cursor])
            }
        }
        cursor = contents.index(after: cursor)
    }

    XCTFail("Could not find closing brace for \(functionName)", file: file, line: line)
    return nil
}

private func phase1W3RepositoryRoot(file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}
