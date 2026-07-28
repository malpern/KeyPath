@testable import KeyPathAppKit
import Metal
import XCTest

final class MetalShaderPackagingTests: XCTestCase {
    func testDefaultMetalLibraryIsPackagedWithKeyPathAppKit() {
        XCTAssertNotNil(
            KeyPathAppKitResources.bundle.url(
                forResource: "default",
                withExtension: "metallib"
            )
        )
    }

    func testPackagedLibraryBuildsTheKeyboardStagePipeline() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this test host.")
        }

        let library = try KeyboardStageMetalLibrary.loadLibrary(device: device)
        for functionName in KeyboardStageMetalLibrary.requiredFunctionNames {
            XCTAssertNotNil(
                library.makeFunction(name: functionName),
                "Missing packaged Metal function: \(functionName)"
            )
        }
        XCTAssertEqual(KeyboardStageMetalLibrary.intermediatePixelFormat, .rgba16Float)
        XCTAssertEqual(KeyboardStageMetalLibrary.drawablePixelFormat, .bgra8Unorm_srgb)
        XCTAssertNoThrow(try KeyboardStageMetalLibrary.makePipeline(device: device))
        XCTAssertNoThrow(try KeyboardStageMetalLibrary.makePipelines(device: device))
    }
}
