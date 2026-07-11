import Foundation
@preconcurrency import XCTest

/// Pins the production XPC entry points to the shared helper-operation gate.
final class HelperOperationGateWiringLintTests: XCTestCase {
    func testEveryHelperXPCEntryPointUsesOperationPermit() throws {
        let requestHandlers = try String(
            contentsOf: LintScanner.path("Sources/KeyPathAppKit/Core/HelperManager+RequestHandlers.swift"),
            encoding: .utf8
        )
        let status = try String(
            contentsOf: LintScanner.path("Sources/KeyPathAppKit/Core/HelperManager+Status.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(body(of: "executeXPCCall", in: requestHandlers).contains("withHelperOperationPermit"))
        XCTAssertTrue(body(of: "executeValueXPCCall", in: requestHandlers).contains("withHelperOperationPermit"))
        XCTAssertTrue(body(of: "getHelperVersion", in: status).contains("withHelperOperationPermit"))
    }

    private func body(of function: String, in source: String) -> String {
        guard let start = source.range(of: "func \(function)")?.lowerBound,
              let opening = source[start...].firstIndex(of: "{")
        else { return "" }
        var depth = 0
        for index in source.indices[opening...].dropFirst() {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                if depth == 0 { return String(source[opening ... index]) }
                depth -= 1
            }
        }
        return ""
    }
}
