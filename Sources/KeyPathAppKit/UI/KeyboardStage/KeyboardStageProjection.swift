import CoreGraphics

struct KeyboardStageProjection: Equatable, Sendable {
    let sourceRect: KeyboardStageRect
    let destinationSize: KeyboardStageSize

    init(scene: KeyboardStageScene, size: CGSize) {
        let destinationWidth = Float(max(1, size.width))
        let destinationHeight = Float(max(1, size.height))
        let aspectRatio = destinationWidth / destinationHeight
        let bounds = scene.layoutBounds
        let zoom = max(0.1, scene.viewport.zoom)

        var visibleHeight = min(bounds.size.height, bounds.size.height / zoom)
        var visibleWidth = visibleHeight * aspectRatio
        if visibleWidth > bounds.size.width {
            visibleWidth = min(bounds.size.width, bounds.size.width / zoom)
            visibleHeight = visibleWidth / aspectRatio
        }

        visibleWidth = min(bounds.size.width, max(0.1, visibleWidth))
        visibleHeight = min(bounds.size.height, max(0.1, visibleHeight))

        let desiredX = scene.viewport.focus.x - visibleWidth / 2
        let desiredY = scene.viewport.focus.y - visibleHeight / 2
            + visibleHeight * scene.viewport.verticalBias
        let maximumX = max(bounds.minX, bounds.maxX - visibleWidth)
        let maximumY = max(bounds.minY, bounds.maxY - visibleHeight)
        let x = min(maximumX, max(bounds.minX, desiredX))
        let y = min(maximumY, max(bounds.minY, desiredY))

        sourceRect = KeyboardStageRect(
            x: x,
            y: y,
            width: visibleWidth,
            height: visibleHeight
        )
        destinationSize = KeyboardStageSize(
            width: destinationWidth,
            height: destinationHeight
        )
    }

    func project(_ rect: KeyboardStageRect) -> CGRect {
        let scaleX = destinationSize.width / sourceRect.size.width
        let scaleY = destinationSize.height / sourceRect.size.height
        return CGRect(
            x: CGFloat((rect.origin.x - sourceRect.origin.x) * scaleX),
            y: CGFloat((rect.origin.y - sourceRect.origin.y) * scaleY),
            width: CGFloat(rect.size.width * scaleX),
            height: CGFloat(rect.size.height * scaleY)
        )
    }

    func project(_ point: KeyboardStagePoint) -> CGPoint {
        let scaleX = destinationSize.width / sourceRect.size.width
        let scaleY = destinationSize.height / sourceRect.size.height
        return CGPoint(
            x: CGFloat((point.x - sourceRect.origin.x) * scaleX),
            y: CGFloat((point.y - sourceRect.origin.y) * scaleY)
        )
    }

    func projectKey(_ key: KeyboardStageKey, inset: Float = 0.045) -> CGRect {
        project(key.transformedFrame.insetBy(dx: inset, dy: inset))
    }

    func projectDecoration(_ decoration: KeyboardStageDecoration) -> CGRect {
        let frame = decoration.frame
        let width = frame.size.width * decoration.scale
        let height = frame.size.height * decoration.scale
        return project(KeyboardStageRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        ))
    }
}
