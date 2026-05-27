import KeyPathCore
import SwiftUI

// Most special key content has moved to BaseKeycap.swift.
// touchIdContent, capsLockIndicator, and functionKeyWithMappingContent
// remain for the parent shell (keycapBody, dots legend).

extension OverlayKeycapView {
    // MARK: - Touch ID / Layer Indicator

    @ViewBuilder
    var touchIdContent: some View {
        if isLoadingLayerMap {
            Circle()
                .fill(foregroundColor.opacity(0.6))
                .frame(width: 4 * scale, height: 4 * scale)
                .modifier(PulseAnimation())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: "sidebar.right")
                .font(.system(size: 12 * scale, weight: .regular))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Function Key (retained for dots legend)

    @ViewBuilder
    var functionKeyWithMappingContent: some View {
        let iconName: String? = if hasSystemAction, let sysIcon = systemActionIcon {
            sysIcon
        } else {
            LabelMetadata.sfSymbol(forKeyCode: key.keyCode)
        }

        VStack(spacing: 0) {
            if let icon = iconName {
                Image(systemName: icon)
                    .font(.system(size: 8 * scale, weight: .regular))
                    .foregroundStyle(foregroundColor)
            }
            Spacer()
            Text(key.label)
                .font(.system(size: 5.4 * scale, weight: .regular))
                .foregroundStyle(foregroundColor.opacity(0.6))
        }
        .padding(.top, 4 * scale)
        .padding(.bottom, 2 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Caps Lock Indicator

    var capsLockIndicator: some View {
        VStack {
            HStack {
                Circle()
                    .fill(isCapsLockOn ? Color.green : Color.white.opacity(0.15))
                    .frame(width: 4 * scale, height: 4 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(1.0) : .clear, radius: 2 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(0.8) : .clear, radius: 4 * scale)
                    .shadow(color: isCapsLockOn ? Color.green.opacity(0.5) : .clear, radius: 8 * scale)
                    .animation(.easeInOut(duration: 0.2), value: isCapsLockOn)
                Spacer()
            }
            .padding(.leading, 4.4 * scale)
            .padding(.top, 3 * scale)
            Spacer()
        }
    }
}
