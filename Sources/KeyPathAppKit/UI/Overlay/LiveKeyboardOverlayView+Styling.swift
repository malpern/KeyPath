import AppKit
import SwiftUI

extension LiveKeyboardOverlayView {
    var isDark: Bool {
        colorScheme == .dark
    }

    var overlayPanelFill: Color {
        Color(white: isDark ? 0.11 : 0.88)
    }

    @ViewBuilder
    func glassBackground(
        cornerRadius: CGFloat,
        fadeAmount: CGFloat,
        isHovered: Bool,
        isDragging: Bool
    ) -> some View {
        let dragBoost: CGFloat = isDragging ? 0.06 : 0
        let tint = isDark
            ? Color.white.opacity(0.12 - 0.07 * fadeAmount + dragBoost)
            : Color.black.opacity(0.08 - 0.04 * fadeAmount + dragBoost)

        let contactShadow = Color.black.opacity((isDark ? 0.12 : 0.08) * (1 - fadeAmount))

        let focusBorderOpacity: CGFloat = {
            if isDragging {
                return isDark ? 0.45 : 0.5
            }
            return isHovered ? (isDark ? 0.25 : 0.35) : 0
        }()
        let focusBorderColor = isDark ? Color.white : Color.black

        let baseShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            baseShape
                .fill(Color(white: isDark ? 0.1 : 0.92))
                .overlay(
                    baseShape.stroke(Color.white.opacity(isDark ? 0.08 : 0.25), lineWidth: 0.5)
                )
                .overlay(
                    baseShape.stroke(focusBorderColor.opacity(focusBorderOpacity), lineWidth: 1)
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
        } else {
            baseShape
                .fill(.ultraThinMaterial)
                .overlay(
                    baseShape.fill(tint)
                )
                .overlay(
                    baseShape.fill(Color(white: isDark ? 0.1 : 0.9).opacity(0.25 * fadeAmount))
                )
                .overlay(
                    baseShape.strokeBorder(focusBorderColor.opacity(focusBorderOpacity), lineWidth: 1)
                )
                .shadow(color: contactShadow, radius: 4, x: 0, y: 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fadeAmount)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
        }
    }

    func updateOverlayCursor(
        hovering: Bool,
        isDragging: Bool,
        allowDragCursor: Bool,
        isOverButton: Bool = false
    ) {
        if isDragging {
            NSCursor.closedHand.set()
            return
        }
        if isOverButton {
            NSCursor.pointingHand.set()
            return
        }
        guard allowDragCursor else {
            NSCursor.arrow.set()
            return
        }
        if hovering {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    func refreshOverlayCursor(allowDragCursor: Bool) {
        updateOverlayCursor(
            hovering: isOverlayHovered,
            isDragging: isKeyboardDragging || isHeaderDragging,
            allowDragCursor: allowDragCursor,
            isOverButton: isHoveringHeaderButton
        )
    }

    func makeInspectorContent(
        fadeAmount: CGFloat,
        inspectorTotalWidth: CGFloat,
        inspectorReveal: CGFloat,
        inspectorLeadingGap: CGFloat,
        healthIndicatorState: HealthIndicatorState,
        onHealthTap: @escaping () -> Void,
        onKeySelected: @escaping (UInt16?) -> Void,
        onRuleHover: @escaping (String?) -> Void
    ) -> some View {
        OverlayInspectorPanel(
            selectedSection: inspectorSection,
            onSelectSection: { selectInspectorSection($0) },
            fadeAmount: fadeAmount,
            isMapperAvailable: isMapperAvailable,
            kanataViewModel: kanataViewModel,
            inspectorReveal: inspectorReveal,
            inspectorTotalWidth: inspectorTotalWidth,
            inspectorLeadingGap: inspectorLeadingGap,
            healthIndicatorState: healthIndicatorState,
            onHealthTap: onHealthTap,
            onKeymapChanged: onKeymapChanged,
            isSettingsShelfActive: isSettingsShelfActive,
            onToggleSettingsShelf: toggleSettingsShelf,
            onKeySelected: onKeySelected,
            layerKeyMap: viewModel.layerKeyMap,
            hasCustomRules: hasCustomRules,
            customRules: cachedCustomRules,
            appKeymaps: appKeymaps,
            onDeleteAppRule: { keymap, override in
                deleteAppRule(keymap: keymap, override: override)
            },
            onDeleteGlobalRule: { rule in
                Task {
                    await kanataViewModel?.removeCustomRule(rule.id)
                    loadCustomRulesState()
                }
            },
            onResetAllRules: {
                showResetAllRulesConfirmation = true
            },
            onCreateNewAppRule: {
                inspectorSection = .mapper
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .openMapperAppConditionPicker, object: nil)
                }
            },
            onRuleHover: onRuleHover
        )
        .frame(width: inspectorTotalWidth, alignment: .trailing)
    }

    func moveKeyboardWindow(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = findOverlayWindow() else { return }
        var newOrigin = keyboardDragInitialFrame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        window.setFrameOrigin(newOrigin)
    }

    func findOverlayWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.styleMask.contains(.borderless) && $0.level == .floating
        }
    }
}
