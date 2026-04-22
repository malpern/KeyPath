import AppKit
import SwiftUI

struct LabelComboBoxField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    let accessibilityID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, suggestions: suggestions)
    }

    func makeNSView(context: Context) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .preferredFont(forTextStyle: .body)

        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 12
        comboBox.delegate = context.coordinator
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.selectionChanged(_:))
        comboBox.setAccessibilityIdentifier(accessibilityID)
        comboBox.addItems(withObjectValues: suggestions)

        context.coordinator.comboBox = comboBox
        context.coordinator.applyDisplayedText()

        let stack = NSStackView(views: [label, comboBox])
        stack.orientation = .vertical
        stack.spacing = 6
        return stack
    }

    func updateNSView(_ nsView: NSStackView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.suggestions = suggestions
        if let comboBox = context.coordinator.comboBox {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: suggestions)
            context.coordinator.applyDisplayedText()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var text: Binding<String>
        var suggestions: [String]
        weak var comboBox: NSComboBox?

        init(text: Binding<String>, suggestions: [String]) {
            self.text = text
            self.suggestions = suggestions
        }

        func applyDisplayedText() {
            guard let comboBox, comboBox.stringValue != text.wrappedValue else { return }
            comboBox.stringValue = text.wrappedValue
        }

        @objc
        func selectionChanged(_ sender: NSComboBox) {
            text.wrappedValue = sender.stringValue
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSComboBox else { return }
            text.wrappedValue = field.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            text.wrappedValue = comboBox.stringValue
        }
    }
}

struct KeyCodeComboBoxField: NSViewRepresentable {
    let title: String
    @Binding var value: UInt16
    let suggestions: [KeyCodeSuggestion]
    let accessibilityID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, suggestions: suggestions)
    }

    func makeNSView(context: Context) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .preferredFont(forTextStyle: .body)

        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 14
        comboBox.delegate = context.coordinator
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.selectionChanged(_:))
        comboBox.setAccessibilityIdentifier(accessibilityID)
        comboBox.addItems(withObjectValues: suggestions.map(\.displayText))

        context.coordinator.comboBox = comboBox
        context.coordinator.applyDisplayedText()

        let stack = NSStackView(views: [label, comboBox])
        stack.orientation = .vertical
        stack.spacing = 6
        return stack
    }

    func updateNSView(_ nsView: NSStackView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.suggestions = suggestions
        if let comboBox = context.coordinator.comboBox {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: suggestions.map(\.displayText))
            context.coordinator.applyDisplayedText()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var value: Binding<UInt16>
        var suggestions: [KeyCodeSuggestion]
        weak var comboBox: NSComboBox?

        init(value: Binding<UInt16>, suggestions: [KeyCodeSuggestion]) {
            self.value = value
            self.suggestions = suggestions
        }

        func applyDisplayedText() {
            guard let comboBox,
                  let suggestion = suggestions.first(where: { $0.keyCode == value.wrappedValue })
            else { return }
            if comboBox.stringValue != suggestion.displayText {
                comboBox.stringValue = suggestion.displayText
            }
        }

        @objc
        func selectionChanged(_ sender: NSComboBox) {
            resolve(string: sender.stringValue)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSComboBox else { return }
            resolve(string: field.stringValue)
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            resolve(string: comboBox.stringValue)
        }

        private func resolve(string: String) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let numericPrefix = UInt16(trimmed.split(separator: " ").first ?? "") {
                value.wrappedValue = numericPrefix
            } else if let match = suggestions.first(where: { suggestion in
                suggestion.searchTokens.contains { $0.localizedCaseInsensitiveContains(trimmed) } ||
                suggestion.displayText.localizedCaseInsensitiveContains(trimmed)
            }) {
                value.wrappedValue = match.keyCode
            }
            applyDisplayedText()
        }
    }
}
