import KeyPathCore
import Testing

@Suite("KanataRuntimeHost Isolated Core Tests")
struct KanataRuntimeHostCoreTests {
    @Test("Current host uses app-bundle-relative paths")
    func currentUsesBundleRelativePaths() {
        let host = KanataRuntimeHost.current(bundlePath: "/Applications/KeyPath.app")

        #expect(host.launcherPath == "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher")
        #expect(host.bridgeLibraryPath == "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        #expect(host.bundledCorePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
        #expect(host.kanataEngineBundlePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app")
    }

    @Test("Current host normalizes launcher directory to app bundle root")
    func currentNormalizesLauncherDirectory() {
        let host = KanataRuntimeHost.current(
            bundlePath: "/Applications/KeyPath.app/Contents/Library/KeyPath"
        )

        #expect(host.launcherPath == "/Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher")
        #expect(host.bridgeLibraryPath == "/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib")
        #expect(host.bundledCorePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
        #expect(host.kanataEngineBundlePath == "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app")
    }

    @Test("Launch request builds command line and adds trace when needed")
    func launchRequestBuildsCommandLine() {
        let request = KanataRuntimeLaunchRequest(
            configPath: "/Users/test/.config/keypath/keypath.kbd",
            inheritedArguments: ["--port", "37001", "--log-layer-changes"],
            addTraceLogging: true
        )

        #expect(
            request.commandLine(binaryPath: "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
                == [
                    "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata",
                    "--cfg", "/Users/test/.config/keypath/keypath.kbd",
                    "--port", "37001",
                    "--log-layer-changes",
                    "--trace"
                ]
        )
    }

    @Test("Launch request does not duplicate trace when debug already exists")
    func launchRequestDoesNotDuplicateTraceWhenDebugExists() {
        let request = KanataRuntimeLaunchRequest(
            configPath: "/Users/test/.config/keypath/keypath.kbd",
            inheritedArguments: ["--debug"],
            addTraceLogging: true
        )

        #expect(
            request.commandLine(binaryPath: "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata")
                == [
                    "/Applications/KeyPath.app/Contents/Library/KeyPath/Kanata Engine.app/Contents/MacOS/kanata",
                    "--cfg", "/Users/test/.config/keypath/keypath.kbd",
                    "--debug"
                ]
        )
    }
}
