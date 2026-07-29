import AppKit
import Metal
import MetalKit

private struct KeyboardStageGPUInstance {
    var geometry: SIMD4<Float>
    var fillColor: SIMD4<Float>
    var accentColor: SIMD4<Float>
    var glowColor: SIMD4<Float>
    var parameters: SIMD4<Float>
    var treatment: SIMD4<Float>
    var lighting: SIMD4<Float>
}

private struct KeyboardStageGPUUniforms {
    var viewportSize: SIMD2<Float>
    var entrance: SIMD2<Float>
    var windowX: SIMD2<Float>
    var cinematicLighting: SIMD4<Float>
}

private struct KeyboardStageGPULegendInstance {
    var geometry: SIMD4<Float>
    var uvRect: SIMD4<Float>
    var settledColor: SIMD4<Float>
    var parameters: SIMD4<Float>
}

private struct KeyboardStageGPUPostUniforms {
    var sourceAndBloomSize: SIMD4<Float>
    var entranceAndDirection: SIMD4<Float>
}

private struct KeyboardStageMetalRenderTargets {
    let width: Int
    let height: Int
    let bloomWidth: Int
    let bloomHeight: Int
    let scene: any MTLTexture
    let bloomA: any MTLTexture
    let bloomB: any MTLTexture
}

private struct KeyboardStageLegendDrawItem {
    let descriptor: KeyboardStageLegendAtlasDescriptor
    let frame: CGRect
    let settledColor: KeyboardStageRGBA
    let opacity: Float
    let entranceEmission: Float
    let roleEmission: Float
    let alignment: KeyboardStageLegendAtlasDescriptor.Alignment
}

