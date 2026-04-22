import SwiftUI

struct LabeledDoubleField: View {
    let title: String
    @Binding var value: Double
    let accessibilityID: String

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .accessibilityIdentifier(accessibilityID)
        }
    }
}
