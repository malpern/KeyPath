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
        XCTAssertNotNil(
            library.makeFunction(name: KeyboardStageMetalLibrary.vertexFunctionName)
        )
        XCTAssertNotNil(
            library.makeFunction(name: KeyboardStageMetalLibrary.fragmentFunctionName)
        )
        XCTAssertNoThrow(try KeyboardStageMetalLibrary.makePipeline(device: device))
    }
}
