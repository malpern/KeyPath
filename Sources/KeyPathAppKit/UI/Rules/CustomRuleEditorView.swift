import KeyPathCore
import SwiftUI

struct CustomRuleEditorView: View {
  enum Mode {
    case create
    case edit
  }

  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var input: String
  @State private var output: String
  @State private var notes: String
  @State private var isEnabled: Bool
  private let existingRule: CustomRule?
  private let mode: Mode
  let onSave: (CustomRule) -> Void

  init(rule: CustomRule?, onSave: @escaping (CustomRule) -> Void) {
    existingRule = rule
    self.onSave = onSave
    if let rule {
      _title = State(initialValue: rule.title)
      _input = State(initialValue: rule.input)
      _output = State(initialValue: rule.output)
      _notes = State(initialValue: rule.notes ?? "")
      _isEnabled = State(initialValue: rule.isEnabled)
      mode = .edit
    } else {
      _title = State(initialValue: "")
      _input = State(initialValue: "")
      _output = State(initialValue: "")
      _notes = State(initialValue: "")
      _isEnabled = State(initialValue: true)
      mode = .create
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(mode == .create ? "New Custom Rule" : "Edit Custom Rule")
        .font(.title2.bold())

      VStack(alignment: .leading, spacing: 10) {
        TextField("Friendly name (optional)", text: $title)
        TextField("Input key (e.g. caps_lock)", text: $input)
        TextField("Output key or sequence", text: $output)
        Toggle("Enabled", isOn: $isEnabled)
        VStack(alignment: .leading, spacing: 4) {
          Text("Notes (optional)")
            .font(.caption)
            .foregroundColor(.secondary)
          TextEditor(text: $notes)
            .frame(height: 70)
            .font(.body)
            .padding(6)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2))
            )
        }
      }
      .textFieldStyle(.roundedBorder)

      Spacer()

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button(mode == .create ? "Add Rule" : "Save Changes") {
          let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
          let rule = CustomRule(
            id: existingRule?.id ?? UUID(),
            title: title,
            input: input.trimmingCharacters(in: .whitespacesAndNewlines),
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            createdAt: existingRule?.createdAt ?? Date()
          )
          onSave(rule)
          dismiss()
        }
        .disabled(
          input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(minWidth: 400, minHeight: 320)
  }
}
