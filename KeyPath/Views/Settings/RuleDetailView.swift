import SwiftUI

struct RuleDetailView: View {
    @State var rule: MockRule
    let onBack: () -> Void
    let onUpdate: (MockRule) -> Void
    @State private var isEditingName = false
    @State private var editedName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Rule name (editable)
                if isEditingName {
                    TextField("Rule name", text: $editedName, onCommit: {
                        rule.name = editedName
                        isEditingName = false
                        onUpdate(rule)
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.title2)
                    .fontWeight(.semibold)
                } else {
                    Button(action: {
                        editedName = rule.name
                        isEditingName = true
                    }) {
                        Text(rule.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Large visualization with demo button
                    VStack(spacing: 16) {
                        EnhancedRemapVisualizer(behavior: rule.behavior)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColor.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(rule.explanation)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    // Kanata code with syntax highlighting
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kanata Configuration")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(rule.kanataCode)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}