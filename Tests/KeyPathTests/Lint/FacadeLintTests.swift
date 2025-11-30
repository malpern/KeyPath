import Foundation
@preconcurrency import XCTest

final class FacadeLintTests: XCTestCase {
    func testAppKitSourcesDoNotBypassInstallerEngine() throws {
        let root = repositoryRoot()
        let appKitRoot = root.appendingPathComponent("Sources/KeyPathAppKit")
        // Allow coordinator and engine internals to reference the coordinator
        let allow = [
            root.appendingPathComponent("Sources/KeyPathAppKit/Core/PrivilegedOperationsCoordinator.swift").path,
            root.appendingPathComponent("Sources/KeyPathAppKit/InstallationWizard/Core/PrivilegeBroker.swift").path,
            root.appendingPathComponent("Sources/KeyPathAppKit/InstallationWizard/Core/InstallerEngine.swift").path,
            root.appendingPathComponent("Sources/KeyPathAppKit/Infrastructure/Privileged/HelperBackedPrivilegedOperations.swift").path,
            root.appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator.swift").path,
            root.appendingPathComponent("Sources/KeyPathAppKit/Managers/RuntimeCoordinator+Lifecycle.swift").path,
            root.appendingPathComponent("Sources/KeyPathAppKit/InstallationWizard/Core/PermissionGrantCoordinator.swift").path
        ]
        let violations = findPattern("PrivilegedOperationsCoordinator\\.shared", in: appKitRoot, allowList: allow)
        if !violations.isEmpty {
            XCTFail("PrivilegedOperationsCoordinator.shared found outside allowlist:\n" + violations.joined(separator: "\n"))
        }
    }

    func testDirectAXChecksAreLimitedToAllowlist() throws {
        let root = repositoryRoot()
        let sourcesDir = root.appendingPathComponent("Sources/KeyPathAppKit")
        let allow = [
            root.appendingPathComponent("Sources/KeyPathAppKit/Services/KeyboardCapture.swift").path,
            root.appendingPathComponent("Sources/KeyPathAppKit/UI/KeyboardVisualization/KeyboardVisualizationViewModel.swift").path,
            root.appendingPathComponent("Sources/KeyPathPermissions/PermissionOracle.swift").path
        ]
        let violations = findPattern("AXIsProcessTrusted\\(", in: sourcesDir, allowList: allow)
        if !violations.isEmpty {
            XCTFail("Direct AXIsProcessTrusted use outside allowlist:\n" + violations.joined(separator: "\n"))
        }
    }
}

// MARK: - Helpers

private func repositoryRoot(file: StaticString = #filePath) -> URL {
    // …/KeyPath/Tests/KeyPathTests/Lint/FacadeLintTests.swift -> go up 4 levels
    URL(fileURLWithPath: file.description)
        .deletingLastPathComponent() // Lint
        .deletingLastPathComponent() // KeyPathTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

private func findPattern(_ pattern: String, in directory: URL, allowList: [String]) -> [String] {
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
        return []
    }
    var hits: [String] = []
    let allowed = Set(allowList)
    for case let fileURL as URL in enumerator {
        guard fileURL.pathExtension == "swift" else { continue }
        if allowed.contains(fileURL.path) { continue }
        guard let contents = try? String(contentsOf: fileURL) else { continue }
        let lines = contents.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() where line.contains(pattern) {
            hits.append("\(fileURL.path):\(idx + 1): \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
    return hits
}
