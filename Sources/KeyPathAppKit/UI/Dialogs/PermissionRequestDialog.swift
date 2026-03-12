import AppKit
import SwiftUI

enum PermissionRequestDialog {
    @MainActor
    static func show(
        title: String = "Permission Required",
        explanation: String,
        permissions _: Set<PGPermissionType>,
        approveButtonTitle: String = "Allow",
        cancelButtonTitle: String = "Cancel"
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = explanation
                alert.alertStyle = .informational
                alert.addButton(withTitle: approveButtonTitle)
                alert.addButton(withTitle: cancelButtonTitle)
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
