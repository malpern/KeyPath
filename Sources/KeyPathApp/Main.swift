import AppKit
import Foundation
import KeyPathAppKit
import SwiftUI

@main
struct KeyPath {
    @MainActor
    static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--session-runtime") || arguments.contains("--session-capabilities") {
            // NSWorkspace waits for actual AppKit launch completion. This worker
            // bypasses SwiftUI, so complete launch before starting its run loop.
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            application.finishLaunching()
            Task { await SessionRuntimeWorker.runIfRequested() }
            RunLoop.main.run()
            return
        }
        // Ordinary SwiftUI startup stays synchronous. Yielding before installing
        // its delegate can miss AppKit's finish-launching notification.
        KeyPathApp.main()
    }
}
