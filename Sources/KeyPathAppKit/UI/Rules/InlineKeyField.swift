import KeyPathCore
import SwiftUI

// MARK: - Inline Key Field

struct InlineKeyField: View {
    let title: String
    @Binding var text: String
    let options: [String]
    let fieldWidth: CGFloat
    let textFieldIdentifier: String
    let menuIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                    .accessibilityIdentifier(textFieldIdentifier)

                Menu {
                    ForEach(options, id: \.self) { key in
                        Button(key) {
                            text = key
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier(menuIdentifier)
            }
        }
    }
}
