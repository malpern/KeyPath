import AppIntents

struct KeyPathShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetCurrentLayerIntent(),
            phrases: [
                "What layer am I on in \(.applicationName)",
                "Get current layer in \(.applicationName)",
                "\(.applicationName) current layer",
            ],
            shortTitle: "Current Layer",
            systemImageName: "keyboard"
        )
        AppShortcut(
            intent: ServiceControlIntent(),
            phrases: [
                "\(\.$action) \(.applicationName)",
                "\(\.$action) \(.applicationName) service",
            ],
            shortTitle: "Control Service",
            systemImageName: "power"
        )
        AppShortcut(
            intent: SendActionIntent(),
            phrases: [
                "Send action to \(.applicationName)",
            ],
            shortTitle: "Send Action",
            systemImageName: "arrow.right.circle"
        )
    }
}
