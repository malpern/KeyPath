@testable import KeyPathAppKit
import XCTest

final class KanataProcessDetectorTests: XCTestCase {
    private let engine = "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata"

    private func isKanata(_ command: String) -> Bool {
        KanataProcessDetector.isKanataBinary(command, knownPaths: [engine])
    }

    /// The bundled engine run as its own process is the retired 1.0.1 daemon:
    /// KeyPath never runs it that way now, so it competes for the keyboard.
    func testBundledEngineProcessCountsEvenThoughItsPathContainsCat() {
        XCTAssertTrue(isKanata(engine))
        XCTAssertTrue(isKanata("\(engine) --cfg /Users/me/.config/keypath/keypath.kbd --port 37001"))
    }

    func testStandaloneKanataBinariesCount() {
        XCTAssertTrue(isKanata("/opt/homebrew/bin/kanata -c ~/kanata.kbd"))
        XCTAssertTrue(isKanata("/usr/local/bin/kanata"))
        XCTAssertTrue(isKanata("kanata --cfg a.kbd"))
        XCTAssertTrue(isKanata("/Applications/Tools/kanata"))
    }

    func testToolsThatMentionKanataDoNotCount() {
        XCTAssertFalse(isKanata("tail -f /var/log/com.keypath.kanata.stderr.log"))
        XCTAssertFalse(isKanata("pgrep -fl kanata"))
        XCTAssertFalse(isKanata("grep kanata /tmp/x"))
        XCTAssertFalse(isKanata("vim ~/.config/kanata/kanata.kbd"))
        XCTAssertFalse(isKanata("/Applications/Visual Studio Code.app/Contents/MacOS/Electron --kanata-lsp"))
        XCTAssertFalse(isKanata("/usr/local/bin/kanata-lsp --stdio"))
    }

    /// The session worker is the KeyPath executable hosting the bridge.
    func testKeyPathSessionWorkerDoesNotCount() {
        XCTAssertFalse(isKanata("/Applications/KeyPath.app/Contents/MacOS/KeyPath --session-worker"))
        XCTAssertFalse(isKanata("/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib"))
    }
}
