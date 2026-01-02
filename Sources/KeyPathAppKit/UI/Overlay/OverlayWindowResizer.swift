import CoreGraphics

enum OverlayResizeAnchor {
    case none
    case width
    case height
}

enum OverlayWindowResizer {
    static func constrainedSize(
        targetSize: CGSize,
        currentSize: CGSize,
        aspect: CGFloat,
        verticalChrome: CGFloat,
        horizontalChrome: CGFloat,
        minSize: CGSize,
        maxSize: CGSize,
        anchor: OverlayResizeAnchor
    ) -> CGSize {
        let safeAspect = max(aspect, 0.1)

        func heightForWidth(_ width: CGFloat) -> CGFloat {
            let keyboardWidth = max(0, width - horizontalChrome)
            return verticalChrome + (keyboardWidth / safeAspect)
        }

        func widthForHeight(_ height: CGFloat) -> CGFloat {
            let keyboardHeight = max(0, height - verticalChrome)
            return horizontalChrome + (keyboardHeight * safeAspect)
        }

        let widthDelta = abs(targetSize.width - currentSize.width)
        let heightDelta = abs(targetSize.height - currentSize.height)
        let resolvedAnchor = anchor == .none ? (heightDelta > widthDelta ? .height : .width) : anchor

        var newWidth: CGFloat
        var newHeight: CGFloat

        if resolvedAnchor == .height {
            newHeight = clamp(targetSize.height, min: minSize.height, max: maxSize.height)
            newWidth = widthForHeight(newHeight)
        } else {
            newWidth = clamp(targetSize.width, min: minSize.width, max: maxSize.width)
            newHeight = heightForWidth(newWidth)
        }

        if newWidth < minSize.width {
            newWidth = minSize.width
            newHeight = heightForWidth(newWidth)
        } else if newWidth > maxSize.width {
            newWidth = maxSize.width
            newHeight = heightForWidth(newWidth)
        }

        if newHeight < minSize.height {
            newHeight = minSize.height
            newWidth = widthForHeight(newHeight)
        } else if newHeight > maxSize.height {
            newHeight = maxSize.height
            newWidth = widthForHeight(newHeight)
        }

        return CGSize(width: newWidth, height: newHeight)
    }

    static func resolveAnchor(
        existing: OverlayResizeAnchor,
        startFrame: CGRect,
        currentFrame: CGRect?,
        startMouse: CGPoint,
        currentMouse: CGPoint,
        widthDelta: CGFloat,
        heightDelta: CGFloat,
        threshold: CGFloat
    ) -> OverlayResizeAnchor {
        if existing != .none {
            return existing
        }

        let hasStart = startFrame.size != .zero
        if hasStart {
            let frameWidthDelta = abs(startFrame.width - (currentFrame?.width ?? startFrame.width))
            let frameHeightDelta = abs(startFrame.height - (currentFrame?.height ?? startFrame.height))
            if frameWidthDelta > threshold || frameHeightDelta > threshold {
                return frameHeightDelta > frameWidthDelta ? .height : .width
            }
        }

        let mouseDeltaX = abs(currentMouse.x - startMouse.x)
        let mouseDeltaY = abs(currentMouse.y - startMouse.y)
        if mouseDeltaX > threshold || mouseDeltaY > threshold {
            return mouseDeltaY > mouseDeltaX ? .height : .width
        }

        return heightDelta > widthDelta ? .height : .width
    }

    static func widthForAspect(
        currentHeight: CGFloat,
        aspect: CGFloat,
        verticalChrome: CGFloat,
        horizontalChrome: CGFloat
    ) -> CGFloat {
        let keyboardHeight = currentHeight - verticalChrome
        return (keyboardHeight * aspect) + horizontalChrome
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(maxValue, Swift.max(minValue, value))
    }
}
