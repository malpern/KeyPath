@testable import KeyPathAppKit
import XCTest

#if os(macOS)
    @MainActor
    final class AccessibleIntegerFieldTests: XCTestCase {
        func testAccessibilitySetValueUpdatesFieldAndNotifiesCoordinator() {
            let field = AccessibilitySettableIntegerTextField()
            var capturedValue: String?
            field.onAccessibilityValueChanged = { capturedValue = $0 }

            field.setAccessibilityValue("225")

            XCTAssertEqual(field.stringValue, "225")
            XCTAssertEqual(capturedValue, "225")
        }

        func testAccessibilitySetValueAcceptsValueWithUnitSuffix() {
            let field = AccessibilitySettableIntegerTextField()
            var capturedValue: String?
            field.onAccessibilityValueChanged = { capturedValue = $0 }

            field.setAccessibilityValue("180 ms")

            XCTAssertEqual(field.stringValue, "180 ms")
            XCTAssertEqual(capturedValue, "180 ms")
        }

        func testDisplayedAccessibilityValueDoesNotCommitAUserEdit() {
            let field = AccessibilitySettableIntegerTextField()
            field.stringValue = "180"
            var capturedValue: String?
            field.onAccessibilityValueChanged = { capturedValue = $0 }

            field.setDisplayedAccessibilityValue("180 ms")

            XCTAssertEqual(field.stringValue, "180")
            XCTAssertNil(capturedValue)
        }
    }
#endif
