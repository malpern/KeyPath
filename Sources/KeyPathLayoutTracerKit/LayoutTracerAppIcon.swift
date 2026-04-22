import AppKit

enum LayoutTracerAppIcon {
    static func makeIcon(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let bounds = CGRect(origin: .zero, size: image.size)
        let cornerRadius = size * 0.22

        let base = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.20, alpha: 1.0).setFill()
        base.fill()

        let highlightRect = bounds.insetBy(dx: size * 0.04, dy: size * 0.04)
        let highlight = NSBezierPath(roundedRect: highlightRect, xRadius: cornerRadius * 0.85, yRadius: cornerRadius * 0.85)
        NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.36, alpha: 1.0).setFill()
        highlight.fill()

        drawSymbol(
            "keyboard",
            in: CGRect(x: size * 0.13, y: size * 0.18, width: size * 0.56, height: size * 0.42),
            pointSize: size * 0.29,
            color: NSColor.white.withAlphaComponent(0.95),
            weight: .semibold
        )

        drawRulerBadge(size: size)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawRulerBadge(size: CGFloat) {
        let badgeRect = CGRect(x: size * 0.57, y: size * 0.53, width: size * 0.24, height: size * 0.24)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: badgeRect.midX, yBy: badgeRect.midY)
        transform.rotate(byDegrees: 18)
        transform.translateX(by: -badgeRect.midX, yBy: -badgeRect.midY)
        transform.concat()

        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: size * 0.055, yRadius: size * 0.055)
        NSColor(calibratedRed: 0.94, green: 0.73, blue: 0.31, alpha: 1.0).setFill()
        badgePath.fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let stroke = NSBezierPath(roundedRect: badgeRect, xRadius: size * 0.055, yRadius: size * 0.055)
        stroke.lineWidth = size * 0.012
        stroke.stroke()

        let markWidth = size * 0.008
        let markInsetX = badgeRect.minX + size * 0.04
        let marks: [CGFloat] = [0.04, 0.075, 0.11, 0.145]
        NSColor.white.withAlphaComponent(0.82).setFill()
        for (index, offset) in marks.enumerated() {
            let height = index.isMultiple(of: 2) ? size * 0.045 : size * 0.03
            let rect = CGRect(x: markInsetX + size * offset, y: badgeRect.minY + size * 0.05, width: markWidth, height: height)
            NSBezierPath(rect: rect).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawSymbol(
        _ name: String,
        in rect: CGRect,
        pointSize: CGFloat,
        color: NSColor,
        weight: NSFont.Weight
    ) {
        guard let symbol = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        ) else { return }

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let tinted = configured.copy() as? NSImage ?? configured
        tinted.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setBlendMode(.sourceAtop)
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: tinted.size))
        }
        tinted.unlockFocus()
        tinted.draw(in: rect)
    }
}
