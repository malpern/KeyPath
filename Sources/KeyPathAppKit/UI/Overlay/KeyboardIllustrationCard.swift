import KeyPathCore
import SwiftUI

/// Individual keyboard illustration card with image and label
struct KeyboardIllustrationCard: View {
    let layout: PhysicalLayout
    let isSelected: Bool
    let isDark: Bool
    let isCustom: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    let onRefreshKeymap: (() -> Void)?

    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    /// Image size - fairly big as requested
    private let imageHeight: CGFloat = 120

    init(
        layout: PhysicalLayout,
        isSelected: Bool,
        isDark: Bool,
        isCustom: Bool = false,
        onSelect: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onRefreshKeymap: (() -> Void)? = nil
    ) {
        self.layout = layout
        self.isSelected = isSelected
        self.isDark = isDark
        self.isCustom = isCustom
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onRefreshKeymap = onRefreshKeymap
    }

    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = NSHapticFeedbackManager.defaultPerformer
            generator.perform(.alignment, performanceTime: .default)

            onSelect()
        }) {
            VStack(spacing: 8) {
                // Keyboard illustration - fixed height, horizontally centered
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardBackground)
                        .shadow(
                            color: shadowColor,
                            radius: shadowRadius,
                            x: 0,
                            y: shadowY
                        )

                    // Selection ring overlay
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    }

                    keyboardImage
                        .frame(maxHeight: imageHeight)
                        .padding(12)
                }
                .frame(height: imageHeight + 24)

                // Label - centered below image, supports multi-line for long names
                Text(layout.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-keyboard-layout-button-\(layout.id)")
        .accessibilityLabel("Select keyboard layout \(layout.name)")
        .onHover { hovering in
            // Animate only hover state, not scale - avoids layout shifts
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        // No scale "pop" animation on selection - keeps drawer stable
        // Selection ring and shadow changes provide sufficient visual feedback
        .contextMenu {
            if isCustom {
                if onRefreshKeymap != nil {
                    Button {
                        onRefreshKeymap?()
                    } label: {
                        Label("Refresh Keymap", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("refresh-keymap-button")
                }

                if onDelete != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Layout", systemImage: "trash")
                    }
                    .accessibilityIdentifier("delete-custom-layout-button")
                }
            }
        }
        .confirmationDialog(
            "Delete Layout",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
            .accessibilityIdentifier("overlay-keyboard-layout-delete-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("overlay-keyboard-layout-delete-cancel")
        } message: {
            Text("Are you sure you want to delete \"\(layout.name)\"? This action cannot be undone.")
        }
    }

    // MARK: - Computed Animation Properties

    private var shadowColor: Color {
        if isSelected {
            Color.accentColor.opacity(0.4)
        } else if isHovering {
            Color.black.opacity(0.15)
        } else {
            Color.black.opacity(0.08)
        }
    }

    private var shadowRadius: CGFloat {
        if isSelected {
            10
        } else if isHovering {
            6
        } else {
            4
        }
    }

    private var shadowY: CGFloat {
        if isSelected {
            5
        } else if isHovering {
            3
        } else {
            2
        }
    }

    @ViewBuilder
    private var keyboardImage: some View {
        // Images are at bundle root (not in subdirectory) due to .process() flattening
        // Same pattern as SVG loading in LiveKeyboardOverlayView
        let imageURL = KeyPathAppKitResources.url(
            forResource: layout.id,
            withExtension: "png"
        ) ?? Bundle.main.url(
            forResource: layout.id,
            withExtension: "png"
        )

        if let url = imageURL,
           let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to SF Symbol
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            AnyShapeStyle(
                Color.accentColor.opacity(isDark ? 0.25 : 0.18)
            )
        } else if isHovering {
            AnyShapeStyle(
                Color.white.opacity(isDark ? 0.12 : 0.10)
            )
        } else {
            AnyShapeStyle(
                Color.white.opacity(isDark ? 0.06 : 0.05)
            )
        }
    }
}
