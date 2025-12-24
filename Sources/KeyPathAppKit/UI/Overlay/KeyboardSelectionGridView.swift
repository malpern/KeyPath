import SwiftUI
import KeyPathCore

/// Visual keyboard selection grid component with illustrations
struct KeyboardSelectionGridView: View {
    let layouts: [PhysicalLayout]
    @Binding var selectedLayoutId: String
    let isDark: Bool
    
    // Grid layout: 1 column for single-row keyboard previews
    private let columns = [
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(layouts) { layout in
                    KeyboardIllustrationCard(
                        layout: layout,
                        isSelected: selectedLayoutId == layout.id,
                        isDark: isDark
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedLayoutId = layout.id
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }
}

/// Individual keyboard illustration card with image and label
private struct KeyboardIllustrationCard: View {
    let layout: PhysicalLayout
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    @State private var scale: CGFloat = 1.0
    
    // Image size - fairly big as requested
    private let imageHeight: CGFloat = 120
    
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
                            color: isSelected ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.1),
                            radius: isSelected ? 8 : 4,
                            x: 0,
                            y: isSelected ? 4 : 2
                        )
                    
                    keyboardImage
                        .frame(maxHeight: imageHeight)
                        .padding(12)
                }
                .frame(height: imageHeight + 24)
                .scaleEffect(scale)
                
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
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
                scale = hovering ? 1.02 : 1.0
            }
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                // Selection animation
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    scale = 1.05
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        scale = 1.0
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var keyboardImage: some View {
        // Images are at bundle root (not in subdirectory) due to .process() flattening
        // Same pattern as SVG loading in LiveKeyboardOverlayView
        let imageURL = Bundle.module.url(
            forResource: layout.id,
            withExtension: "png"
        ) ?? Bundle.main.url(
            forResource: layout.id,
            withExtension: "png"
        )
        
        if let url = imageURL,
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to SF Symbol
            // Log image loading failure for debugging
            let _ = {
                AppLogger.shared.debug("🖼️ [KeyboardSelection] Could not load image for layout '\(layout.id)'. URL: \(imageURL?.absoluteString ?? "nil")")
            }()
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
    
    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                Color.accentColor.opacity(isDark ? 0.2 : 0.15)
            )
        } else if isHovering {
            return AnyShapeStyle(
                Color.white.opacity(isDark ? 0.1 : 0.08)
            )
        } else {
            return AnyShapeStyle(
                Color.white.opacity(isDark ? 0.05 : 0.04)
            )
        }
    }
}

#Preview {
    KeyboardSelectionGridView(
        layouts: Array(PhysicalLayout.all.prefix(6)),
        selectedLayoutId: .constant("macbook-us"),
        isDark: false
    )
    .frame(width: 400, height: 600)
}
