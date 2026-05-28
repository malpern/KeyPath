import Foundation
@testable import KeyPathAppKit
import Testing

// MARK: - WindowPosition Tests

@Suite("WindowPosition Tests")
struct WindowPositionTests {
    @Test("All position raw values are unique")
    func allPositionRawValuesAreUnique() {
        let rawValues = WindowPosition.allCases.map(\.rawValue)
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }

    @Test("Position can be initialized from raw value")
    func positionFromRawValue() {
        #expect(WindowPosition(rawValue: "left") == .left)
        #expect(WindowPosition(rawValue: "right") == .right)
        #expect(WindowPosition(rawValue: "maximize") == .maximize)
        #expect(WindowPosition(rawValue: "center") == .center)
        #expect(WindowPosition(rawValue: "top-left") == .topLeft)
        #expect(WindowPosition(rawValue: "top-right") == .topRight)
        #expect(WindowPosition(rawValue: "bottom-left") == .bottomLeft)
        #expect(WindowPosition(rawValue: "bottom-right") == .bottomRight)
        #expect(WindowPosition(rawValue: "next-display") == .nextDisplay)
        #expect(WindowPosition(rawValue: "previous-display") == .previousDisplay)
        #expect(WindowPosition(rawValue: "next-space") == .nextSpace)
        #expect(WindowPosition(rawValue: "previous-space") == .previousSpace)
        #expect(WindowPosition(rawValue: "undo") == .undo)
    }

    @Test("Invalid raw value returns nil")
    func invalidRawValueReturnsNil() {
        #expect(WindowPosition(rawValue: "invalid") == nil)
        #expect(WindowPosition(rawValue: "LEFT") == nil) // Case-sensitive
        #expect(WindowPosition(rawValue: "") == nil)
    }

    @Test("allValues contains all positions")
    func allValuesContainsAllPositions() {
        let allValues = WindowPosition.allValues
        for position in WindowPosition.allCases {
            #expect(allValues.contains(position.rawValue))
        }
    }

    @Test("Position count is 13")
    func positionCount() {
        // Halves: left, right
        // Full: maximize, center
        // Corners: top-left, top-right, bottom-left, bottom-right
        // Display: next-display, previous-display
        // Space: next-space, previous-space
        // Undo: undo
        #expect(WindowPosition.allCases.count == 13)
    }

    @Test("all positions have non-empty rawValue")
    func allPositionsHaveNonEmptyRawValue() {
        for position in WindowPosition.allCases {
            #expect(!position.rawValue.isEmpty, "\(position) should have a non-empty rawValue")
        }
    }

    @Test("allValues contains all rawValues")
    func allValuesContainsAllRawValues() {
        let allValuesString = WindowPosition.allValues
        // allValues is a comma-separated string; split and count
        let splitValues = allValuesString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(splitValues.count == WindowPosition.allCases.count,
                "allValues should list exactly \(WindowPosition.allCases.count) positions")
    }
}

// MARK: - Frame Calculation Tests

