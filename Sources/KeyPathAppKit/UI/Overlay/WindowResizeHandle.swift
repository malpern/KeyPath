import AppKit
import SwiftUI

// MARK: - Private Cursor API

/// Private AppKit cursors for diagonal window resizing.
/// These are not public API but are stable and used by macOS itself.
/// Note: Not App Store safe - use custom cursor images if distributing via App Store.
private extension NSCursor {
    static var _windowResizeNorthWestSouthEastCursor: NSCursor? {
        NSCursor.perform(NSSelectorFromString("_windowResizeNorthWestSouthEastCursor"))?
            .takeUnretainedValue() as? NSCursor
    }

    static var _windowResizeNorthEastSouthWestCursor: NSCursor? {
        NSCursor.perform(NSSelectorFromString("_windowResizeNorthEastSouthWestCursor"))?
            .takeUnretainedValue() as? NSCursor
    }
}

/// Resize edge/corner identifiers
enum ResizeEdge: CaseIterable {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: .resizeUpDown
        case .left, .right: .resizeLeftRight
        case .topRight, .bottomLeft:
            // NE-SW diagonal: / direction (points toward top-right and bottom-left)
            NSCursor._windowResizeNorthEastSouthWestCursor ?? .crosshair
        case .topLeft, .bottomRight:
            // NW-SE diagonal: \ direction (points toward top-left and bottom-right)
            NSCursor._windowResizeNorthWestSouthEastCursor ?? .crosshair
        }
    }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: true
        default: false
        }
    }
}

/// A view modifier that adds resize handles to all edges of a borderless window.
/// Provides forgiving hit targets and visual feedback during resize.
/// Also handles window moving when dragging from the center.
/// Option+drag from anywhere triggers resize (uses bottom-right corner behavior).
struct WindowResizeHandles: ViewModifier {
    /// Width of edge hit targets
    let edgeWidth: CGFloat = 16
    /// Size of corner hit targets
    let cornerSize: CGFloat = 20
    let keyboardAspectRatio: CGFloat
    let horizontalChrome: CGFloat
    let verticalChrome: CGFloat

    /// Debug: set to true to see handle positions (red = edges, blue = corners)
    private let debugShowHandles = false
    @State private var activeEdge: ResizeEdge?
    @State private var isDragging = false
    @State private var isMoving = false
    @State private var isOptionResizing = false
    @EnvironmentObject private var vizViewModel: KeyboardVisualizationViewModel
    @State private var initialFrame: NSRect = .zero
    @State private var initialMouseLocation: NSPoint = .zero

