import AppKit
import SwiftUI

struct LayoutTracerCanvasView: View {
    @Bindable var document: TracingDocument
    private let rulerThickness: CGFloat = 24
    private let guideRemovalThreshold: Double = 8
    @State private var dragOrigin: TracingKey?
    @State private var resizeOrigin: TracingKey?
    @State private var layoutResizeOrigin: CGRect?
    @State private var layoutMoveLastTranslation: CGSize?
    @State private var draggingGuideID: UUID?
    @State private var draggingGuideOrigin: Double?
    @State private var pendingVerticalGuide: Double?
    @State private var pendingHorizontalGuide: Double?

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                let contentSize = CGSize(
                    width: document.editorTotalWidth * document.zoom,
                    height: document.editorTotalHeight * document.zoom
                )
                let canvasOrigin = CGPoint(x: rulerThickness, y: rulerThickness)

                ZStack(alignment: .topLeading) {
                    rulerCorner
                    topRuler(contentSize: contentSize)
                    leftRuler(contentSize: contentSize)

                    checkerboard
                        .contentShape(Rectangle())
                        .offset(x: canvasOrigin.x, y: canvasOrigin.y)

                    if let url = document.backgroundImageURL, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: document.imageSize.width * document.zoom, height: document.imageSize.height * document.zoom)
                            .opacity(document.imageOpacity)
                            .contentShape(Rectangle())
                            .offset(x: canvasOrigin.x, y: canvasOrigin.y)
                    }

                    if document.showsAnalysisLayer, let analysis = document.analysis {
                        ForEach(analysis.proposals) { proposal in
                            AnalysisProposalOverlayView(
                                proposal: proposal,
                                zoom: document.zoom,
                                coordinateScale: document.coordinateScale,
                                canvasOrigin: canvasOrigin
                            )
                        }
                    }

                    if document.showsLayoutLayer {
                        ForEach(document.guides) { guide in
                            GuideOverlayView(
                                guide: guide,
                                isSelected: guide.id == document.selectedGuideID,
                                contentSize: contentSize,
                                canvasOrigin: canvasOrigin,
                                zoom: document.zoom,
                                coordinateScale: document.coordinateScale,
                                onSelect: {
                                    document.selectGuide(id: guide.id)
                                },
                                onMove: { translation, final in
                                    moveGuide(id: guide.id, translation: translation, final: final)
                                }
                            )
                        }
                    }

                    if let pendingVerticalGuide {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 2, height: contentSize.height)
                            .offset(x: canvasOrigin.x + (pendingVerticalGuide * document.zoom * document.coordinateScale) - 1, y: canvasOrigin.y)
                    }

                    if let pendingHorizontalGuide {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: contentSize.width, height: 2)
                            .offset(x: canvasOrigin.x, y: canvasOrigin.y + (pendingHorizontalGuide * document.zoom * document.coordinateScale) - 1)
                    }

                    if document.showsLayoutLayer, let layoutBounds = document.layoutBounds {
                        LayoutBoundsOverlayView(
                            bounds: layoutBounds,
                            isSelected: document.isLayoutSelected,
                            zoom: document.zoom,
                            coordinateScale: document.coordinateScale,
                            canvasOrigin: canvasOrigin,
                            onSelect: {
                                document.selectLayout()
                            },
                            onMove: { translation, final in
                                moveLayout(translation: translation, final: final)
                            },
                            onResize: { translation, final in
                                resizeLayout(translation: translation, final: final)
                            }
                        )
                    }

                    if document.showsLayoutLayer {
                        ForEach(document.keys) { key in
                            KeyOverlayView(
                                key: key,
                                isSelected: key.id == document.selectedKeyID,
                                cornerRadius: document.keyCornerRadius,
                                zoom: document.zoom,
                                coordinateScale: document.coordinateScale,
                                canvasOrigin: canvasOrigin,
                                onSelect: { document.selectKey(id: key.id) },
                                onMove: { translation, final in
                                    move(keyID: key.id, translation: translation, final: final)
                                },
                                onResize: { translation, final in
                                    resize(keyID: key.id, translation: translation, final: final)
                                }
                            )
                        }
                    }
                }
                .frame(width: contentSize.width + rulerThickness, height: contentSize.height + rulerThickness, alignment: .topLeading)
                .background(canvasBackground)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            handleCanvasTap(at: value.location, canvasOrigin: canvasOrigin)
                        }
                )
                .focusable()
                .onMoveCommand(perform: handleMoveCommand)
                .onDeleteCommand(perform: handleDeleteCommand)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                updateViewport(proxy.size)
            }
            .onChange(of: proxy.size) { _, newValue in
                updateViewport(newValue)
            }
        }
    }

    @ViewBuilder
    private var canvasBackground: some View {
        // .glassEffect ships in the macOS 26 SDK (Swift 6.2+). Gate at compile
        // time so the module still builds on older SDKs — the runtime
        // #available check alone isn't enough because the compiler can't
        // type-check the call on older SDKs even inside the guarded branch.
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.tint(.white.opacity(0.02)), in: .rect(cornerRadius: 22))
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.12))
        }
        #else
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.black.opacity(0.12))
        #endif
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let block = 24.0
            for row in stride(from: 0.0, to: size.height, by: block) {
                for column in stride(from: 0.0, to: size.width, by: block) {
                    let even = Int((row / block) + (column / block)).isMultiple(of: 2)
                    let rect = CGRect(x: column, y: row, width: block, height: block)
                    context.fill(Path(rect), with: .color(even ? Color.white.opacity(0.04) : Color.clear))
                }
            }
        }
        .frame(width: document.editorTotalWidth * document.zoom, height: document.editorTotalHeight * document.zoom)
    }

    private var rulerCorner: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: rulerThickness, height: rulerThickness)
    }

    private func topRuler(contentSize: CGSize) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: contentSize.width, height: rulerThickness)
            .offset(x: rulerThickness, y: 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        pendingVerticalGuide = max(0, min(value.location.x / (document.zoom * document.coordinateScale), document.editorTotalWidth / document.coordinateScale))
                    }
                    .onEnded { value in
                        let position = max(0, min(value.location.x / (document.zoom * document.coordinateScale), document.editorTotalWidth / document.coordinateScale))
                        pendingVerticalGuide = nil
                        document.addGuide(axis: .vertical, position: position)
                    }
            )
    }

    private func leftRuler(contentSize: CGSize) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: rulerThickness, height: contentSize.height)
            .offset(x: 0, y: rulerThickness)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        pendingHorizontalGuide = max(0, min(value.location.y / (document.zoom * document.coordinateScale), document.editorTotalHeight / document.coordinateScale))
                    }
                    .onEnded { value in
                        let position = max(0, min(value.location.y / (document.zoom * document.coordinateScale), document.editorTotalHeight / document.coordinateScale))
                        pendingHorizontalGuide = nil
                        document.addGuide(axis: .horizontal, position: position)
                    }
            )
    }

    private func move(keyID: UUID, translation: CGSize, final: Bool) {
        guard let key = document.keys.first(where: { $0.id == keyID }) else { return }
        if dragOrigin?.id != keyID {
            dragOrigin = key
            document.beginInteractiveChange()
        }
        guard var origin = dragOrigin else { return }
        origin.x += translation.width / (document.zoom * document.coordinateScale)
        origin.y += translation.height / (document.zoom * document.coordinateScale)
        let candidate = document.snapMoveIfNeeded(for: origin)
        document.updateKey(candidate)
        document.selectedKeyID = keyID
        if final {
            dragOrigin = nil
            document.endInteractiveChange()
        }
    }

    private func resize(keyID: UUID, translation: CGSize, final: Bool) {
        guard let key = document.keys.first(where: { $0.id == keyID }) else { return }
        if resizeOrigin?.id != keyID {
            resizeOrigin = key
            document.beginInteractiveChange()
        }
        guard var origin = resizeOrigin else { return }
        origin.width += translation.width / (document.zoom * document.coordinateScale)
        origin.height += translation.height / (document.zoom * document.coordinateScale)
        let candidate = document.snapResizeIfNeeded(for: origin)
        document.updateKey(candidate)
        document.selectedKeyID = keyID
        if final {
            resizeOrigin = nil
            document.endInteractiveChange()
        }
    }

    private func moveGuide(id: UUID, translation: CGSize, final: Bool) {
        guard let guide = document.guides.first(where: { $0.id == id }) else { return }
        if draggingGuideID != id {
            draggingGuideID = id
            draggingGuideOrigin = guide.position
            document.beginInteractiveChange()
        }
        guard let origin = draggingGuideOrigin else { return }
        let delta: Double
        switch guide.axis {
        case .horizontal:
            delta = translation.height / (document.zoom * document.coordinateScale)
        case .vertical:
            delta = translation.width / (document.zoom * document.coordinateScale)
        }
        let proposedPosition = origin + delta
        if final, proposedPosition <= guideRemovalThreshold {
            document.removeGuide(id: id)
        } else {
            document.updateGuide(id: id, position: proposedPosition)
        }
        if final {
            draggingGuideID = nil
            draggingGuideOrigin = nil
            document.endInteractiveChange()
        }
    }

    private func resizeLayout(translation: CGSize, final: Bool) {
        guard let bounds = document.layoutBounds, bounds.width > 0, bounds.height > 0 else { return }
        if layoutResizeOrigin == nil {
            layoutResizeOrigin = bounds
            document.beginInteractiveChange()
            document.selectLayout()
        }
        guard let origin = layoutResizeOrigin else { return }

        let translatedWidth = max(40 / document.coordinateScale, origin.width + (translation.width / (document.zoom * document.coordinateScale)))
        let translatedHeight = max(40 / document.coordinateScale, origin.height + (translation.height / (document.zoom * document.coordinateScale)))
        let scale = max(translatedWidth / origin.width, translatedHeight / origin.height)

        let currentBounds = document.layoutBounds ?? origin
        document.scaleLayout(by: scale / max(currentBounds.width / origin.width, 0.0001), anchor: origin.origin)

        if final {
            layoutResizeOrigin = nil
            document.endInteractiveChange()
        }
    }

    private func moveLayout(translation: CGSize, final: Bool) {
        if layoutMoveLastTranslation == nil {
            layoutMoveLastTranslation = .zero
            document.beginInteractiveChange()
            document.selectLayout()
        }

        let previousTranslation = layoutMoveLastTranslation ?? .zero
        let delta = CGSize(
            width: (translation.width - previousTranslation.width) / (document.zoom * document.coordinateScale),
            height: (translation.height - previousTranslation.height) / (document.zoom * document.coordinateScale)
        )
        document.translateLayout(by: delta)
        layoutMoveLastTranslation = translation

        if final {
            layoutMoveLastTranslation = nil
            document.endInteractiveChange()
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        let delta: Double = NSEvent.modifierFlags.contains(.shift) ? 10 : 1
        switch direction {
        case .left:
            document.nudgeSelectedKey(dx: -delta, dy: 0)
        case .right:
            document.nudgeSelectedKey(dx: delta, dy: 0)
        case .up:
            document.nudgeSelectedKey(dx: 0, dy: -delta)
        case .down:
            document.nudgeSelectedKey(dx: 0, dy: delta)
        @unknown default:
            break
        }
    }

    private func handleCanvasTap(at location: CGPoint, canvasOrigin: CGPoint) {
        if document.showsLayoutLayer, let keyID = keyID(at: location, canvasOrigin: canvasOrigin) {
            document.selectKey(id: keyID)
        } else if document.showsLayoutLayer, layoutContains(location: location, canvasOrigin: canvasOrigin) {
            document.selectLayout()
        } else {
            document.selectKey(id: nil)
            document.selectGuide(id: nil)
            document.isLayoutSelected = false
        }
    }

    private func keyID(at location: CGPoint, canvasOrigin: CGPoint) -> UUID? {
        let scale = document.zoom * document.coordinateScale
        for key in document.keys.reversed() {
            let frame = key.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
            let shiftedFrame = frame.offsetBy(dx: canvasOrigin.x, dy: canvasOrigin.y)
            if shiftedFrame.contains(location) {
                return key.id
            }
        }
        return nil
    }

    private func updateViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        document.canvasViewportSize = size
    }

    private func layoutContains(location: CGPoint, canvasOrigin: CGPoint) -> Bool {
        guard let layoutBounds = document.layoutBounds else { return false }
        let scale = document.zoom * document.coordinateScale
        let frame = layoutBounds
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: canvasOrigin.x, dy: canvasOrigin.y)
        return frame.contains(location)
    }

    private func handleDeleteCommand() {
        if document.showsLayoutLayer, document.selectedGuideID != nil {
            document.removeSelectedGuide()
        } else if document.showsLayoutLayer, document.selectedKeyID != nil {
            document.removeSelectedKey()
        }
    }
}
