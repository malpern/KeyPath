import Foundation
import Metal

enum KeyboardStageMetalError: LocalizedError, Equatable, Sendable {
    case noDevice
    case missingFunction(String)
    case commandQueueUnavailable
    case bufferUnavailable
    case textureUnavailable
    case legendAtlasUnavailable(String)
    case commandBufferUnavailable
    case renderEncoderUnavailable
    case drawableUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDevice:
            "Metal is not available on this Mac."
        case let .missingFunction(name):
            "The keyboard-stage shader function \(name) is missing."
        case .commandQueueUnavailable:
            "Metal could not create the keyboard-stage command queue."
        case .bufferUnavailable:
            "Metal could not create the keyboard-stage instance buffer."
        case .textureUnavailable:
            "Metal could not create the keyboard-stage lighting textures."
        case let .legendAtlasUnavailable(message):
            "Metal could not create the keyboard legend atlas: \(message)"
        case .commandBufferUnavailable:
            "Metal could not create a keyboard-stage command buffer."
        case .renderEncoderUnavailable:
            "Metal could not create the keyboard-stage render encoder."
        case .drawableUnavailable:
            "Metal could not acquire a keyboard-stage drawable."
        case let .commandFailed(message):
            "The keyboard-stage Metal command failed: \(message)"
        }
    }
}

struct KeyboardStageMetalPipelines {
    let surface: any MTLRenderPipelineState
    let legend: any MTLRenderPipelineState
    let brightPass: any MTLRenderPipelineState
    let blurHorizontal: any MTLRenderPipelineState
    let blurVertical: any MTLRenderPipelineState
    let composite: any MTLRenderPipelineState
}

enum KeyboardStageMetalLibrary {
    static let vertexFunctionName = "keypath_keyboard_stage_vertex"
    static let fragmentFunctionName = "keypath_keyboard_stage_fragment"
    static let legendVertexFunctionName = "keypath_keyboard_legend_vertex"
    static let legendFragmentFunctionName = "keypath_keyboard_legend_fragment"
    static let fullscreenVertexFunctionName = "keypath_fullscreen_vertex"
    static let brightPassFragmentFunctionName = "keypath_keyboard_bright_pass_fragment"
    static let blurHorizontalFragmentFunctionName = "keypath_keyboard_blur_horizontal_fragment"
    static let blurVerticalFragmentFunctionName = "keypath_keyboard_blur_vertical_fragment"
    static let compositeFragmentFunctionName = "keypath_keyboard_composite_fragment"

    static let intermediatePixelFormat = MTLPixelFormat.rgba16Float
    static let drawablePixelFormat = MTLPixelFormat.bgra8Unorm_srgb

    /// Compatibility alias for the MTKView's drawable configuration. Surface
    /// and legend rendering use `intermediatePixelFormat` before compositing.
    static let colorPixelFormat = drawablePixelFormat

    static let requiredFunctionNames = [
        vertexFunctionName,
        fragmentFunctionName,
        legendVertexFunctionName,
        legendFragmentFunctionName,
        fullscreenVertexFunctionName,
        brightPassFragmentFunctionName,
        blurHorizontalFragmentFunctionName,
        blurVerticalFragmentFunctionName,
        compositeFragmentFunctionName,
    ]

    static let isAvailable: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        do {
            let library = try loadLibrary(device: device)
            return requiredFunctionNames.allSatisfy {
                library.makeFunction(name: $0) != nil
            }
        } catch {
            return false
        }
    }()

    static func loadLibrary(device: any MTLDevice) throws -> any MTLLibrary {
        try device.makeDefaultLibrary(bundle: KeyPathAppKitResources.bundle)
    }

    /// Preserves the original entry point while moving the surface pass into
    /// the linear HDR intermediate target.
    static func makePipeline(device: any MTLDevice) throws -> any MTLRenderPipelineState {
        let library = try loadLibrary(device: device)
        return try makeRenderPipeline(
            library: library,
            label: "KeyPath keyboard stage surface",
            vertexFunctionName: vertexFunctionName,
            fragmentFunctionName: fragmentFunctionName,
            pixelFormat: intermediatePixelFormat,
            blendMode: .straightAlpha
        )
    }

    static func makePipelines(device: any MTLDevice) throws -> KeyboardStageMetalPipelines {
        let library = try loadLibrary(device: device)
        return try KeyboardStageMetalPipelines(
            surface: makeRenderPipeline(
                library: library,
                label: "KeyPath keyboard stage surface",
                vertexFunctionName: vertexFunctionName,
                fragmentFunctionName: fragmentFunctionName,
                pixelFormat: intermediatePixelFormat,
                blendMode: .straightAlpha
            ),
            legend: makeRenderPipeline(
                library: library,
                label: "KeyPath keyboard stage legends",
                vertexFunctionName: legendVertexFunctionName,
                fragmentFunctionName: legendFragmentFunctionName,
                pixelFormat: intermediatePixelFormat,
                blendMode: .straightAlpha
            ),
            brightPass: makeRenderPipeline(
                library: library,
                label: "KeyPath keyboard stage bright pass",
                vertexFunctionName: fullscreenVertexFunctionName,
                fragmentFunctionName: brightPassFragmentFunctionName,
                pixelFormat: intermediatePixelFormat,
                blendMode: .disabled
            ),
            blurHorizontal: makeRenderPipeline(
                library: library,
                label: "KeyPath keyboard stage bloom horizontal",
                vertexFunctionName: fullscreenVertexFunctionName,
                fragmentFunctionName: blurHorizontalFragmentFunctionName,
                pixelFormat: intermediatePixelFormat,
                blendMode: .disabled
            ),
            blurVertical: makeRenderPipeline(
                library: library,
                label: "KeyPath keyboard stage bloom vertical",
                vertexFunctionName: fullscreenVertexFunctionName,
                fragmentFunctionName: blurVerticalFragmentFunctionName,
                pixelFormat: intermediatePixelFormat,
                blendMode: .disabled
            ),
            composite: makeRenderPipeline(
                library: library,
                label: "KeyPath keyboard stage composite",
                vertexFunctionName: fullscreenVertexFunctionName,
                fragmentFunctionName: compositeFragmentFunctionName,
                pixelFormat: drawablePixelFormat,
                blendMode: .premultipliedAlpha
            )
        )
    }

    private enum BlendMode {
        case disabled
        case straightAlpha
        case premultipliedAlpha
    }

    private static func makeRenderPipeline(
        library: any MTLLibrary,
        label: String,
        vertexFunctionName: String,
        fragmentFunctionName: String,
        pixelFormat: MTLPixelFormat,
        blendMode: BlendMode
    ) throws -> any MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            throw KeyboardStageMetalError.missingFunction(vertexFunctionName)
        }
        guard let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            throw KeyboardStageMetalError.missingFunction(fragmentFunctionName)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = pixelFormat

        switch blendMode {
        case .disabled:
            attachment?.isBlendingEnabled = false

        case .straightAlpha:
            attachment?.isBlendingEnabled = true
            attachment?.rgbBlendOperation = .add
            attachment?.alphaBlendOperation = .add
            attachment?.sourceRGBBlendFactor = .sourceAlpha
            attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment?.sourceAlphaBlendFactor = .one
            attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        case .premultipliedAlpha:
            attachment?.isBlendingEnabled = true
            attachment?.rgbBlendOperation = .add
            attachment?.alphaBlendOperation = .add
            attachment?.sourceRGBBlendFactor = .one
            attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment?.sourceAlphaBlendFactor = .one
            attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        let device = library.device
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
