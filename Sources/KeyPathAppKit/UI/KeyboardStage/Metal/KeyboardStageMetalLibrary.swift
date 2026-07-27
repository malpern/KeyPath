import Foundation
import Metal

enum KeyboardStageMetalError: LocalizedError, Equatable, Sendable {
    case noDevice
    case missingFunction(String)
    case commandQueueUnavailable
    case bufferUnavailable
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

enum KeyboardStageMetalLibrary {
    static let vertexFunctionName = "keypath_keyboard_stage_vertex"
    static let fragmentFunctionName = "keypath_keyboard_stage_fragment"
    static let colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb

    static let isAvailable: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        do {
            let library = try loadLibrary(device: device)
            return library.makeFunction(name: vertexFunctionName) != nil
                && library.makeFunction(name: fragmentFunctionName) != nil
        } catch {
            return false
        }
    }()

    static func loadLibrary(device: any MTLDevice) throws -> any MTLLibrary {
        try device.makeDefaultLibrary(bundle: KeyPathAppKitResources.bundle)
    }

    static func makePipeline(device: any MTLDevice) throws -> any MTLRenderPipelineState {
        let library = try loadLibrary(device: device)
        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            throw KeyboardStageMetalError.missingFunction(vertexFunctionName)
        }
        guard let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            throw KeyboardStageMetalError.missingFunction(fragmentFunctionName)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "KeyPath keyboard stage"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
