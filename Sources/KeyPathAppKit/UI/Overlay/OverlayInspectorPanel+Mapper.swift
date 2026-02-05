import SwiftUI

extension OverlayInspectorPanel {
    // MARK: - Mapper Content

    @ViewBuilder
    var mapperContent: some View {
        // Use a single OverlayMapperSection instance to maintain view identity across health state changes.
        // Previously, separate instances for .unhealthy/.checking/.healthy caused onAppear to reset
        // the selected key when health state changed (e.g., after clicking a rule from the rules panel).
        let showMapper: Bool = {
            if isMapperAvailable { return true }
            if healthIndicatorState == .checking { return true }
            if case .unhealthy = healthIndicatorState { return true }
            return false
        }()
        if showMapper {
            OverlayMapperSection(
                isDark: isDark,
                kanataViewModel: kanataViewModel,
                healthIndicatorState: healthIndicatorState,
                onHealthTap: onHealthTap,
                fadeAmount: fadeAmount,
                onKeySelected: onKeySelected,
                layerKeyMap: layerKeyMap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            unavailableSection(
                title: "Mapper Unavailable",
                message: "Finish setup to enable quick remapping in the overlay."
            )
        }
    }
}
