import SwiftUI

struct LayoutSaveSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var layoutID: String
    @State private var layoutName: String

    let title: String
    let confirmTitle: String
    let onConfirm: (String, String) -> Void

    init(title: String, confirmTitle: String, layoutID: String, layoutName: String, onConfirm: @escaping (String, String) -> Void) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        _layoutID = State(initialValue: layoutID)
        _layoutName = State(initialValue: layoutName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            LabeledContent("Layout ID") {
                TextField("Layout ID", text: $layoutID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .accessibilityIdentifier("layoutTracer.saveSheet.layoutID")
            }

            LabeledContent("Layout Name") {
                TextField("Layout Name", text: $layoutName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .accessibilityIdentifier("layoutTracer.saveSheet.layoutName")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .accessibilityIdentifier("layoutTracer.saveSheet.cancel")

                Button(confirmTitle) {
                    onConfirm(layoutID, layoutName)
                    dismiss()
                }
                .disabled(layoutID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || layoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("layoutTracer.saveSheet.confirm")
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
