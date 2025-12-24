@testable import KeyPathAppKit
import XCTest

final class KeyIconRegistryTests: XCTestCase {
    // MARK: - Navigation Icons

    func testResolve_arrowLeft_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("arrow-left")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "arrow.left")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    func testResolve_arrowRight_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("arrow-right")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "arrow.right")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    func testResolve_home_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("home")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "house")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    // MARK: - Editing Icons

    func testResolve_delete_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("delete")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "delete.left")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    func testResolve_copy_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("copy")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "doc.on.doc")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    func testResolve_undo_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("undo")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "arrow.uturn.backward")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    // MARK: - Media Icons

    func testResolve_play_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("play")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "play.fill")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    func testResolve_mute_returnsSFSymbol() {
        let result = KeyIconRegistry.resolve("mute")
        if case .sfSymbol(let name) = result {
            XCTAssertEqual(name, "speaker.slash.fill")
        } else {
            XCTFail("Expected sfSymbol, got \(result)")
        }
    }

    // MARK: - App Icons

    func testResolve_safari_returnsAppIcon() {
        let result = KeyIconRegistry.resolve("safari")
        if case .appIcon(let name) = result {
            XCTAssertEqual(name, "Safari")
        } else {
            XCTFail("Expected appIcon, got \(result)")
        }
    }

    func testResolve_terminal_returnsAppIcon() {
        let result = KeyIconRegistry.resolve("terminal")
        if case .appIcon(let name) = result {
            XCTAssertEqual(name, "Terminal")
        } else {
            XCTFail("Expected appIcon, got \(result)")
        }
    }

    func testResolve_xcode_returnsAppIcon() {
        let result = KeyIconRegistry.resolve("xcode")
        if case .appIcon(let name) = result {
            XCTAssertEqual(name, "Xcode")
        } else {
            XCTFail("Expected appIcon, got \(result)")
        }
    }

    func testResolve_vscode_returnsAppIcon() {
        let result = KeyIconRegistry.resolve("vscode")
        if case .appIcon(let name) = result {
            XCTAssertEqual(name, "Visual Studio Code")
        } else {
            XCTFail("Expected appIcon, got \(result)")
        }
    }

    // MARK: - Fallback Behavior

    func testResolve_unknownIcon_returnsTextFallback() {
        let result = KeyIconRegistry.resolve("unknown-icon-xyz")
        if case .text(let name) = result {
            XCTAssertEqual(name, "unknown-icon-xyz")
        } else {
            XCTFail("Expected text fallback, got \(result)")
        }
    }

    func testResolve_emptyString_returnsTextFallback() {
        let result = KeyIconRegistry.resolve("")
        if case .text(let name) = result {
            XCTAssertEqual(name, "")
        } else {
            XCTFail("Expected text fallback, got \(result)")
        }
    }

    // MARK: - Registry Completeness

    func testRegistry_containsExpectedNavigationIcons() {
        let navigationIcons = ["arrow-left", "arrow-right", "arrow-up", "arrow-down", "home", "end", "page-up", "page-down"]
        for icon in navigationIcons {
            XCTAssertNotNil(KeyIconRegistry.registry[icon], "Missing navigation icon: \(icon)")
        }
    }

    func testRegistry_containsExpectedEditingIcons() {
        let editingIcons = ["delete", "forward-delete", "cut", "copy", "paste", "undo", "redo"]
        for icon in editingIcons {
            XCTAssertNotNil(KeyIconRegistry.registry[icon], "Missing editing icon: \(icon)")
        }
    }

    func testRegistry_containsExpectedMediaIcons() {
        let mediaIcons = ["play", "pause", "stop", "next", "previous", "volume-up", "volume-down", "mute"]
        for icon in mediaIcons {
            XCTAssertNotNil(KeyIconRegistry.registry[icon], "Missing media icon: \(icon)")
        }
    }

    func testRegistry_containsExpectedSystemIcons() {
        let systemIcons = ["brightness-up", "brightness-down", "lock", "unlock", "search", "settings"]
        for icon in systemIcons {
            XCTAssertNotNil(KeyIconRegistry.registry[icon], "Missing system icon: \(icon)")
        }
    }

    func testRegistry_containsExpectedAppIcons() {
        let appIcons = ["safari", "terminal", "finder", "mail", "xcode", "vscode", "slack", "discord"]
        for icon in appIcons {
            XCTAssertNotNil(KeyIconRegistry.registry[icon], "Missing app icon: \(icon)")
        }
    }
}