    func body(content: Content) -> some View {
        content
            // Move gesture on the main content (lower priority than resize)
            // Option+drag = resize from bottom-right corner
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        let optionHeld = NSEvent.modifierFlags.contains(.option)

                        if !isMoving, !isOptionResizing {
                            if let window = findOverlayWindow() {
                                initialFrame = window.frame
                                initialMouseLocation = NSEvent.mouseLocation
                                vizViewModel.noteInteraction()
                            }
                            if optionHeld {
                                isOptionResizing = true
                                // Show resize cursor
                                ResizeEdge.bottomRight.cursor.push()
                            } else {
                                isMoving = true
                            }
                        }

                        let currentMouse = NSEvent.mouseLocation
                        let deltaX = currentMouse.x - initialMouseLocation.x
                        let deltaY = currentMouse.y - initialMouseLocation.y

                        if isOptionResizing {
                            // Option+drag = resize from bottom-right
                            let delta = CGSize(width: deltaX, height: -deltaY)
                            resizeWindow(edge: .bottomRight, translation: delta, from: initialFrame)
                        } else {
                            // Normal drag = move
                            moveWindow(deltaX: deltaX, deltaY: deltaY)
                        }
                    }
                    .onEnded { _ in
                        if isOptionResizing {
                            NSCursor.pop()
                        }
                        isMoving = false
                        isOptionResizing = false
                        vizViewModel.noteInteraction()
                    }
            )
            .overlay(
                GeometryReader { geometry in
                    let size = geometry.size

                    // Bottom edge
                    edgeHandleView(.bottom)
                        .frame(width: size.width - cornerSize * 2, height: edgeWidth)
                        .position(x: size.width / 2, y: size.height - edgeWidth / 2)

                    // Left edge
                    edgeHandleView(.left)
                        .frame(width: edgeWidth, height: size.height - cornerSize * 2)
                        .position(x: edgeWidth / 2, y: size.height / 2)

                    // Right edge
                    edgeHandleView(.right)
                        .frame(width: edgeWidth, height: size.height - cornerSize * 2)
                        .position(x: size.width - edgeWidth / 2, y: size.height / 2)

                    // Corners (on top)
                    // Top-left corner disabled to avoid conflict with header buttons
                    // cornerHandleView(.topLeft)
                    //     .frame(width: cornerSize, height: cornerSize)
                    //     .position(x: cornerSize / 2, y: cornerSize / 2)

                    cornerHandleView(.bottomLeft)
                        .frame(width: cornerSize, height: cornerSize)
                        .position(x: cornerSize / 2, y: size.height - cornerSize / 2)

                    cornerHandleView(.bottomRight)
                        .frame(width: cornerSize, height: cornerSize)
                        .position(x: size.width - cornerSize / 2, y: size.height - cornerSize / 2)
                }
            )
    }

    private func moveWindow(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = findOverlayWindow() else { return }
        // Move window by mouse delta from initial position
        var newOrigin = initialFrame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY // Both in screen coordinates now
        window.setFrameOrigin(newOrigin)
    }

    /// Creates an edge handle view (visual + gestures, no positioning)
    @ViewBuilder
    private func edgeHandleView(_ edge: ResizeEdge) -> some View {
        if edge == .top || edge == .bottom {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        } else {
            Rectangle()
                .fill(debugShowHandles ? Color.red.opacity(0.3) : Color.clear)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering, !isDragging {
                        edge.cursor.push()
                        activeEdge = edge
                    } else if !isDragging {
                        NSCursor.pop()
                        if activeEdge == edge { activeEdge = nil }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { _ in
                            if !isDragging {
                                if let window = findOverlayWindow() {
                                    initialFrame = window.frame
                                    initialMouseLocation = NSEvent.mouseLocation
                                }
                                isDragging = true
                            }
                            activeEdge = edge
                            let currentMouse = NSEvent.mouseLocation
                            let delta = CGSize(
                                width: currentMouse.x - initialMouseLocation.x,
                                height: -(currentMouse.y - initialMouseLocation.y)
                            )
                            resizeWindow(edge: edge, translation: delta, from: initialFrame)
                        }
                        .onEnded { _ in
                            isDragging = false
                            NSCursor.pop()
                        }
                )
        }
    }

    /// Creates a corner handle view (visual + gestures, no positioning)
    private func cornerHandleView(_ corner: ResizeEdge) -> some View {
        Rectangle()
            .fill(debugShowHandles ? Color.blue.opacity(0.3) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering, !isDragging {
                    corner.cursor.push()
                    activeEdge = corner
                } else if !isDragging {
                    NSCursor.pop()
                    if activeEdge == corner { activeEdge = nil }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        if !isDragging {
                            if let window = findOverlayWindow() {
                                initialFrame = window.frame
                                initialMouseLocation = NSEvent.mouseLocation
                            }
                            isDragging = true
                        }
                        activeEdge = corner
                        let currentMouse = NSEvent.mouseLocation
                        let delta = CGSize(
                            width: currentMouse.x - initialMouseLocation.x,
                            height: -(currentMouse.y - initialMouseLocation.y)
                        )
                        resizeWindow(edge: corner, translation: delta, from: initialFrame)
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }

    // MARK: - Window Resizing

    private func findOverlayWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.styleMask.contains(.borderless) && $0.level == .floating
        }
    }

    private func resizeWindow(edge: ResizeEdge, translation: CGSize, from initialFrame: NSRect) {
        guard let window = findOverlayWindow() else { return }

        let minSize = window.minSize
        let maxSize = window.maxSize

        let widthDelta = (edge == .left || edge == .topLeft || edge == .bottomLeft)
            ? -translation.width
            : translation.width
        let heightDelta = (edge == .top || edge == .topLeft || edge == .topRight)
            ? -translation.height
            : translation.height

        func heightForWidth(_ width: CGFloat) -> CGFloat {
            let keyboardWidth = max(0, width - horizontalChrome)
            return verticalChrome + (keyboardWidth / keyboardAspectRatio)
        }

        func widthForHeight(_ height: CGFloat) -> CGFloat {
            let keyboardHeight = max(0, height - verticalChrome)
            return horizontalChrome + (keyboardHeight * keyboardAspectRatio)
        }

        func widthBasedFrame() -> (CGFloat, CGFloat) {
            var width = clamp(initialFrame.width + widthDelta, min: minSize.width, max: maxSize.width)
            var height = heightForWidth(width)
            if height < minSize.height || height > maxSize.height {
                height = clamp(height, min: minSize.height, max: maxSize.height)
                width = widthForHeight(height)
            }
            return (width, height)
        }

        func heightBasedFrame() -> (CGFloat, CGFloat) {
            var height = clamp(initialFrame.height + heightDelta, min: minSize.height, max: maxSize.height)
            var width = widthForHeight(height)
            if width < minSize.width || width > maxSize.width {
                width = clamp(width, min: minSize.width, max: maxSize.width)
                height = heightForWidth(width)
            }
            return (width, height)
        }

        let newWidth: CGFloat
        let newHeight: CGFloat
        switch edge {
        case .left, .right:
            (newWidth, newHeight) = widthBasedFrame()
        case .top, .bottom:
            (newWidth, newHeight) = heightBasedFrame()
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let (widthFromX, heightFromX) = widthBasedFrame()
            let (widthFromY, heightFromY) = heightBasedFrame()
            if abs(widthFromX - initialFrame.width) >= abs(widthFromY - initialFrame.width) {
                newWidth = widthFromX
                newHeight = heightFromX
            } else {
                newWidth = widthFromY
                newHeight = heightFromY
            }
        }

        var newFrame = initialFrame
        newFrame.size.width = newWidth
        newFrame.size.height = newHeight

        // Adjust origin based on which edge is anchored
        switch edge {
        case .left, .topLeft, .bottomLeft:
            newFrame.origin.x = initialFrame.maxX - newWidth
        case .right, .topRight, .bottomRight:
            // Right edge anchored at left (origin.x stays)
            break
        case .top, .bottom:
            // Center horizontally for top/bottom edges
            newFrame.origin.x = initialFrame.origin.x + (initialFrame.width - newWidth) / 2
        }

        switch edge {
        case .top, .topLeft, .topRight:
            // Top edge: anchor at bottom (origin.y stays)
            break
        case .bottom, .bottomLeft, .bottomRight:
            // Bottom edge: anchor at top
            newFrame.origin.y = initialFrame.maxY - newHeight
        case .left, .right:
            // Center vertically for left/right edges
            newFrame.origin.y = initialFrame.origin.y + (initialFrame.height - newHeight) / 2
        }

        // Disable implicit animations during resize
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        window.setFrame(newFrame, display: true, animate: false)
        NSAnimationContext.endGrouping()
    }

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(maxVal, Swift.max(minVal, value))
    }
}

extension View {
    /// Adds resize handles to all edges for borderless window resizing.
    func windowResizeHandles(
        keyboardAspectRatio: CGFloat,
        horizontalChrome: CGFloat,
        verticalChrome: CGFloat
    ) -> some View {
        modifier(
            WindowResizeHandles(
                keyboardAspectRatio: keyboardAspectRatio,
                horizontalChrome: horizontalChrome,
                verticalChrome: verticalChrome
            )
        )
    }
}
