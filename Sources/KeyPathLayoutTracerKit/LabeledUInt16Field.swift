import SwiftUI

struct LabeledUInt16Field: View {
    let title: String
    @Binding var value: UInt16
    let accessibilityID: String

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .accessibilityIdentifier(accessibilityID)
        }
    }
}
