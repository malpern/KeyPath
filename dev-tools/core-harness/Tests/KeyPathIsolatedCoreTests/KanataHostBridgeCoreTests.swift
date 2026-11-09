import KeyPathCore
import Testing

@Suite("KanataHostBridge Isolated Core Tests")
struct KanataHostBridgeCoreTests {
    @Test("Probe reports unavailable when bridge library is missing")
    func probeReportsUnavailableWhenLibraryMissing() {
        let runtimeHost = KanataRuntimeHost(
            launcherPath: "/tmp/kanata-launcher",
            bridgeLibraryPath: "/definitely/missing/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "/tmp/kanata",
            kanataEngineBundlePath: "/tmp/Kanata Engine.app"
        )

        #expect(
            KanataHostBridge.probe(runtimeHost: runtimeHost)
                == .unavailable(reason: "library not found at /definitely/missing/libkeypath_kanata_host_bridge.dylib")
        )
    }

    @Test("Bridge result summaries are stable")
    func resultSummariesAreStable() {
        #expect(
            KanataHostBridgeProbeResult.loaded(version: "0.1.0", defaultConfigCount: 2).logSummary
                == "Host bridge loaded: version=0.1.0 default_cfg_count=2"
        )
        #expect(
            KanataHostBridgePassthruRuntimeResult.created(layerCount: 3).logSummary
                == "Host bridge passthru runtime created successfully: layer_count=3"
        )
    }

    @Test("Passthru runtime creation reports unavailable when bridge library is missing")
    func passthruRuntimeReportsUnavailableWhenLibraryMissing() {
        let runtimeHost = KanataRuntimeHost(
            launcherPath: "/tmp/kanata-launcher",
            bridgeLibraryPath: "/definitely/missing/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "/tmp/kanata",
            kanataEngineBundlePath: "/tmp/Kanata Engine.app"
        )

        let result = KanataHostBridge.createPassthruRuntime(
            runtimeHost: runtimeHost,
            configPath: "/tmp/keypath.kbd",
            tcpPort: 37001
        )

        #expect(
            result.result
                == .unavailable(reason: "library not found at /definitely/missing/libkeypath_kanata_host_bridge.dylib")
        )
        #expect(result.handle == nil)
    }
}
