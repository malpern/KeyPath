import SwiftUI

#if os(macOS)
    import AppKit

    struct AccessibleIntegerField: NSViewRepresentable {
        let placeholder: String
        @Binding var value: Int
        var range: ClosedRange<Int>?
        let accessibilityIdentifier: String
        let accessibilityLabel: String
        var accessibilityValueSuffix: String = " ms"
        var onValueChanged: (Int) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeNSView(context: Context) -> NSTextField {
            let field = AccessibilitySettableIntegerTextField()
            field.placeholderString = placeholder
            field.isEditable = true
            field.isSelectable = true
            field.alignment = .right
            field.formatter = nil
            field.bezelStyle = .roundedBezel
            field.controlSize = .small
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            field.target = context.coordinator
            field.action = #selector(Coordinator.commitFromField(_:))
            field.delegate = context.coordinator
            field.setAccessibilityIdentifier(accessibilityIdentifier)
            field.setAccessibilityLabel(accessibilityLabel)
            field.onAccessibilityValueChanged = { [weak coordinator = context.coordinator] rawValue in
                coordinator?.commit(rawValue: rawValue)
            }
            return field
        }

        func updateNSView(_ field: NSTextField, context: Context) {
            context.coordinator.parent = self
            let text = "\(value)"
            if field.stringValue != text, field.currentEditor() == nil {
                field.stringValue = text
            }
            field.placeholderString = placeholder
            field.setAccessibilityIdentifier(accessibilityIdentifier)
            field.setAccessibilityLabel(accessibilityLabel)
            if let field = field as? AccessibilitySettableIntegerTextField {
                field.onAccessibilityValueChanged = { [weak coordinator = context.coordinator] rawValue in
                    coordinator?.commit(rawValue: rawValue)
                }
                field.setDisplayedAccessibilityValue("\(value)\(accessibilityValueSuffix)")
            } else {
                field.setAccessibilityValue("\(value)\(accessibilityValueSuffix)")
            }
        }

        @MainActor
        final class Coordinator: NSObject, NSTextFieldDelegate {
            var parent: AccessibleIntegerField

            init(parent: AccessibleIntegerField) {
                self.parent = parent
            }

            @objc func commitFromField(_ sender: NSTextField) {
                commit(rawValue: sender.stringValue)
            }

            func controlTextDidEndEditing(_ notification: Notification) {
                guard let field = notification.object as? NSTextField else { return }
                commit(rawValue: field.stringValue)
            }

            func commit(rawValue: String) {
                guard let parsed = Self.parse(rawValue) else { return }
                let nextValue = parent.range.map { min(max(parsed, $0.lowerBound), $0.upperBound) } ?? parsed
                parent.value = nextValue
                parent.onValueChanged(nextValue)
            }

            private static func parse(_ rawValue: String) -> Int? {
                let trimmed = rawValue
                    .replacingOccurrences(of: "ms", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(trimmed)
            }
        }
    }

    final class AccessibilitySettableIntegerTextField: NSTextField {
        var onAccessibilityValueChanged: ((String) -> Void)?

        func setDisplayedAccessibilityValue(_ accessibilityValue: String) {
            super.setAccessibilityValue(accessibilityValue)
        }

        override func setAccessibilityValue(_ accessibilityValue: Any?) {
            if let rawValue = accessibilityValue.map(String.init(describing:)) {
                stringValue = rawValue
                onAccessibilityValueChanged?(rawValue)
            }
            super.setAccessibilityValue(accessibilityValue)
        }
    }
#endif
