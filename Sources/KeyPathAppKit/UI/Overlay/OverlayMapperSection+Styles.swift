import SwiftUI

// MARK: - Layer Picker Item Button Style

/// Custom button style for layer picker items with hover effect
struct LayerPickerItemButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : (configuration.isPressed ? 0.15 : 0)))
            )
            .animation(.easeInOut(duration: 0.1), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Shared Popover List Styling

/// Standard row divider used in picker-style popovers.
struct PopoverListDivider: View {
    var body: some View {
        Divider()
            .opacity(0.2)
            .padding(.horizontal, 8)
    }
}

extension View {
    /// Shared material/border chrome for picker-style popovers.
    func pickerPopoverChrome(cornerRadius: CGFloat = 8, outerPadding: CGFloat = 0) -> some View {
        background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .padding(outerPadding)
    }

    /// Drop-in replacement for `.popover()` that renders content as an inline overlay
    /// instead of using NSPopover. Avoids a crash on borderless overlay windows where
    /// NSPopover's animated resize triggers a null function pointer callback.
    func inlinePopover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay(alignment: .top) {
            if isPresented.wrappedValue {
                ZStack {
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented.wrappedValue = false }

                    content()
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
                .animation(.easeOut(duration: 0.15), value: isPresented.wrappedValue)
            }
        }
    }
}
