import AppKit
import UniformTypeIdentifiers

/// NSView that provides a draggable file URL for System Settings privacy lists.
/// System Settings accepts .fileURL drops into its privacy sidebar lists.
final class DragToAuthorizeDragSource: NSView, NSDraggingSource {
    var fileURL: URL
    var onDragBegan: (@MainActor () -> Void)?
    var onDragEnded: (@MainActor (NSDragOperation) -> Void)?

    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero

    init(fileURL: URL, frame: NSRect = .zero) {
        self.fileURL = fileURL
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - dragStartPoint.x, current.y - dragStartPoint.y)

        guard distance > 3, !isDragging else { return }
        isDragging = true
        beginDragSession(from: event)
    }

    private func beginDragSession(from event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        let iconSize: CGFloat = 48
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: iconSize, height: iconSize)

        let iconFrame = NSRect(
            x: (bounds.width - iconSize) / 2,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        draggingItem.setDraggingFrame(iconFrame, contents: icon)

        onDragBegan?()

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
        isDragging = false
        onDragEnded?(operation)
    }
}
