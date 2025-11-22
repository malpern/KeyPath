import AppKit
import SwiftUI

enum PermissionRequestDialog {
    @MainActor
    static func show(
        explanation: String,
        permissions _: Set<PGPermissionType>
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Permission Required"
                alert.informativeText = explanation
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Allow")
                alert.addButton(withTitle: "Cancel")
                if let window = NSApplication.shared.keyWindow {
                    alert.beginSheetModal(for: window) { resp in
                        continuation.resume(returning: resp == .alertFirstButtonReturn)
                    }
                } else {
                    let resp = alert.runModal()
                    continuation.resume(returning: resp == .alertFirstButtonReturn)
                }
            }
        }
    }
}
