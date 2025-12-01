import AppKit
import SwiftUI

/// Resize edge/corner identifiers
enum ResizeEdge: CaseIterable {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: .resizeUpDown
        case .left, .right: .resizeLeftRight
        case .topLeft, .bottomRight: .crosshair // No diagonal cursors in AppKit, use crosshair
        case .topRight, .bottomLeft: .crosshair
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
struct WindowResizeHandles: ViewModifier {
    /// Width of edge hit targets
    let edgeWidth: CGFloat = 12
    /// Size of corner hit targets
    let cornerSize: CGFloat = 20
    /// Fixed aspect ratio for keyboard (width/height) - from PhysicalLayout.macBookUS
    let keyboardAspectRatio: CGFloat = 15.66 / 6.5 // ~2.41

    @State private var activeEdge: ResizeEdge?
    @State private var isDragging = false
    @State private var isMoving = false
    @State private var initialFrame: NSRect = .zero
    @State private var initialMouseLocation: NSPoint = .zero

    func body(content: Content) -> some View {
        content
            // Move gesture on the main content (lower priority than resize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        if !isMoving {
                            if let window = findOverlayWindow() {
                                initialFrame = window.frame
                                initialMouseLocation = NSEvent.mouseLocation
                            }
                            isMoving = true
                        }
                        // Use global mouse position delta, not SwiftUI translation
                        let currentMouse = NSEvent.mouseLocation
                        let deltaX = currentMouse.x - initialMouseLocation.x
                        let deltaY = currentMouse.y - initialMouseLocation.y
                        moveWindow(deltaX: deltaX, deltaY: deltaY)
                    }
                    .onEnded { _ in
                        isMoving = false
                    }
            )
            .overlay(
                GeometryReader { geometry in
                    ZStack {
                        // Edge handles
                        edgeHandle(.top, geometry: geometry)
                        edgeHandle(.bottom, geometry: geometry)
                        edgeHandle(.left, geometry: geometry)
                        edgeHandle(.right, geometry: geometry)

                        // Corner handles (on top of edges)
                        cornerHandle(.topLeft, geometry: geometry)
                        cornerHandle(.topRight, geometry: geometry)
                        cornerHandle(.bottomLeft, geometry: geometry)
                        cornerHandle(.bottomRight, geometry: geometry)
                    }
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

    @ViewBuilder
    private func edgeHandle(_ edge: ResizeEdge, geometry: GeometryProxy) -> some View {
        let size = geometry.size

        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(
                width: edgeWidth(for: edge, in: size),
                height: edgeHeight(for: edge, in: size)
            )
            .position(edgePosition(for: edge, in: size))
            .onHover { hovering in
                if hovering, !isDragging {
                    edge.cursor.push()
                    activeEdge = edge
                } else if !isDragging {
                    NSCursor.pop()
                    if activeEdge == edge { activeEdge = nil }
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        if !isDragging {
                            // Capture initial frame and mouse position at drag start
                            if let window = findOverlayWindow() {
                                initialFrame = window.frame
                                initialMouseLocation = NSEvent.mouseLocation
                            }
                            isDragging = true
                        }
                        activeEdge = edge
                        // Use global mouse delta
                        let currentMouse = NSEvent.mouseLocation
                        let delta = CGSize(
                            width: currentMouse.x - initialMouseLocation.x,
                            height: -(currentMouse.y - initialMouseLocation.y) // Invert Y for SwiftUI convention
                        )
                        resizeWindow(edge: edge, translation: delta, from: initialFrame)
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }

    @ViewBuilder
    private func cornerHandle(_ corner: ResizeEdge, geometry: GeometryProxy) -> some View {
        let size = geometry.size

        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: cornerSize, height: cornerSize)
            .position(cornerPosition(for: corner, in: size))
            .onHover { hovering in
                if hovering, !isDragging {
                    corner.cursor.push()
                    activeEdge = corner
                } else if !isDragging {
                    NSCursor.pop()
                    if activeEdge == corner { activeEdge = nil }
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        if !isDragging {
                            // Capture initial frame and mouse position at drag start
                            if let window = findOverlayWindow() {
                                initialFrame = window.frame
                                initialMouseLocation = NSEvent.mouseLocation
                            }
                            isDragging = true
                        }
                        activeEdge = corner
                        // Use global mouse delta
                        let currentMouse = NSEvent.mouseLocation
                        let delta = CGSize(
                            width: currentMouse.x - initialMouseLocation.x,
                            height: -(currentMouse.y - initialMouseLocation.y) // Invert Y for SwiftUI convention
                        )
                        resizeWindow(edge: corner, translation: delta, from: initialFrame)
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }

    // MARK: - Edge Positioning

    private func edgeWidth(for edge: ResizeEdge, in size: CGSize) -> CGFloat {
        switch edge {
        case .top, .bottom: size.width - cornerSize * 2
        case .left, .right: edgeWidth
        default: 0
        }
    }

    private func edgeHeight(for edge: ResizeEdge, in size: CGSize) -> CGFloat {
        switch edge {
        case .top, .bottom: edgeWidth
        case .left, .right: size.height - cornerSize * 2
        default: 0
        }
    }

    private func edgePosition(for edge: ResizeEdge, in size: CGSize) -> CGPoint {
        switch edge {
        case .top: CGPoint(x: size.width / 2, y: edgeWidth / 2)
        case .bottom: CGPoint(x: size.width / 2, y: size.height - edgeWidth / 2)
        case .left: CGPoint(x: edgeWidth / 2, y: size.height / 2)
        case .right: CGPoint(x: size.width - edgeWidth / 2, y: size.height / 2)
        default: .zero
        }
    }

    private func cornerPosition(for corner: ResizeEdge, in size: CGSize) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: cornerSize / 2, y: cornerSize / 2)
        case .topRight: CGPoint(x: size.width - cornerSize / 2, y: cornerSize / 2)
        case .bottomLeft: CGPoint(x: cornerSize / 2, y: size.height - cornerSize / 2)
        case .bottomRight: CGPoint(x: size.width - cornerSize / 2, y: size.height - cornerSize / 2)
        default: .zero
        }
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

        // Use a single scale factor based on drag direction
        // This ensures smooth, proportional resize without jitter
        let scale: CGFloat

        switch edge {
        case .right:
            scale = (initialFrame.width + translation.width) / initialFrame.width
        case .left:
            scale = (initialFrame.width - translation.width) / initialFrame.width
        case .bottom:
            scale = (initialFrame.height + translation.height) / initialFrame.height
        case .top:
            scale = (initialFrame.height - translation.height) / initialFrame.height
        case .bottomRight, .topRight:
            // Use the larger proportional change
            let widthScale = (initialFrame.width + translation.width) / initialFrame.width
            let heightScale = (initialFrame.height + (edge == .bottomRight ? translation.height : -translation.height)) / initialFrame.height
            scale = abs(widthScale - 1) > abs(heightScale - 1) ? widthScale : heightScale
        case .bottomLeft, .topLeft:
            let widthScale = (initialFrame.width - translation.width) / initialFrame.width
            let heightScale = (initialFrame.height + (edge == .bottomLeft ? translation.height : -translation.height)) / initialFrame.height
            scale = abs(widthScale - 1) > abs(heightScale - 1) ? widthScale : heightScale
        }

        // Apply scale to both dimensions (maintains aspect ratio perfectly)
        var newWidth = initialFrame.width * scale
        var newHeight = initialFrame.height * scale

        // Clamp to min/max
        newWidth = clamp(newWidth, min: minSize.width, max: maxSize.width)
        newHeight = clamp(newHeight, min: minSize.height, max: maxSize.height)

        // Ensure aspect ratio is maintained after clamping
        let clampedScale = min(newWidth / initialFrame.width, newHeight / initialFrame.height)
        newWidth = initialFrame.width * clampedScale
        newHeight = initialFrame.height * clampedScale

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
    func windowResizeHandles() -> some View {
        modifier(WindowResizeHandles())
    }
}
