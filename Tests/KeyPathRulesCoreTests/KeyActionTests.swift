import Foundation
@testable import KeyPathRulesCore
import Testing

@Suite("KeyAction")
struct KeyActionTests {
    // MARK: - kanataOutput

    @Suite("kanataOutput")
    struct KanataOutputTests {
        @Test("keystroke returns the key directly")
        func keystroke() {
            #expect(KeyAction.keystroke(key: "esc").kanataOutput == "esc")
            #expect(KeyAction.keystroke(key: "a").kanataOutput == "a")
            #expect(KeyAction.keystroke(key: "M-c").kanataOutput == "M-c")
            #expect(KeyAction.keystroke(key: "lctl").kanataOutput == "lctl")
        }

        @Test("launchApp produces push-msg with bundleId when available")
        func launchAppWithBundleId() {
            let action = KeyAction.launchApp(name: "Safari", bundleId: "com.apple.Safari")
            #expect(action.kanataOutput == "(push-msg \"launch:com.apple.Safari\")")
        }

        @Test("launchApp falls back to name when bundleId is nil")
        func launchAppWithoutBundleId() {
            let action = KeyAction.launchApp(name: "Firefox", bundleId: nil)
            #expect(action.kanataOutput == "(push-msg \"launch:Firefox\")")
        }

        @Test("launchApp falls back to name when bundleId is empty")
        func launchAppWithEmptyBundleId() {
            let action = KeyAction.launchApp(name: "Chrome", bundleId: "")
            #expect(action.kanataOutput == "(push-msg \"launch:Chrome\")")
        }

        @Test("openURL produces push-msg with encoded URL")
        func openURL() {
            let action = KeyAction.openURL("https://example.com/path?q=1")
            let encoded = URLMappingFormatter.encodeForPushMessage("https://example.com/path?q=1")
            #expect(action.kanataOutput == "(push-msg \"open:\(encoded)\")")
        }

        @Test("openFolder produces push-msg with path")
        func openFolder() {
            let action = KeyAction.openFolder(path: "/Users/me/Documents", name: "Docs")
            #expect(action.kanataOutput == "(push-msg \"folder:/Users/me/Documents\")")
        }

        @Test("runScript produces push-msg with path")
        func runScript() {
            let action = KeyAction.runScript(path: "/usr/local/bin/myscript.sh", name: "My Script")
            #expect(action.kanataOutput == "(push-msg \"script:/usr/local/bin/myscript.sh\")")
        }

        @Test("systemAction produces push-msg with id")
        func systemAction() {
            #expect(KeyAction.systemAction(id: "mission-control").kanataOutput == "(push-msg \"system:mission-control\")")
            #expect(KeyAction.systemAction(id: "spotlight").kanataOutput == "(push-msg \"system:spotlight\")")
        }

        @Test("hyper produces multi modifier expression")
        func hyper() {
            #expect(KeyAction.hyper.kanataOutput == "(multi lctl lmet lalt lsft)")
        }

        @Test("meh produces multi modifier expression without Cmd")
        func meh() {
            #expect(KeyAction.meh.kanataOutput == "(multi lctl lalt lsft)")
        }

        @Test("notify produces push-msg with parameters")
        func notify() {
            let withBody = KeyAction.notify(title: "Done", body: "Build complete", sound: true)
            #expect(withBody.kanataOutput == "(push-msg \"notify?title=Done&body=Build complete&sound=1\")")

            let noBody = KeyAction.notify(title: "Done", body: nil, sound: false)
            #expect(noBody.kanataOutput == "(push-msg \"notify?title=Done\")")
        }

        @Test("windowAction produces push-msg with position")
        func windowAction() {
            #expect(KeyAction.windowAction(position: "left").kanataOutput == "(push-msg \"window:left\")")
            #expect(KeyAction.windowAction(position: "maximize").kanataOutput == "(push-msg \"window:maximize\")")
        }

        @Test("fakeKey produces on-press-fakekey expression")
        func fakeKey() {
            #expect(KeyAction.fakeKey(name: "vk-nav", action: .tap).kanataOutput == "(on-press-fakekey vk-nav tap)")
            #expect(KeyAction.fakeKey(name: "vk-toggle", action: .toggle).kanataOutput == "(on-press-fakekey vk-toggle toggle)")
        }

