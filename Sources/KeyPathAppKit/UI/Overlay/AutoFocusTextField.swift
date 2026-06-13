import AppKit
import SwiftUI

/// A borderless text field that grabs first-responder focus as soon as it is
/// placed in a window. Used inside the hoisted output-type picker popover where
/// SwiftUI's `@FocusState` does not bridge across the window-anchored host, so
/// programmatic focus there is unreliable. This drops to AppKit and calls
/// `makeFirstResponder` directly, which works regardless of view-tree hoisting.
///
/// Focus is grabbed once (guarded by the coordinator) so a re-render does not
/// keep stealing focus back from the user.
struct AutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var autoFocus: Bool = true

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        guard autoFocus, !context.coordinator.didFocus else { return }
        // Defer until the field is actually in a window and the responder chain
        // has settled (the popover slides in), then make it first responder.
        DispatchQueue.main.async {
            guard let window = nsView.window, !context.coordinator.didFocus else { return }
            context.coordinator.didFocus = true
            window.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>
        var didFocus = false

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
