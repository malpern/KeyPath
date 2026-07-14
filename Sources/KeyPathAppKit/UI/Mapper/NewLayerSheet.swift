import AppKit
import KeyPathCore
import SwiftUI

// MARK: - New Layer Sheet

/// Sheet for creating a new layer
struct NewLayerSheet: View {
    @Binding var layerName: String
    let existingLayers: [String]
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private var isValidName: Bool {
        let sanitized = layerName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        return !sanitized.isEmpty && !existingLayers.contains { $0.lowercased() == sanitized }
    }

    private var validationMessage: String? {
        guard !layerName.isEmpty else { return nil }

        let sanitized = layerName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        if sanitized.isEmpty {
            return "Name must contain letters or numbers"
        }

        if existingLayers.contains(where: { $0.lowercased() == sanitized }) {
            return "A layer with this name already exists"
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Layer")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Layer name", text: $layerName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit {
                        if isValidName {
                            onSubmit(layerName)
                        }
                    }
                    .accessibilityIdentifier("new-layer-name-field")

                if let message = validationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("new-layer-cancel-button")

                Button("Create") {
                    onSubmit(layerName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidName)
                .accessibilityIdentifier("new-layer-create-button")
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            isNameFocused = true
        }
    }
}
