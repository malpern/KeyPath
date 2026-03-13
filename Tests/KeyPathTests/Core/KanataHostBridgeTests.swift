@testable import KeyPathCore
import XCTest

final class KanataHostBridgeTests: XCTestCase {
    func testProbeReturnsUnavailableWhenLibraryMissing() {
        let runtimeHost = KanataRuntimeHost(
            launcherPath: "/tmp/kanata-launcher",
            bridgeLibraryPath: "/definitely/missing/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "/tmp/kanata",
            kanataEngineBundlePath: "/tmp/Kanata Engine.app"
        )

        XCTAssertEqual(
            KanataHostBridge.probe(runtimeHost: runtimeHost),
            .unavailable(reason: "library not found at /definitely/missing/libkeypath_kanata_host_bridge.dylib")
        )
    }

    func testLoadedLogSummaryFormatsExpectedFields() {
        XCTAssertEqual(
            KanataHostBridgeProbeResult.loaded(version: "0.1.0", defaultConfigCount: 2).logSummary,
            "Host bridge loaded: version=0.1.0 default_cfg_count=2"
        )
    }

    func testRunResultLogSummaryFormatsFailure() {
        XCTAssertEqual(
            KanataHostBridgeRunResult.failed(reason: "permission denied").logSummary,
            "Host bridge runtime failed: permission denied"
        )
    }

    func testRunResultLogSummaryFormatsUnavailable() {
        XCTAssertEqual(
            KanataHostBridgeRunResult.unavailable(reason: "missing symbol").logSummary,
            "Host bridge runtime unavailable: missing symbol"
        )
    }

    func testCreatePassthruRuntimeReturnsUnavailableWhenLibraryMissing() {
        let runtimeHost = KanataRuntimeHost(
            launcherPath: "/tmp/kanata-launcher",
            bridgeLibraryPath: "/definitely/missing/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "/tmp/kanata",
            kanataEngineBundlePath: "/tmp/Kanata Engine.app"
        )

        let result = KanataHostBridge.createPassthruRuntime(
            runtimeHost: runtimeHost,
            configPath: "/tmp/keypath.kbd",
            tcpPort: 37_001
        )

        XCTAssertEqual(
            result.result,
            .unavailable(reason: "library not found at /definitely/missing/libkeypath_kanata_host_bridge.dylib")
        )
        XCTAssertNil(result.handle)
    }

    func testPassthruRuntimeResultLogSummaryFormatsCreated() {
        XCTAssertEqual(
            KanataHostBridgePassthruRuntimeResult.created(layerCount: 3).logSummary,
            "Host bridge passthru runtime created successfully: layer_count=3"
        )
    }
}
