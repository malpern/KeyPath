import SwiftUI

/// Individual keycap view for keyboard visualization
struct KeycapView: View {
    let key: PhysicalKey
    let isPressed: Bool

    var body: some View {
        ZStack {
            // Keycap background
            RoundedRectangle(cornerRadius: 4)
                .fill(keycapColor)
                .shadow(color: shadowColor, radius: isPressed ? 2 : 1, x: 0, y: isPressed ? 1 : 0.5)

            // Keycap border
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: isPressed ? 1.5 : 1)

            // Label
            Text(key.label)
                .font(.system(size: fontSize, weight: .medium, design: .default))
                .foregroundColor(labelColor)
        }
    }

    // MARK: - Styling

    private var keycapColor: Color {
        if isPressed {
            Color(white: 0.7) // Brighter when pressed
        } else {
            Color(white: 0.95) // Light gray default
        }
    }

    private var borderColor: Color {
        if isPressed {
            Color(white: 0.4) // Darker border when pressed
        } else {
            Color(white: 0.8) // Light border default
        }
    }

    private var shadowColor: Color {
        Color.black.opacity(isPressed ? 0.3 : 0.15)
    }

    private var labelColor: Color {
        if isPressed {
            .black
        } else {
            Color(white: 0.3)
        }
    }

    private var fontSize: CGFloat {
        // Scale font size based on key width (smaller keys get smaller fonts)
        let baseSize: CGFloat = 12
        if key.width < 1.0 {
            return baseSize * 0.8
        } else if key.width > 2.0 {
            return baseSize * 1.2
        } else {
            return baseSize
        }
    }
}
