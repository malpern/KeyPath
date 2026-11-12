import KeyPathCore
import Testing

@Suite("KanataRuntimeHost Isolated Core Tests")
struct KanataRuntimeHostCoreTests {
    @Test("Current host uses app-bundle-relative paths")
    func currentUsesBundleRelativePaths() {
        let host = KanataRuntimeHost.current(bundlePath: "/Applications/KeyPath.app")

        #expect(host.bridgeLibraryPath == "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        #expect(host.bundledCorePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
        #expect(host.kanataEngineBundlePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app")
    }

    @Test("Current host normalizes runtime resource directory to app bundle root")
    func currentNormalizesRuntimeResourceDirectory() {
        let host = KanataRuntimeHost.current(
            bundlePath: "/Applications/KeyPath.app/Contents/Library/KeyPath"
        )

        #expect(host.bridgeLibraryPath == "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        #expect(host.bundledCorePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
        #expect(host.kanataEngineBundlePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app")
    }
}
