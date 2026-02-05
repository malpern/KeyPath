import AppKit
import KeyPathCore
import SwiftUI

struct OverlayAvailableWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RightRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct InspectorMaskedHost<Content: View>: NSViewRepresentable {
    var content: Content
    var reveal: CGFloat
    var totalWidth: CGFloat
    var leadingGap: CGFloat
    var slideOffset: CGFloat
    var opacity: CGFloat
    var debugEnabled: Bool

    func makeNSView(context _: Context) -> InspectorMaskedHostingView<Content> {
        InspectorMaskedHostingView(content: content)
    }

    func updateNSView(_ nsView: InspectorMaskedHostingView<Content>, context _: Context) {
        nsView.update(
            content: content,
            reveal: reveal,
            totalWidth: totalWidth,
            leadingGap: leadingGap,
            slideOffset: slideOffset,
            opacity: opacity,
            debugEnabled: debugEnabled
        )
    }
}

final class InspectorMaskedHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let maskLayer = CALayer()
    private var reveal: CGFloat = 0
    private var totalWidth: CGFloat = 0
    private var leadingGap: CGFloat = 0
    private var slideOffset: CGFloat = 0
    private var contentOpacity: CGFloat = 1
    private var debugEnabled: Bool = false
    private var lastDebugLogTime: CFTimeInterval = 0

    init(content: Content) {
        hostingView = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.mask = maskLayer
        maskLayer.backgroundColor = NSColor.black.cgColor

        hostingView.wantsLayer = true
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        content: Content,
        reveal: CGFloat,
        totalWidth: CGFloat,
        leadingGap: CGFloat,
        slideOffset: CGFloat,
        opacity: CGFloat,
        debugEnabled: Bool
    ) {
        hostingView.rootView = content
        self.reveal = reveal
        self.totalWidth = totalWidth
        self.leadingGap = leadingGap
        self.slideOffset = slideOffset
        contentOpacity = opacity
        self.debugEnabled = debugEnabled
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let bounds = bounds
        hostingView.frame = bounds.offsetBy(dx: slideOffset, dy: 0)
        hostingView.alphaValue = contentOpacity

        let widthBasis = totalWidth > 0 ? totalWidth : bounds.width
        let gap = max(0, min(leadingGap, widthBasis))
        let panelWidth = max(0, widthBasis - gap)
        let width = max(0, min(widthBasis, gap + panelWidth * reveal))
        maskLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)

        guard debugEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDebugLogTime > 0.2 else { return }
        lastDebugLogTime = now
        let revealStr = String(format: "%.3f", reveal)
        let slideStr = String(format: "%.1f", slideOffset)
        let widthStr = String(format: "%.1f", width)
        let gapStr = String(format: "%.1f", gap)
        let opacityStr = String(format: "%.2f", contentOpacity)
        AppLogger.shared.log(
            "🧱 [OverlayInspectorMask] bounds=\(bounds.size.debugDescription) reveal=\(revealStr) slide=\(slideStr) gap=\(gapStr) maskW=\(widthStr) opacity=\(opacityStr)"
        )
    }
}
