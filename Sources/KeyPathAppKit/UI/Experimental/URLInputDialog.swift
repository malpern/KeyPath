import AppKit
import KeyPathCore
import SwiftUI

// MARK: - URL Input Dialog

/// Dialog for entering a web URL to map to a key
struct URLInputDialog: View {
    @Binding var urlText: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter Web URL")
                .font(.headline)

            TextField("example.com or https://...", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { onSubmit() }
                .accessibilityIdentifier("mapper-url-input-field")
                .accessibilityLabel("URL input")

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("mapper-dialog-cancel-button")
                .accessibilityLabel("Cancel")

                Button("OK") {
                    onSubmit()
                }
                .keyboardShortcut(.return)
                .accessibilityIdentifier("mapper-dialog-ok-button")
                .accessibilityLabel("OK")
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
