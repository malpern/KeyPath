import SwiftUI

#if os(macOS)
    import AppKit

    struct MacSearchField: NSViewRepresentable {
        @Binding var text: String

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        func makeNSView(context: Context) -> NSSearchField {
            let searchField = NSSearchField()
            searchField.placeholderString = nil
            searchField.sendsSearchStringImmediately = true
            searchField.sendsWholeSearchString = false
            searchField.delegate = context.coordinator
            searchField.stringValue = text
            searchField.setAccessibilityIdentifier("rules-search-field")
            searchField.setAccessibilityLabel("Search rules")
            return searchField
        }

        func updateNSView(_ nsView: NSSearchField, context _: Context) {
            if nsView.stringValue != text {
                nsView.stringValue = text
            }
        }

        final class Coordinator: NSObject, NSSearchFieldDelegate {
            @Binding var text: String

            init(text: Binding<String>) {
                _text = text
            }

            func controlTextDidChange(_ obj: Notification) {
                guard let searchField = obj.object as? NSSearchField else { return }
                text = searchField.stringValue
            }
        }
    }
#endif
