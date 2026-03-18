import AppKit
import CoreGraphics
import Foundation
import Observation

@Observable
final class TracingDocument {
    private struct Snapshot: Equatable {
        var layoutID: String
        var layoutName: String
        var layoutFileURL: URL?
        var backgroundImageURL: URL?
        var backgroundImageSize: CGSize
        var keys: [TracingKey]
        var guides: [TracingGuide]
        var analysis: LayoutAnalysisDocument?
        var showsAnalysisLayer: Bool
        var selectedKeyID: UUID?
        var selectedGuideID: UUID?
        var isLayoutSelected: Bool
    }

    private let maxUndoSnapshots = 200
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var interactionSnapshot: Snapshot?

    var layoutID = "custom-layout"
    var layoutName = "Custom Layout"
    var layoutFileURL: URL?
    var backgroundImageURL: URL?
    var backgroundImageSize = CGSize(width: 1600, height: 700)
    var keys: [TracingKey] = []
    var guides: [TracingGuide] = []
    var analysis: LayoutAnalysisDocument?
    var showsAnalysisLayer = true
    var showsLayoutLayer = true
    var selectedKeyID: UUID?
    var selectedGuideID: UUID?
    var isLayoutSelected = false
    var zoom: Double = 0.75
    var coordinateScale: Double = 1.0
    var canvasViewportSize = CGSize.zero
    var showsSnapGuides = true
    var snapEnabled = true
    var imageOpacity = 1.0
    var keyCornerRadius: Double = 10
    var exportsExplicitBounds = false

    var selectedKey: TracingKey? {
        get { keys.first(where: { $0.id == selectedKeyID }) }
        set {
            guard let newValue else {
                selectedKeyID = nil
                return
            }
            updateKey(newValue)
            selectedKeyID = newValue.id
            selectedGuideID = nil
            isLayoutSelected = false
        }
    }

    var selectedGuide: TracingGuide? {
        guides.first(where: { $0.id == selectedGuideID })
    }

    var layoutBounds: CGRect? {
        guard let first = keys.first else { return nil }
        return keys.dropFirst().reduce(first.rect) { partial, key in
            partial.union(key.rect)
        }
    }

    var totalWidth: Double {
        max(Double(backgroundImageSize.width), keys.map(\.rect.maxX).max() ?? 0)
    }

    var totalHeight: Double {
        max(Double(backgroundImageSize.height), keys.map(\.rect.maxY).max() ?? 0)
    }

    var editorTotalWidth: Double {
        max(Double(backgroundImageSize.width), (keys.map(\.rect.maxX).max() ?? 0) * coordinateScale)
    }

    var editorTotalHeight: Double {
        max(Double(backgroundImageSize.height), (keys.map(\.rect.maxY).max() ?? 0) * coordinateScale)
    }

