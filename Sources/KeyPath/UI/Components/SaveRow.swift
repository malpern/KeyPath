import SwiftUI

struct SaveRow: View {
    let isActive: Bool
    let label: String
    let isDisabled: Bool
    let onSave: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onSave) {
                HStack {
                    if isActive {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    }
                    Text(label)
                }
                .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
            .accessibilityIdentifier("save-mapping-button")
            .accessibilityLabel(label.isEmpty ? "Save key mapping" : label)
            .accessibilityHint("Save the input and output key mapping to your configuration")
        }
    }
}