@Suite("Window Frame Calculation Tests")
struct WindowFrameCalculationTests {
    /// Test screen: 1920x1080, with 25px menu bar
    let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1055)

    @Test("Left half calculation")
    func leftHalfCalculation() {
        let expected = CGRect(x: 0, y: 0, width: 960, height: 1055)
        let result = calculateFrame(for: .left, in: visibleFrame)
        #expect(result == expected)
    }

    @Test("Right half calculation")
    func rightHalfCalculation() {
        let expected = CGRect(x: 960, y: 0, width: 960, height: 1055)
        let result = calculateFrame(for: .right, in: visibleFrame)
        #expect(result == expected)
    }

    @Test("Top-left quarter calculation")
    func topLeftQuarterCalculation() {
        let expected = CGRect(x: 0, y: 527.5, width: 960, height: 527.5)
        let result = calculateFrame(for: .topLeft, in: visibleFrame)
        #expect(result == expected)
    }

    @Test("Top-right quarter calculation")
    func topRightQuarterCalculation() {
        let expected = CGRect(x: 960, y: 527.5, width: 960, height: 527.5)
        let result = calculateFrame(for: .topRight, in: visibleFrame)
        #expect(result == expected)
    }

    @Test("Bottom-left quarter calculation")
    func bottomLeftQuarterCalculation() {
        let expected = CGRect(x: 0, y: 0, width: 960, height: 527.5)
        let result = calculateFrame(for: .bottomLeft, in: visibleFrame)
        #expect(result == expected)
    }

    @Test("Bottom-right quarter calculation")
    func bottomRightQuarterCalculation() {
        let expected = CGRect(x: 960, y: 0, width: 960, height: 527.5)
        let result = calculateFrame(for: .bottomRight, in: visibleFrame)
        #expect(result == expected)
    }

    @Test("Maximize calculation")
    func maximizeCalculation() {
        let result = calculateFrame(for: .maximize, in: visibleFrame)
        #expect(result == visibleFrame)
    }

    @Test("Center calculation preserves window size")
    func centerCalculation() {
        let windowSize = CGSize(width: 800, height: 600)
        let currentFrame = CGRect(x: 100, y: 100, width: windowSize.width, height: windowSize.height)

        let result = calculateFrameWithCurrentFrame(for: .center, in: visibleFrame, currentFrame: currentFrame)

        // Should be centered (use approximate comparison for floating point)
        let expectedX = (1920.0 - 800.0) / 2.0
        let expectedY = (1055.0 - 600.0) / 2.0
        #expect(abs(result.origin.x - expectedX) < 0.01)
        #expect(abs(result.origin.y - expectedY) < 0.01)
        // Size should be preserved
        #expect(result.size.width == windowSize.width)
        #expect(result.size.height == windowSize.height)
    }

    @Test("left and right halves together cover full width")
    func leftAndRightHalvesCoverFullWidth() {
        let left = calculateFrame(for: .left, in: visibleFrame)
        let right = calculateFrame(for: .right, in: visibleFrame)

        #expect(left.width + right.width == visibleFrame.width)
        #expect(left.union(right) == visibleFrame)
    }

    @Test("all four quarters together cover full visible frame")
    func allFourQuartersCoverFullVisibleFrame() {
        let topLeft = calculateFrame(for: .topLeft, in: visibleFrame)
        let topRight = calculateFrame(for: .topRight, in: visibleFrame)
        let bottomLeft = calculateFrame(for: .bottomLeft, in: visibleFrame)
        let bottomRight = calculateFrame(for: .bottomRight, in: visibleFrame)

        let combined = topLeft.union(topRight).union(bottomLeft).union(bottomRight)
        #expect(combined == visibleFrame)
    }

    @Test("frame calculations with non-zero origin")
    func frameCalculationsWithNonZeroOrigin() {
        // Simulate an external monitor with non-zero origin
        let externalFrame = CGRect(x: 100, y: 50, width: 1920, height: 1055)

        let left = calculateFrame(for: .left, in: externalFrame)
        #expect(left == CGRect(x: 100, y: 50, width: 960, height: 1055))

        let right = calculateFrame(for: .right, in: externalFrame)
        #expect(right == CGRect(x: 1060, y: 50, width: 960, height: 1055))

        let maximize = calculateFrame(for: .maximize, in: externalFrame)
        #expect(maximize == externalFrame)
    }

    @Test("center with window larger than screen clips to screen")
    func centerWithLargerWindowPositionsCorrectly() {
        let largeFrame = CGRect(x: 0, y: 0, width: 2500, height: 1500)

        let result = calculateFrameWithCurrentFrame(for: .center, in: visibleFrame, currentFrame: largeFrame)

        // Center formula: x + (width - currentFrame.width) / 2 => 0 + (1920 - 2500) / 2 = -290
        let expectedX = (1920.0 - 2500.0) / 2.0
        let expectedY = (1055.0 - 1500.0) / 2.0
        #expect(abs(result.origin.x - expectedX) < 0.01)
        #expect(abs(result.origin.y - expectedY) < 0.01)
        // Size preserved (the window size itself, not clipped)
        #expect(result.size.width == largeFrame.width)
        #expect(result.size.height == largeFrame.height)
    }

    // Helper: Simplified frame calculation (mirrors WindowManager logic)
    private func calculateFrame(for position: WindowPosition, in visibleFrame: CGRect) -> CGRect {
        calculateFrameWithCurrentFrame(for: position, in: visibleFrame, currentFrame: visibleFrame)
    }

    private func calculateFrameWithCurrentFrame(
        for position: WindowPosition,
        in visibleFrame: CGRect,
        currentFrame: CGRect
    ) -> CGRect {
        let x = visibleFrame.origin.x
        let y = visibleFrame.origin.y
        let width = visibleFrame.width
        let height = visibleFrame.height
        let halfWidth = width / 2
        let halfHeight = height / 2

        switch position {
        case .left:
            return CGRect(x: x, y: y, width: halfWidth, height: height)
        case .right:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: height)
        case .maximize:
            return visibleFrame
        case .center:
            let centerX = x + (width - currentFrame.width) / 2
            let centerY = y + (height - currentFrame.height) / 2
            return CGRect(x: centerX, y: centerY, width: currentFrame.width, height: currentFrame.height)
        case .topLeft:
            return CGRect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: x, y: y, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)
        case .nextDisplay, .previousDisplay, .nextSpace, .previousSpace, .undo:
            return currentFrame
        }
    }
}

// MARK: - CGS Type Tests

@Suite("CGS Type Tests")
struct CGSTypeTests {
    @Test("CGSConnectionID is UInt32")
    func connectionIDType() {
        let _: CGSConnectionID = 0
        #expect(MemoryLayout<CGSConnectionID>.size == MemoryLayout<UInt32>.size)
    }

    @Test("CGSSpaceID is UInt64")
    func spaceIDType() {
        let _: CGSSpaceID = 0
        #expect(MemoryLayout<CGSSpaceID>.size == MemoryLayout<UInt64>.size)
    }
}

// MARK: - CGS API Availability Tests

@Suite("CGS API Availability Tests")
struct CGSAPIAvailabilityTests {
    @Test("CGSPrivateAPI.isAvailable returns consistent result")
    func isAvailableConsistent() {
        // Should return the same value on repeated calls (cached)
        let first = CGSPrivateAPI.isAvailable
        let second = CGSPrivateAPI.isAvailable
        #expect(first == second)
    }

    @Test("CGSPrivateAPI.checkAvailabilityDetails returns tuple")
    func checkAvailabilityDetailsReturnsTuple() {
        let (available, missing) = CGSPrivateAPI.checkAvailabilityDetails()
        // If available, missing should be empty
        if available {
            #expect(missing.isEmpty)
        }
        // If not available, missing should have entries
        if !available {
            #expect(!missing.isEmpty)
        }
    }

    @Test("CGSPrivateAPI.statusMessage is non-empty")
    func statusMessageNonEmpty() {
        let message = CGSPrivateAPI.statusMessage
        #expect(!message.isEmpty)
    }

    @Test("SpaceManager.isAvailable matches CGSPrivateAPI.isAvailable")
    @MainActor
    func spaceManagerAvailabilityMatches() {
        let apiAvailable = CGSPrivateAPI.isAvailable
        let managerAvailable = SpaceManager.shared.isAvailable
        #expect(apiAvailable == managerAvailable)
    }
}
