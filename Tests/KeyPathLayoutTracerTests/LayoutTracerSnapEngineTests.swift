import Testing
@testable import KeyPathLayoutTracerKit

struct LayoutTracerSnapEngineTests {
    @Test
    func moveSnapsToNeighborEdge() {
        let moving = TracingKey(keyCode: 0, label: "A", x: 96, y: 10, width: 50, height: 40)
        let other = TracingKey(keyCode: 1, label: "B", x: 100, y: 10, width: 50, height: 40)

        let snapped = LayoutTracerSnapEngine.snapMove(moving: moving, others: [other])

        #expect(snapped.x == 100)
    }

    @Test
    func resizeSnapsTrailingEdge() {
        let resizing = TracingKey(keyCode: 0, label: "A", x: 10, y: 10, width: 95, height: 40)
        let other = TracingKey(keyCode: 1, label: "B", x: 100, y: 10, width: 50, height: 40)

        let snapped = LayoutTracerSnapEngine.snapResize(resizing: resizing, others: [other])

        #expect(snapped.width == 90)
    }

    @Test
    func moveSnapsToVerticalGuide() {
        let moving = TracingKey(keyCode: 0, label: "A", x: 96, y: 10, width: 50, height: 40)
        let guide = TracingGuide(axis: .vertical, position: 100)

        let snapped = LayoutTracerSnapEngine.snapMove(moving: moving, others: [], guides: [guide])

        #expect(snapped.x == 100)
    }
}