        @Test("activateLayer produces layer-switch expression")
        func activateLayer() {
            #expect(KeyAction.activateLayer(name: "nav").kanataOutput == "(layer-switch nav)")
            #expect(KeyAction.activateLayer(name: "vim-normal").kanataOutput == "(layer-switch vim-normal)")
        }

        @Test("rawKanata passes through expression unchanged")
        func rawKanata() {
            #expect(KeyAction.rawKanata("(multi lctl lsft)").kanataOutput == "(multi lctl lsft)")
            #expect(KeyAction.rawKanata("_").kanataOutput == "_")
            #expect(KeyAction.rawKanata("(layer-while-held nav)").kanataOutput == "(layer-while-held nav)")
        }
    }

    // MARK: - displayName

    @Suite("displayName")
    struct DisplayNameTests {
        @Test("keystroke shows the key")
        func keystroke() {
            #expect(KeyAction.keystroke(key: "esc").displayName == "esc")
            #expect(KeyAction.keystroke(key: "a").displayName == "a")
        }

        @Test("launchApp shows the app name")
        func launchApp() {
            #expect(KeyAction.launchApp(name: "Safari", bundleId: "com.apple.Safari").displayName == "Safari")
        }

        @Test("openURL shows the domain")
        func openURL() {
            let action = KeyAction.openURL("https://github.com/malpern/KeyPath")
            #expect(action.displayName == "github.com")
        }

        @Test("openFolder shows name when provided")
        func openFolderWithName() {
            #expect(KeyAction.openFolder(path: "/Users/me/Documents", name: "Docs").displayName == "Docs")
        }

        @Test("openFolder shows Folder when name is nil")
        func openFolderWithoutName() {
            #expect(KeyAction.openFolder(path: "/Users/me/Documents", name: nil).displayName == "Folder")
        }

        @Test("runScript shows name when provided")
        func runScriptWithName() {
            #expect(KeyAction.runScript(path: "/bin/foo.sh", name: "Foo").displayName == "Foo")
        }

        @Test("runScript derives name from path when name is nil")
        func runScriptWithoutName() {
            #expect(KeyAction.runScript(path: "/usr/local/bin/deploy.sh", name: nil).displayName == "deploy")
        }

        @Test("hyper shows Hyper")
        func hyper() {
            #expect(KeyAction.hyper.displayName == "Hyper")
        }

        @Test("meh shows Meh")
        func meh() {
            #expect(KeyAction.meh.displayName == "Meh")
        }

        @Test("systemAction shows the id")
        func systemAction() {
            #expect(KeyAction.systemAction(id: "mission-control").displayName == "mission-control")
        }

        @Test("notify shows the title")
        func notify() {
            #expect(KeyAction.notify(title: "Build Done", body: nil, sound: false).displayName == "Build Done")
        }

        @Test("windowAction shows the position")
        func windowAction() {
            #expect(KeyAction.windowAction(position: "maximize").displayName == "maximize")
        }

        @Test("fakeKey shows the key name")
        func fakeKey() {
            #expect(KeyAction.fakeKey(name: "vk-nav", action: .tap).displayName == "vk-nav")
        }

        @Test("activateLayer shows the layer name")
        func activateLayer() {
            #expect(KeyAction.activateLayer(name: "nav").displayName == "nav")
        }

        @Test("rawKanata shows the expression")
        func rawKanata() {
            #expect(KeyAction.rawKanata("(multi lctl lsft)").displayName == "(multi lctl lsft)")
        }
    }

    // MARK: - outputString backward compat

    @Suite("outputString")
    struct OutputStringTests {
        @Test("keystroke returns the key")
        func keystroke() {
            #expect(KeyAction.keystroke(key: "a").outputString == "a")
        }

        @Test("non-keystroke returns kanataOutput")
        func nonKeystroke() {
            let action = KeyAction.systemAction(id: "spotlight")
            #expect(action.outputString == action.kanataOutput)
        }
    }
}
