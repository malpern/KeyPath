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
    var padding: SIMD2<Float> = .zero
}

final class KeyboardStageMetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let stateLock = NSLock()
    private var frame: KeyboardStagePresentedFrame
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
        pipeline = try KeyboardStageMetalLibrary.makePipeline(device: device)
        self.frame = frame
        self.onFirstFramePresented = onFirstFramePresented
        self.onFailure = onFailure
        super.init()
    }

    func update(frame: KeyboardStagePresentedFrame) {
        stateLock.lock()
        self.frame = frame
        stateLock.unlock()
    }

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0,
              view.drawableSize.height > 0,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
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
        stateLock.unlock()

        let instances = makeInstances(
            frame: currentFrame,
            drawableSize: view.drawableSize
        )
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            (view as? KeyboardStageMTKView)?.cancelPendingDraw()
            reportFailure(KeyboardStageMetalError.commandBufferUnavailable)
            return
        }

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            (view as? KeyboardStageMTKView)?.cancelPendingDraw()
            reportFailure(KeyboardStageMetalError.renderEncoderUnavailable)
            return
        }

        encoder.label = "KeyPath keyboard stage"
        encoder.setRenderPipelineState(pipeline)
        if !instances.isEmpty {
            let bufferLength = instances.count * MemoryLayout<KeyboardStageGPUInstance>.stride
            let instanceBuffer: (any MTLBuffer)? = instances.withUnsafeBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return nil }
                return device.makeBuffer(
                    bytes: baseAddress,
                    length: bufferLength,
                    options: .storageModeShared
                )
            }
            guard let instanceBuffer else {
                encoder.endEncoding()
                (view as? KeyboardStageMTKView)?.cancelPendingDraw()
                reportFailure(KeyboardStageMetalError.bufferUnavailable)
                return
            }

            var uniforms = KeyboardStageGPUUniforms(
                viewportSize: SIMD2(
                    Float(view.drawableSize.width),
                    Float(view.drawableSize.height)
                )
            )
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<KeyboardStageGPUUniforms>.stride,
                index: 1
            )
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: instances.count
            )
        }
        encoder.endEncoding()

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
            makeInstance(
                frame: projection.projectKey(key),
                rotationRadians: key.rotationRadians,
                style: palette.style(for: key.role),
                opacity: key.opacity,
                pressure: key.pressure,
                glow: key.glow,
                lighting: lighting.lighting(for: key),
                cornerRatio: 0.31,
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
            0.34
        case .capsEcho:
            0.31
        case .modifierToken:
            0.48
        case .launcherCandidateMarker:
            0.96
        }
        return makeInstance(
            frame: projection.projectDecoration(decoration),
            rotationRadians: decoration.rotationRadians,
            style: palette.style(for: decoration.role),
            opacity: decoration.opacity,
            pressure: decoration.pressure,
            glow: decoration.glow,
            lighting: lighting.lighting(for: decoration),
            cornerRatio: cornerRatio,
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
        lighting: KeyboardStageSurfaceLighting,
        cornerRatio: Float,
        drawableSize: CGSize
    ) -> KeyboardStageGPUInstance {
        let width = max(1, Float(drawableSize.width))
        let height = max(1, Float(drawableSize.height))
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
                11 + max(glow, lighting.transientGlow) * 10,
                0
            ),
            lighting: SIMD4(
                lighting.illumination,
                lighting.transientGlow,
                lighting.shadowStrength,
                lighting.legendOpacity
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
