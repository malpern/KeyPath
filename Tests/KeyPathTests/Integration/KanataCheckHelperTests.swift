import Foundation
import XCTest

final class KanataCheckHelperTests: XCTestCase {
    func testDrainsOutputWhileProcessIsRunning() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanata-check-fake-\(UUID().uuidString).sh")
        try """
        #!/bin/bash
        /usr/bin/yes x | /usr/bin/head -c 1048576
        echo '[ERROR] synthetic large-output failure'
        exit 1
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        defer { try? FileManager.default.removeItem(at: script) }

        let result = try await KanataCheckHelper.runCheck("(defcfg)", binary: script.path)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.errors, ["[ERROR] synthetic large-output failure"])
    }
}
