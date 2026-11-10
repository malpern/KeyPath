@testable import KeyPathAppKit
import XCTest

final class ExternalKanataServiceCommandTests: XCTestCase {
    /// A child that fills both pipe buffers (64 KB each) before exiting used to
    /// deadlock: the caller waited for exit before reading either pipe.
    func testCommandWithLargeOutputOnBothStreamsDoesNotHang() async throws {
        let script = "head -c 300000 /dev/zero | tr '\\\\0' o; head -c 300000 /dev/zero | tr '\\\\0' e >&2; exit 3"
        let result = try await ExternalKanataService.runCommand("/bin/sh", arguments: ["-c", script])
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.stdout.count, 300_000)
        XCTAssertEqual(result.stderr.count, 300_000)
    }
}