final class KeyboardStageMetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let pipelines: KeyboardStageMetalPipelines
    private let legendAtlasCache = KeyboardStageLegendAtlasCache()
    private let stateLock = NSLock()
    private var frame: KeyboardStagePresentedFrame
    private var windowX = SIMD2<Float>(0, 1)
    private var renderTargets: KeyboardStageMetalRenderTargets?
    private var didReportFailure = false
    private var didReportFirstFrame = false
    private let onFirstFramePresented: @MainActor @Sendable () -> Void
    private let onFailure: @MainActor @Sendable (Error) -> Void

    init(
        device: any MTLDevice,
        frame: KeyboardStagePresentedFrame,
        onFirstFramePresented: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable (Error) -> Void
    ) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw KeyboardStageMetalError.commandQueueUnavailable
        }
        self.commandQueue = commandQueue
        pipelines = try KeyboardStageMetalLibrary.makePipelines(device: device)
        self.frame = frame
        self.onFirstFramePresented = onFirstFramePresented
        self.onFailure = onFailure
        super.init()
    }

    func update(frame: KeyboardStagePresentedFrame, windowX: SIMD2<Float>) {
        stateLock.lock()
        self.frame = frame
        self.windowX = windowX
        stateLock.unlock()
    }

    func update(windowX: SIMD2<Float>) {
        stateLock.lock()
        self.windowX = windowX
        stateLock.unlock()
    }

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0,
              view.drawableSize.height > 0,
              let drawableRenderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable
        else {
            guard let stageView = view as? KeyboardStageMTKView,
                  stageView.drawableUnavailable()
            else {
                reportFailure(KeyboardStageMetalError.drawableUnavailable)
                return
            }
            return
        }

        stateLock.lock()
        let currentFrame = frame
        let currentWindowX = windowX
        stateLock.unlock()

        let instances = makeInstances(
            frame: currentFrame,
            drawableSize: view.drawableSize
        )
        let legendSnapshot: KeyboardStageLegendAtlasSnapshot
        let legendInstances: [KeyboardStageGPULegendInstance]
        do {
            let legendRenderData = try makeLegendRenderData(
                frame: currentFrame,
                drawableSize: view.drawableSize
            )
            legendSnapshot = legendRenderData.snapshot
            legendInstances = legendRenderData.instances
        } catch {
            (view as? KeyboardStageMTKView)?.cancelPendingDraw()
            reportFailure(
                KeyboardStageMetalError.legendAtlasUnavailable(
                    String(describing: error)
                )
            )
            return
        }

        let targets: KeyboardStageMetalRenderTargets
        do {
            targets = try renderTargets(for: view.drawableSize)
        } catch {
            (view as? KeyboardStageMTKView)?.cancelPendingDraw()
            reportFailure(error)
            return
        }

        guard let instanceBuffer = makeBuffer(values: instances),
              let legendBuffer = makeBuffer(values: legendInstances)
        else {
            (view as? KeyboardStageMTKView)?.cancelPendingDraw()
            reportFailure(KeyboardStageMetalError.bufferUnavailable)
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            (view as? KeyboardStageMTKView)?.cancelPendingDraw()
            reportFailure(KeyboardStageMetalError.commandBufferUnavailable)
            return
        }

        let cinematicLighting = KeyboardStageCinematicLighting.parameters(
            for: currentFrame.entrance
        )
        var uniforms = KeyboardStageGPUUniforms(
            viewportSize: SIMD2(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            ),
            entrance: SIMD2(
                currentFrame.entrance.progress,
                currentFrame.entrance.reduceMotion ? 1 : 0
            ),
            windowX: currentWindowX,
            cinematicLighting: cinematicLighting.gpuVector
        )
        var postUniforms = KeyboardStageGPUPostUniforms(
            sourceAndBloomSize: SIMD4(
                Float(targets.width),
                Float(targets.height),
                Float(targets.bloomWidth),
                Float(targets.bloomHeight)
            ),
            entranceAndDirection: SIMD4(
                currentFrame.entrance.progress,
                currentFrame.entrance.reduceMotion ? 1 : 0,
                1,
                0
            )
        )

        guard encodeScene(
            commandBuffer: commandBuffer,
            target: targets.scene,
            surfaceInstances: instances,
            surfaceBuffer: instanceBuffer,
            legendInstances: legendInstances,
            legendBuffer: legendBuffer,
            legendTexture: legendSnapshot.texture,
            uniforms: &uniforms
        ),
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                label: "KeyPath keyboard bright pass",
                pipeline: pipelines.brightPass,
                source: targets.scene,
                destination: targets.bloomA,
                uniforms: &postUniforms
            ),
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                label: "KeyPath keyboard bloom horizontal",
                pipeline: pipelines.blurHorizontal,
                source: targets.bloomA,
                destination: targets.bloomB,
                uniforms: &postUniforms
            ),
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                label: "KeyPath keyboard bloom vertical",
                pipeline: pipelines.blurVertical,
                source: targets.bloomB,
                destination: targets.bloomA,
                uniforms: &postUniforms
            ),
            encodeComposite(
                commandBuffer: commandBuffer,
                descriptor: drawableRenderPassDescriptor,
                scene: targets.scene,
                bloom: targets.bloomA,
                uniforms: &postUniforms
            )
        else {
            (view as? KeyboardStageMTKView)?.cancelPendingDraw()
            reportFailure(KeyboardStageMetalError.renderEncoderUnavailable)
            return
        }

        drawable.addPresentedHandler { [weak self] _ in
            self?.reportFirstFramePresentedIfNeeded()
        }
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] completedBuffer in
            guard completedBuffer.status == .error else { return }
            let message = completedBuffer.error?.localizedDescription ?? "Unknown Metal error"
            self?.reportFailure(KeyboardStageMetalError.commandFailed(message))
        }
        commandBuffer.commit()
        (view as? KeyboardStageMTKView)?.markDrawSubmitted()
    }

    private func encodeScene(
        commandBuffer: any MTLCommandBuffer,
        target: any MTLTexture,
        surfaceInstances: [KeyboardStageGPUInstance],
        surfaceBuffer: any MTLBuffer,
        legendInstances: [KeyboardStageGPULegendInstance],
        legendBuffer: any MTLBuffer,
        legendTexture: any MTLTexture,
        uniforms: inout KeyboardStageGPUUniforms
    ) -> Bool {
        let descriptor = renderPassDescriptor(texture: target, loadAction: .clear)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }

        encoder.label = "KeyPath keyboard HDR scene"
        if !surfaceInstances.isEmpty {
            encoder.setRenderPipelineState(pipelines.surface)
            encoder.setVertexBuffer(surfaceBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<KeyboardStageGPUUniforms>.stride,
                index: 1
            )
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<KeyboardStageGPUUniforms>.stride,
                index: 1
            )
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: surfaceInstances.count
            )
        }

        if !legendInstances.isEmpty {
            encoder.setRenderPipelineState(pipelines.legend)
            encoder.setVertexBuffer(legendBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<KeyboardStageGPUUniforms>.stride,
                index: 1
            )
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<KeyboardStageGPUUniforms>.stride,
                index: 1
            )
            encoder.setFragmentTexture(legendTexture, index: 0)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: legendInstances.count
            )
        }

        encoder.endEncoding()
        return true
    }

    private func encodeFullscreenPass(
        commandBuffer: any MTLCommandBuffer,
        label: String,
        pipeline: any MTLRenderPipelineState,
        source: any MTLTexture,
        destination: any MTLTexture,
        uniforms: inout KeyboardStageGPUPostUniforms
    ) -> Bool {
        let descriptor = renderPassDescriptor(texture: destination, loadAction: .clear)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }

        encoder.label = label
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<KeyboardStageGPUPostUniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func encodeComposite(
        commandBuffer: any MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        scene: any MTLTexture,
        bloom: any MTLTexture,
        uniforms: inout KeyboardStageGPUPostUniforms
    ) -> Bool {
        let attachment = descriptor.colorAttachments[0]
        attachment?.loadAction = .clear
        attachment?.storeAction = .store
        attachment?.clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }

        encoder.label = "KeyPath keyboard tone-map composite"
        encoder.setRenderPipelineState(pipelines.composite)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<KeyboardStageGPUPostUniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(scene, index: 0)
        encoder.setFragmentTexture(bloom, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func renderPassDescriptor(
        texture: any MTLTexture,
        loadAction: MTLLoadAction
    ) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        let attachment = descriptor.colorAttachments[0]
        attachment?.texture = texture
        attachment?.loadAction = loadAction
        attachment?.storeAction = .store
        attachment?.clearColor = MTLClearColorMake(0, 0, 0, 0)
        return descriptor
    }

    private func renderTargets(
        for drawableSize: CGSize
    ) throws -> KeyboardStageMetalRenderTargets {
        let width = max(1, Int(drawableSize.width.rounded(.up)))
        let height = max(1, Int(drawableSize.height.rounded(.up)))
        if let renderTargets,
           renderTargets.width == width,
           renderTargets.height == height
        {
            return renderTargets
        }

        let bloomWidth = max(1, (width + 3) / 4)
        let bloomHeight = max(1, (height + 3) / 4)
        guard let scene = makeRenderTexture(
            width: width,
            height: height,
            label: "KeyPath keyboard HDR scene"
        ),
            let bloomA = makeRenderTexture(
                width: bloomWidth,
                height: bloomHeight,
                label: "KeyPath keyboard bloom A"
            ),
            let bloomB = makeRenderTexture(
                width: bloomWidth,
                height: bloomHeight,
                label: "KeyPath keyboard bloom B"
            )
        else {
            throw KeyboardStageMetalError.textureUnavailable
        }

        let targets = KeyboardStageMetalRenderTargets(
            width: width,
            height: height,
            bloomWidth: bloomWidth,
            bloomHeight: bloomHeight,
            scene: scene,
            bloomA: bloomA,
            bloomB: bloomB
        )
        renderTargets = targets
        return targets
    }

    private func makeRenderTexture(
        width: Int,
        height: Int,
        label: String
    ) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: KeyboardStageMetalLibrary.intermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    private func makeBuffer<Element>(values: [Element]) -> (any MTLBuffer)? {
        guard !values.isEmpty else {
            return device.makeBuffer(length: 1, options: .storageModeShared)
        }
        return values.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            return device.makeBuffer(
                bytes: baseAddress,
                length: values.count * MemoryLayout<Element>.stride,
                options: .storageModeShared
            )
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange _: CGSize) {
        (view as? KeyboardStageMTKView)?.requestDraw()
    }

    private func reportFailure(_ error: Error) {
        stateLock.lock()
        let shouldReport = !didReportFailure
        didReportFailure = true
        stateLock.unlock()
        guard shouldReport else { return }

        let handler = onFailure
        Task { @MainActor in
            handler(error)
        }
    }

    private func reportFirstFramePresentedIfNeeded() {
        stateLock.lock()
        let shouldReport = !didReportFirstFrame
        didReportFirstFrame = true
        stateLock.unlock()
        guard shouldReport else { return }

        let handler = onFirstFramePresented
        Task { @MainActor in
            handler()
        }
    }

    private func makeLegendRenderData(
        frame: KeyboardStagePresentedFrame,
        drawableSize: CGSize
    ) throws -> (
        snapshot: KeyboardStageLegendAtlasSnapshot,
        instances: [KeyboardStageGPULegendInstance]
    ) {
        let scene = frame.scene
        let projection = KeyboardStageProjection(scene: scene, size: drawableSize)
        let palette = KeyboardStagePalette(displayMode: scene.displayMode)
        let lightingResolver = KeyboardStageLightingResolver(
            scene: scene,
            entrance: frame.entrance
        )
        var items: [KeyboardStageLegendDrawItem] = []
        items.reserveCapacity(scene.keys.count * 2)

        for key in scene.keys {
            let keyFrame = materialKeyFrame(projection.projectKey(key))
            let visibility = legendVisibility(
                keyFrame: keyFrame,
                scene: scene,
                projection: projection
            )
            let lighting = lightingResolver.lighting(for: key)
            let baseOpacity = key.opacity * lighting.legendOpacity * visibility
            guard baseOpacity > 0.001 else { continue }

            let weight = legendWeight(for: key.role)
            let alignment = atlasAlignment(for: key.legend.alignment)
            let settledColor = palette.style(
                for: key.role,
                interactionLevel: key.interactionLevel
            ).legend
            let progress = min(1, max(0, key.legend.transitionProgress))
            if let previous = key.legend.previous,
               !previous.isEmpty,
               progress < 0.999
            {
                items.append(KeyboardStageLegendDrawItem(
                    descriptor: KeyboardStageLegendAtlasDescriptor(
                        primary: previous,
                        secondary: key.legend.secondary,
                        weight: weight,
                        alignment: alignment
                    ),
                    frame: keyFrame,
                    settledColor: settledColor,
                    opacity: baseOpacity * (1 - progress),
                    entranceEmission: lighting.legendGlow,
                    roleEmission: max(key.glow, key.interactionLevel),
                    alignment: alignment
                ))
            }

            if key.legend.previous == nil || progress > 0.001 {
                items.append(KeyboardStageLegendDrawItem(
                    descriptor: KeyboardStageLegendAtlasDescriptor(
                        primary: key.legend.primary,
                        secondary: key.legend.secondary,
                        weight: weight,
                        alignment: alignment
                    ),
                    frame: keyFrame,
                    settledColor: settledColor,
                    opacity: baseOpacity * (key.legend.previous == nil ? 1 : progress),
                    entranceEmission: lighting.legendGlow,
                    roleEmission: max(key.glow, key.interactionLevel),
                    alignment: alignment
                ))
            }
        }

        let snapshot = try legendAtlasCache.atlas(
            for: items.map(\.descriptor),
            device: device
        )
        let instances = try items.map { item -> KeyboardStageGPULegendInstance in
            guard let entry = snapshot.entries[item.descriptor] else {
                throw KeyboardStageMetalError.legendAtlasUnavailable(
                    "The legend atlas omitted \(item.descriptor.primary)."
                )
            }
            let uv = entry.uvRect
            let atlasRect = SIMD4<Float>(
                uv.x,
                uv.y,
                uv.z - uv.x,
                uv.w - uv.y
            )
            return KeyboardStageGPULegendInstance(
                geometry: legendGeometry(
                    keyFrame: item.frame,
                    alignment: item.alignment,
                    drawableSize: drawableSize
                ),
                uvRect: atlasRect,
                settledColor: linearColor(item.settledColor),
                parameters: SIMD4(
                    item.opacity,
                    item.entranceEmission,
                    item.roleEmission,
                    frame.scene.displayMode.reduceTransparency ? 0 : 1
                )
            )
        }
        return (snapshot, instances)
    }

    private func legendGeometry(
        keyFrame: CGRect,
        alignment: KeyboardStageLegendAtlasDescriptor.Alignment,
        drawableSize: CGSize
    ) -> SIMD4<Float> {
        let width = max(1, Float(drawableSize.width))
        let height = max(1, Float(drawableSize.height))
        // The atlas includes its own vertical padding. This resolves regular
        // legends to roughly 28% of the cap height, matching the proportions
        // of the MacBook legends in the onboarding reference.
        let legendHeight = max(1, Float(keyFrame.height) * 0.84)
        let legendWidth = legendHeight * 2
        // Edge-aligned atlas cells draw the glyphs flush to a small fixed cell
        // padding, so anchoring the quad's matching edge at the keycap's inner
        // margin puts the text where MacBook hardware prints it.
        let cellPadding = legendWidth
            * Float(
                KeyboardStageLegendAtlasRasterizer.edgeAlignedCellPadding
                    / CGFloat(KeyboardStageLegendAtlasLayout.cellWidth)
            )
        let edgeInset = Float(keyFrame.height) * 0.16
        let centerX = switch alignment {
        case .leading:
            Float(keyFrame.minX) + edgeInset - cellPadding + legendWidth / 2
        case .center:
            Float(keyFrame.midX)
        case .trailing:
            Float(keyFrame.maxX) - edgeInset + cellPadding - legendWidth / 2
        }
        return SIMD4(
            centerX / width * 2 - 1,
            1 - Float(keyFrame.midY) / height * 2,
            legendWidth / width * 2,
            legendHeight / height * 2
        )
    }

    private func legendWeight(
        for role: KeyboardStageKeyRole
    ) -> KeyboardStageLegendAtlasDescriptor.Weight {
        switch role {
        case .standard, .modifier, .recommended, .escape, .dimmed:
            .light
        case .deck, .hyper, .launcher, .installed:
            .medium
        }
    }

    private func atlasAlignment(
        for alignment: KeyboardStageLegendAlignment
    ) -> KeyboardStageLegendAtlasDescriptor.Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func legendVisibility(
        keyFrame: CGRect,
        scene: KeyboardStageScene,
        projection: KeyboardStageProjection
    ) -> Float {
        let area = max(1, keyFrame.width * keyFrame.height)
        var occlusion: Float = 0
        for decoration in scene.decorations {
            let occludes = switch decoration.kind {
            case .applicationTarget, .launcherChoiceTarget, .handoffTarget:
                true
            case .keyboardDeck, .capsEcho, .modifierToken, .launcherCandidateMarker:
                false
            }
            guard occludes else { continue }

            let intersection = keyFrame.intersection(
                projection.projectDecoration(decoration)
            )
            guard !intersection.isNull,
                  intersection.width * intersection.height / area > 0.22
            else {
                continue
            }
            occlusion = max(occlusion, decoration.opacity)
        }
        return max(0, 1 - occlusion)
    }

    private func makeInstances(
        frame: KeyboardStagePresentedFrame,
        drawableSize: CGSize
    ) -> [KeyboardStageGPUInstance] {
        let scene = frame.scene
        let projection = KeyboardStageProjection(scene: scene, size: drawableSize)
        let palette = KeyboardStagePalette(displayMode: scene.displayMode)
        let lighting = KeyboardStageLightingResolver(
            scene: scene,
            entrance: frame.entrance
        )
        var instances = scene.decorations.compactMap { decoration -> KeyboardStageGPUInstance? in
            guard decoration.kind == .keyboardDeck else { return nil }
            return makeDecorationInstance(
                decoration,
                projection: projection,
                palette: palette,
                lighting: lighting,
                drawableSize: drawableSize
            )
        }
        instances.append(contentsOf: scene.decorations.compactMap { decoration in
            guard case .capsEcho = decoration.kind else { return nil }
            return makeDecorationInstance(
                decoration,
                projection: projection,
                palette: palette,
                lighting: lighting,
                drawableSize: drawableSize
            )
        })
        instances.append(contentsOf: scene.keys.map { key in
            let visibleGlow = scene.displayMode.reduceTransparency ? 0 : key.glow
            return makeInstance(
                frame: materialKeyFrame(projection.projectKey(key)),
                rotationRadians: key.rotationRadians,
                style: palette.style(
                    for: key.role,
                    interactionLevel: key.interactionLevel
                ),
                opacity: key.opacity,
                pressure: key.pressure,
                glow: visibleGlow,
                interactionLevel: key.interactionLevel,
                lighting: lighting.lighting(for: key),
                cornerRatio: 0.31,
                materialKind: 1,
                drawableSize: drawableSize
            )
        })
        instances.append(contentsOf: scene.decorations.compactMap { decoration in
            guard decoration.kind != .keyboardDeck else { return nil }
            guard case .capsEcho = decoration.kind else {
                return makeDecorationInstance(
                    decoration,
                    projection: projection,
                    palette: palette,
                    lighting: lighting,
                    drawableSize: drawableSize
                )
            }
            return nil
        })
        return instances
    }

    private func materialKeyFrame(_ frame: CGRect) -> CGRect {
        let horizontalInset = min(3.2, frame.width * 0.045)
        let verticalInset = min(3.0, frame.height * 0.045)
        return frame.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    private func makeDecorationInstance(
        _ decoration: KeyboardStageDecoration,
        projection: KeyboardStageProjection,
        palette: KeyboardStagePalette,
        lighting: KeyboardStageLightingResolver,
        drawableSize: CGSize
    ) -> KeyboardStageGPUInstance {
        let cornerRatio: Float = switch decoration.kind {
        case .keyboardDeck:
            0.14
        case .applicationTarget, .launcherChoiceTarget, .handoffTarget:
            // Full capsule: these are floating UI chips above the deck, not
            // keycaps, and their silhouette is the first thing that says so.
            0.50
        case .capsEcho:
            0.31
        case .modifierToken:
            0.48
        case .launcherCandidateMarker:
            0.96
        }
        let materialKind: Float = switch decoration.kind {
        case .keyboardDeck:
            0
        case .capsEcho:
            1
        case .applicationTarget,
             .launcherChoiceTarget,
             .handoffTarget,
             .modifierToken,
             .launcherCandidateMarker:
            2
        }
        return makeInstance(
            frame: projection.projectDecoration(decoration),
            rotationRadians: decoration.rotationRadians,
            style: palette.style(for: decoration.role),
            opacity: decoration.opacity,
            pressure: decoration.pressure,
            glow: decoration.glow,
            interactionLevel: 0,
            lighting: lighting.lighting(for: decoration),
            cornerRatio: cornerRatio,
            materialKind: materialKind,
            drawableSize: drawableSize
        )
    }

    private func makeInstance(
        frame: CGRect,
        rotationRadians: Float,
        style: KeyboardStageSurfaceStyle,
        opacity: Float,
        pressure: Float,
        glow: Float,
        interactionLevel: Float,
        lighting: KeyboardStageSurfaceLighting,
        cornerRatio: Float,
        materialKind: Float,
        drawableSize: CGSize
    ) -> KeyboardStageGPUInstance {
        let width = max(1, Float(drawableSize.width))
        let height = max(1, Float(drawableSize.height))
        let shadowMargin: Float = if materialKind < 0.5 {
            36
        } else if materialKind < 1.5 {
            24 + max(glow, lighting.transientGlow) * 14
        } else {
            30 + max(glow, lighting.transientGlow) * 12
        }
        let centerX = Float(frame.midX) / width * 2 - 1
        let centerY = 1 - Float(frame.midY) / height * 2
        let normalizedWidth = Float(frame.width) / width * 2
        let normalizedHeight = Float(frame.height) / height * 2
        return KeyboardStageGPUInstance(
            geometry: SIMD4(centerX, centerY, normalizedWidth, normalizedHeight),
            fillColor: linearColor(style.fill),
            accentColor: linearColor(style.accent),
            glowColor: linearColor(style.glow),
            parameters: SIMD4(pressure, glow, opacity, style.borderStrength),
            treatment: SIMD4(
                rotationRadians,
                cornerRatio,
                shadowMargin,
                materialKind
            ),
            lighting: SIMD4(
                lighting.illumination,
                lighting.transientGlow,
                lighting.shadowStrength,
                interactionLevel
            )
        )
    }

    private func linearColor(_ color: KeyboardStageRGBA) -> SIMD4<Float> {
        SIMD4(
            linearComponent(color.red),
            linearComponent(color.green),
            linearComponent(color.blue),
            color.alpha
        )
    }

    private func linearComponent(_ component: Float) -> Float {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}
