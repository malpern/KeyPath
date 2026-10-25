import Foundation
import XCTest

final class HelperServiceKeepAliveLifecycleLintTests: XCTestCase {
    func testHelperDisablesKeepAliveServiceBeforeStoppingIt() throws {
        let source = try helperServiceSource()
        let stopBody = try functionBody(named: "stopKanataService", in: source)

        let inspect = try XCTUnwrap(stopBody.range(of: "Self.serviceProcessID(Self.kanataServiceID)"))
        let disable = try XCTUnwrap(stopBody.range(of: "[\"disable\", Self.kanataServiceTarget]"))
        let signal = try XCTUnwrap(stopBody.range(of: "Self.run(\"/bin/kill\", [\"-TERM\", processID]"))
        let restore = try XCTUnwrap(
            stopBody.range(
                of: "[\"enable\", Self.kanataServiceTarget]",
                range: signal.upperBound ..< stopBody.endIndex
            )
        )
        XCTAssertLessThan(inspect.lowerBound, disable.lowerBound)
        XCTAssertLessThan(disable.lowerBound, signal.lowerBound)
        XCTAssertLessThan(signal.lowerBound, restore.lowerBound)
        XCTAssertFalse(stopBody.contains("[\"kill\", \"SIGTERM\", Self.kanataServiceTarget]"))
    }

    func testHelperReenablesServiceBeforeStartingOrRestartingIt() throws {
        let source = try helperServiceSource()

        for functionName in ["startKanataService", "restartKanataService"] {
            let body = try functionBody(named: functionName, in: source)
            let enable = try XCTUnwrap(body.range(of: "[\"enable\", Self.kanataServiceTarget]"))
            let kickstart = try XCTUnwrap(body.range(of: "[\"kickstart\""))
            XCTAssertLessThan(enable.lowerBound, kickstart.lowerBound, functionName)
        }
    }

    private func helperServiceSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent("Sources/KeyPathHelper/HelperService.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func functionBody(named name: String, in source: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: "func \(name)("))
        let remainder = source[start.lowerBound...]
        let nextFunction = remainder.dropFirst().range(of: "\n    func ")
        return nextFunction.map { remainder[..<$0.lowerBound] } ?? remainder
    }
}
