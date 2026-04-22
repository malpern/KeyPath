import Foundation
import Testing
@testable import KeyPathLayoutTracerKit

struct TracingDocumentUndoTests {
    @Test
    func undoAndRedoRestoreKeyGeometry() {
        let document = TracingDocument()
        document.addKey()

        let originalX = document.keys[0].x
        document.nudgeSelectedKey(dx: 24, dy: 0)

        #expect(document.canUndo)
        #expect(document.keys[0].x == originalX + 24)

        document.undo()
        #expect(document.keys[0].x == originalX)
        #expect(document.canRedo)

        document.redo()
        #expect(document.keys[0].x == originalX + 24)
    }

    @Test
    func interactiveChangeCreatesSingleUndoStep() {
        let document = TracingDocument()
        document.addKey()
        let key = document.keys[0]

        document.beginInteractiveChange()
        var moved = key
        moved.x += 10
        document.updateKey(moved)
        moved.x += 15
        document.updateKey(moved)
        document.endInteractiveChange()

        document.undo()
        #expect(document.keys[0].x == key.x)
    }

    @Test
    func fitLayoutToImageScalesAndCentersKeysWithinImageBounds() {
        let document = TracingDocument()
        document.backgroundImageURL = URL(fileURLWithPath: "/tmp/reference.png")
        document.backgroundImageSize = CGSize(width: 1200, height: 500)
        document.coordinateScale = 10
        document.keys = [
            TracingKey(keyCode: 0, label: "A", x: 0, y: 0, width: 10, height: 10),
            TracingKey(keyCode: 1, label: "B", x: 20, y: 10, width: 10, height: 10)
        ]

        document.fitLayoutToImage(recordUndo: false)

        guard let bounds = document.layoutBounds else {
            Issue.record("Expected layout bounds after fitting to image")
            return
        }

        let displayBounds = CGRect(
            x: bounds.minX * document.coordinateScale,
            y: bounds.minY * document.coordinateScale,
            width: bounds.width * document.coordinateScale,
            height: bounds.height * document.coordinateScale
        )

        #expect(displayBounds.width <= 1200)
        #expect(displayBounds.height <= 500)
        #expect(abs(displayBounds.midX - 600) < 10)
        #expect(abs(displayBounds.midY - 250) < 10)
    }

    @Test
    func addAndClearGuidesSupportUndo() {
        let document = TracingDocument()

        document.addGuide(axis: .vertical, position: 120)
        document.addGuide(axis: .horizontal, position: 80)

        #expect(document.guides.count == 2)

        document.clearGuides()
        #expect(document.guides.isEmpty)

        document.undo()
        #expect(document.guides.count == 2)
    }

    @Test
    func removeSelectedGuideClearsSelection() throws {
        let document = TracingDocument()
        document.addGuide(axis: .vertical, position: 120)
        let guideID = try #require(document.guides.first?.id)

        document.selectGuide(id: guideID)
        document.removeSelectedGuide()

        #expect(document.guides.isEmpty)
        #expect(document.selectedGuideID == nil)
    }
}
