import SwiftUI

public struct LayoutTracerApp: App {
    @StateObject private var menuState = LayoutTracerMenuState.shared

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.applicationIconImage = LayoutTracerAppIcon.makeIcon()
    }

    public var body: some Scene {
        WindowGroup("KeyPath Layout Tracer") {
            LayoutTracerRootView()
                .frame(minWidth: 1100, minHeight: 760)
        }
        .commands {
            LayoutTracerMenuCommands(menuState: menuState)
        }
    }
}
