import KeyPathCore
import SwiftUI

extension OverlayInspectorPanel {
    // MARK: - Physical Layout Content

    @ViewBuilder
    var physicalLayoutContent: some View {
        KeyboardSelectionGridView(
            selectedLayoutId: $selectedLayoutId,
            isDark: isDark,
            scrollToCategory: $scrollToLayoutCategory
        )
        // Stable identity prevents scroll position reset when parent re-renders
        // (e.g., when modifier keys like Command trigger pressedKeyCodes updates)
        .id("physical-layout-grid")
    }

    // MARK: - Keycaps Content

    @ViewBuilder
    var keycapsContent: some View {
        // Colorway cards in 2-column grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(GMKColorway.all) { colorway in
                ColorwayCard(
                    colorway: colorway,
                    isSelected: selectedColorwayId == colorway.id,
                    isDark: isDark
                ) {
                    selectedColorwayId = colorway.id
                }
            }
        }
    }

    // MARK: - Sounds Content

    @ViewBuilder
    var soundsContent: some View {
        TypingSoundsSection(isDark: isDark)
    }

    // MARK: - Launchers Content

    @ViewBuilder
    var launchersContent: some View {
        OverlayLaunchersSection(
            isDark: isDark,
            fadeAmount: fadeAmount,
            onMappingHover: onRuleHover,
            onCustomize: { activeDrawerPanel = .launcherSettings }
        )
    }
}