    var imageSize: CGSize {
        backgroundImageSize
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var hasGuides: Bool {
        !guides.isEmpty
    }

    var hasAnalysisProposals: Bool {
        !(analysis?.proposals.isEmpty ?? true)
    }

    var hasLayoutOverlay: Bool {
        !keys.isEmpty
    }

    func loadImage(from url: URL) throws {
        captureUndoSnapshot()
        guard let image = NSImage(contentsOf: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backgroundImageURL = url
        let size = image.size
        if size.width > 0, size.height > 0 {
            backgroundImageSize = size
        }
        if !keys.isEmpty {
            fitLayoutToImage(recordUndo: false)
        }
        redoStack.removeAll()
    }

    func clearImage() {
        guard backgroundImageURL != nil else { return }
        captureUndoSnapshot()
        backgroundImageURL = nil
        redoStack.removeAll()
    }

    func loadLayout(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try LayoutTracerImporter.load(from: data)
        let existingImageSize = backgroundImageSize
        let hadBackgroundImage = backgroundImageURL != nil
        layoutID = imported.id
        layoutName = imported.name
        layoutFileURL = url
        keys = imported.keys
        selectedKeyID = keys.first?.id
        coordinateScale = imported.recommendedCoordinateScale
        exportsExplicitBounds = imported.usesExplicitBounds
        if let totalWidth = imported.totalWidth, let totalHeight = imported.totalHeight {
            backgroundImageSize = CGSize(width: totalWidth * coordinateScale, height: totalHeight * coordinateScale)
        } else if !hadBackgroundImage {
            backgroundImageSize = .zero
        } else {
            backgroundImageSize = existingImageSize
        }
        if hadBackgroundImage {
            fitLayoutToImage(recordUndo: false)
        }
        clearHistory()
    }

    func addKey() {
        captureUndoSnapshot()
        let defaultWidth = max(60, min(backgroundImageSize.width * 0.05, 110))
        let defaultHeight = max(55, min(backgroundImageSize.height * 0.08, 90))
        let centerX = max(24, (backgroundImageSize.width - defaultWidth) / 2)
        let centerY = max(24, (backgroundImageSize.height - defaultHeight) / 2)
        let nextCode = UInt16(keys.count)
        let newKey = TracingKey(
            keyCode: nextCode,
            label: "K\(keys.count + 1)",
            x: centerX / coordinateScale,
            y: centerY / coordinateScale,
            width: defaultWidth / coordinateScale,
            height: defaultHeight / coordinateScale
        )
        keys.append(newKey)
        selectedKeyID = newKey.id
        redoStack.removeAll()
    }

    func duplicateSelectedKey() {
        guard let selectedKey else { return }
        captureUndoSnapshot()
        let duplicate = TracingKey(
            keyCode: UInt16(keys.count),
            label: selectedKey.label.isEmpty ? "K\(keys.count + 1)" : selectedKey.label,
            x: selectedKey.x + (12 / coordinateScale),
            y: selectedKey.y + (12 / coordinateScale),
            width: selectedKey.width,
            height: selectedKey.height,
            rotation: selectedKey.rotation,
            rotationPivotX: selectedKey.rotationPivotX,
            rotationPivotY: selectedKey.rotationPivotY
        )
        keys.append(duplicate)
        selectedKeyID = duplicate.id
        redoStack.removeAll()
    }

    func removeSelectedKey() {
        guard let selectedKeyID else { return }
        captureUndoSnapshot()
        keys.removeAll { $0.id == selectedKeyID }
        self.selectedKeyID = nil
        redoStack.removeAll()
    }

    func selectKey(id: UUID?) {
        selectedKeyID = id
        if id != nil {
            selectedGuideID = nil
            isLayoutSelected = false
        }
    }

    func selectGuide(id: UUID?) {
        selectedGuideID = id
        if id != nil {
            selectedKeyID = nil
            isLayoutSelected = false
        }
    }

    func selectLayout() {
        isLayoutSelected = true
        selectedKeyID = nil
        selectedGuideID = nil
    }

    func updateKey(_ updatedKey: TracingKey) {
        guard let index = keys.firstIndex(where: { $0.id == updatedKey.id }) else { return }
        keys[index] = updatedKey
    }

    func nudgeSelectedKey(dx: Double, dy: Double) {
        guard var selectedKey else { return }
        captureUndoSnapshot()
        selectedKey.x += dx
        selectedKey.y += dy
        selectedKey = clamp(key: selectedKey)
        self.selectedKey = snapMoveIfNeeded(for: selectedKey)
        redoStack.removeAll()
    }

    func setSelectedKeyRect(_ rect: CGRect) {
        guard var selectedKey else { return }
        selectedKey.x = rect.origin.x
        selectedKey.y = rect.origin.y
        selectedKey.width = rect.width
        selectedKey.height = rect.height
        self.selectedKey = clamp(key: selectedKey)
    }

    func rotateSelectedKey(by degrees: Double) {
        guard var selectedKey else { return }
        captureUndoSnapshot()
        let nextRotation = (selectedKey.rotation ?? 0) + degrees
        selectedKey.rotation = abs(nextRotation) < 0.001 ? nil : nextRotation
        self.selectedKey = selectedKey
        redoStack.removeAll()
    }

    func snapMoveIfNeeded(for key: TracingKey) -> TracingKey {
        guard snapEnabled else { return clamp(key: key) }
        return LayoutTracerSnapEngine.snapMove(
            moving: clamp(key: key),
            others: keys.filter { $0.id != key.id },
            guides: guides
        )
    }

    func snapResizeIfNeeded(for key: TracingKey) -> TracingKey {
        guard snapEnabled else { return clamp(key: key) }
        return LayoutTracerSnapEngine.snapResize(
            resizing: clamp(key: key),
            others: keys.filter { $0.id != key.id },
            guides: guides
        )
    }

    func addGuide(axis: TracingGuide.Axis, position: Double) {
        captureUndoSnapshot()
        guides.append(TracingGuide(axis: axis, position: clampedGuidePosition(position, axis: axis)))
        redoStack.removeAll()
    }

    func updateGuide(id: UUID, position: Double) {
        guard let index = guides.firstIndex(where: { $0.id == id }) else { return }
        guides[index].position = clampedGuidePosition(position, axis: guides[index].axis)
    }

    func removeGuide(id: UUID) {
        guard guides.contains(where: { $0.id == id }) else { return }
        captureUndoSnapshot()
        guides.removeAll { $0.id == id }
        if selectedGuideID == id {
            selectedGuideID = nil
        }
        redoStack.removeAll()
    }

    func removeSelectedGuide() {
        guard let selectedGuideID else { return }
        removeGuide(id: selectedGuideID)
    }

    func clearGuides() {
        guard !guides.isEmpty else { return }
        captureUndoSnapshot()
        guides.removeAll()
        redoStack.removeAll()
    }

    func loadAnalysis(from data: Data) throws {
        captureUndoSnapshot()
        analysis = try LayoutAnalysisImporter.load(from: data)
        showsAnalysisLayer = true
        redoStack.removeAll()
    }

    func clearAnalysis() {
        guard analysis != nil else { return }
        captureUndoSnapshot()
        analysis = nil
        redoStack.removeAll()
    }

    func promoteAnalysisProposals() {
        guard let currentAnalysis = analysis, !currentAnalysis.proposals.isEmpty else { return }
        captureUndoSnapshot()
        let startingCount = keys.count
        let promoted = currentAnalysis.proposals.enumerated().map { index, proposal in
            proposal.asTracingKey(index: startingCount + index + 1)
        }
        keys.append(contentsOf: promoted)
        selectedKeyID = promoted.first?.id
        analysis = nil
        redoStack.removeAll()
    }

    func exportJSON() throws -> Data {
        let exportedWidth: Double? = exportsExplicitBounds ? (editorTotalWidth / coordinateScale) : nil
        let exportedHeight: Double? = exportsExplicitBounds ? (editorTotalHeight / coordinateScale) : nil
        return try LayoutTracerExporter.export(
            id: layoutID,
            name: layoutName,
            keys: keys,
            totalWidth: exportedWidth,
            totalHeight: exportedHeight
        )
    }

    func save(to url: URL? = nil) throws {
        let destinationURL = url ?? layoutFileURL
        guard let destinationURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try exportJSON()
        try data.write(to: destinationURL)
        layoutFileURL = destinationURL
    }

    func fitCanvasToViewport(padding: Double = 32) {
        let viewportWidth = canvasViewportSize.width - padding
        let viewportHeight = canvasViewportSize.height - padding
        guard viewportWidth > 0, viewportHeight > 0 else { return }

        let widthScale = viewportWidth / editorTotalWidth
        let heightScale = viewportHeight / editorTotalHeight
        let nextZoom = min(widthScale, heightScale)
        zoom = max(0.03, min(nextZoom, 2.0))
    }

    func fitLayoutToImage(paddingFraction: Double = 0.04, recordUndo: Bool = true) {
        guard backgroundImageURL != nil,
              let bounds = layoutBounds,
              bounds.width > 0,
              bounds.height > 0,
              backgroundImageSize.width > 0,
              backgroundImageSize.height > 0
        else { return }

        if recordUndo {
            captureUndoSnapshot()
        }

        let availableWidth = Double(backgroundImageSize.width) * (1 - (paddingFraction * 2))
        let availableHeight = Double(backgroundImageSize.height) * (1 - (paddingFraction * 2))
        guard availableWidth > 0, availableHeight > 0 else { return }

        let displayWidth = bounds.width * coordinateScale
        let displayHeight = bounds.height * coordinateScale
        guard displayWidth > 0, displayHeight > 0 else { return }

        let scale = min(availableWidth / displayWidth, availableHeight / displayHeight)
        scaleLayout(by: scale, anchor: bounds.origin)

        guard let scaledBounds = layoutBounds else { return }
        let targetMidX = Double(backgroundImageSize.width) / 2
        let targetMidY = Double(backgroundImageSize.height) / 2
        let translation = CGSize(
            width: (targetMidX - (scaledBounds.midX * coordinateScale)) / coordinateScale,
            height: (targetMidY - (scaledBounds.midY * coordinateScale)) / coordinateScale
        )
        translateLayout(by: translation)

        if recordUndo {
            redoStack.removeAll()
        }
    }

    func scaleLayout(by scale: Double, anchor: CGPoint) {
        guard scale.isFinite, scale > 0.05 else { return }
        keys = keys.map { key in
            let originX = anchor.x + ((key.x - anchor.x) * scale)
            let originY = anchor.y + ((key.y - anchor.y) * scale)
            return TracingKey(
                id: key.id,
                keyCode: key.keyCode,
                label: key.label,
                x: originX,
                y: originY,
                width: key.width * scale,
                height: key.height * scale,
                rotation: key.rotation,
                rotationPivotX: key.rotationPivotX.map { anchor.x + (($0 - anchor.x) * scale) },
                rotationPivotY: key.rotationPivotY.map { anchor.y + (($0 - anchor.y) * scale) }
            )
        }
    }

    func translateLayout(by translation: CGSize) {
        guard translation.width.isFinite, translation.height.isFinite else { return }
        keys = keys.map { key in
            TracingKey(
                id: key.id,
                keyCode: key.keyCode,
                label: key.label,
                x: key.x + translation.width,
                y: key.y + translation.height,
                width: key.width,
                height: key.height,
                rotation: key.rotation,
                rotationPivotX: key.rotationPivotX.map { $0 + translation.width },
                rotationPivotY: key.rotationPivotY.map { $0 + translation.height }
            )
        }
    }

    func updateLayoutMetadata(id: String? = nil, name: String? = nil) {
        let nextID = id ?? layoutID
        let nextName = name ?? layoutName
        guard nextID != layoutID || nextName != layoutName else { return }
        captureUndoSnapshot()
        layoutID = nextID
        layoutName = nextName
        redoStack.removeAll()
    }

    func beginInteractiveChange() {
        guard interactionSnapshot == nil else { return }
        interactionSnapshot = makeSnapshot()
    }

    func endInteractiveChange() {
        guard let interactionSnapshot else { return }
        self.interactionSnapshot = nil
        guard interactionSnapshot != makeSnapshot() else { return }
        pushUndoSnapshot(interactionSnapshot)
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(makeSnapshot())
        apply(snapshot)
        interactionSnapshot = nil
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(makeSnapshot())
        apply(snapshot)
        interactionSnapshot = nil
    }

    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        interactionSnapshot = nil
    }

    private func clamp(key: TracingKey) -> TracingKey {
        var clamped = key
        let minimumDimension = 20 / coordinateScale
        clamped.width = max(minimumDimension, clamped.width)
        clamped.height = max(minimumDimension, clamped.height)
        let maxX = max((editorTotalWidth / coordinateScale) - clamped.width, 0)
        let maxY = max((editorTotalHeight / coordinateScale) - clamped.height, 0)
        clamped.x = max(0, min(clamped.x, maxX))
        clamped.y = max(0, min(clamped.y, maxY))
        return clamped
    }

    private func captureUndoSnapshot() {
        guard interactionSnapshot == nil else { return }
        let snapshot = makeSnapshot()
        guard undoStack.last != snapshot else { return }
        pushUndoSnapshot(snapshot)
    }

    private func pushUndoSnapshot(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > maxUndoSnapshots {
            undoStack.removeFirst(undoStack.count - maxUndoSnapshots)
        }
    }

    private func makeSnapshot() -> Snapshot {
        Snapshot(
            layoutID: layoutID,
            layoutName: layoutName,
            layoutFileURL: layoutFileURL,
            backgroundImageURL: backgroundImageURL,
            backgroundImageSize: backgroundImageSize,
            keys: keys,
            guides: guides,
            analysis: analysis,
            showsAnalysisLayer: showsAnalysisLayer,
            selectedKeyID: selectedKeyID,
            selectedGuideID: selectedGuideID,
            isLayoutSelected: isLayoutSelected
        )
    }

    private func apply(_ snapshot: Snapshot) {
        layoutID = snapshot.layoutID
        layoutName = snapshot.layoutName
        layoutFileURL = snapshot.layoutFileURL
        backgroundImageURL = snapshot.backgroundImageURL
        backgroundImageSize = snapshot.backgroundImageSize
        keys = snapshot.keys
        guides = snapshot.guides
        analysis = snapshot.analysis
        showsAnalysisLayer = snapshot.showsAnalysisLayer
        selectedKeyID = snapshot.selectedKeyID
        selectedGuideID = snapshot.selectedGuideID
        isLayoutSelected = snapshot.isLayoutSelected
    }

    private func clampedGuidePosition(_ position: Double, axis: TracingGuide.Axis) -> Double {
        let maxPosition: Double
        switch axis {
        case .horizontal:
            maxPosition = max(editorTotalHeight / coordinateScale, 0)
        case .vertical:
            maxPosition = max(editorTotalWidth / coordinateScale, 0)
        }
        return max(0, min(position, maxPosition))
    }
}
