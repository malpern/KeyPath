import Foundation

/// Bridges internal layer-change notifications to macOS Distributed Notifications,
/// enabling external tools (Hammerspoon, Keyboard Maestro, Shortcuts) to react
/// to KeyPath state changes.
@MainActor
enum DistributedNotificationBridge {
    static let layerChangedName = NSNotification.Name("com.keypath.layerChanged")
    static let serviceStateChangedName = NSNotification.Name("com.keypath.serviceStateChanged")

    private static var previousLayer: String = "base"
    private static var observer: NSObjectProtocol?

    static func start() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(
            forName: .kanataLayerChanged,
            object: nil,
            queue: .main
        ) { notification in
            guard let layerName = notification.userInfo?["layerName"] as? String else { return }
            guard layerName.lowercased() != previousLayer.lowercased() else { return }

            let previous = previousLayer
            previousLayer = layerName

            DistributedNotificationCenter.default().postNotificationName(
                layerChangedName,
                object: "com.keypath.app",
                userInfo: [
                    "layer": layerName,
                    "previous": previous,
                ],
                deliverImmediately: true
            )
        }
    }

    static func postServiceState(_ state: String) {
        DistributedNotificationCenter.default().postNotificationName(
            serviceStateChangedName,
            object: "com.keypath.app",
            userInfo: ["state": state],
            deliverImmediately: true
        )
    }

    static func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}
