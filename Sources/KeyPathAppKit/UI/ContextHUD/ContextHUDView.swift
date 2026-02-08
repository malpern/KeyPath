import SwiftUI

/// Root SwiftUI view for the Context HUD floating window
struct ContextHUDView: View {
    let viewModel: ContextHUDViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Layer name header
            HStack(spacing: 6) {
                Circle()
                    .fill(headerColor)
                    .frame(width: 6, height: 6)

                Text(viewModel.layerName.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(1.5)
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Content based on style
            contentView
        }
        .padding(20)
        .frame(minWidth: 240, maxWidth: 800)
        .appGlassSheet(cornerRadius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context HUD: \(viewModel.layerName)")
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.style {
        case .defaultList:
            ContextHUDDefaultListView(groups: viewModel.groups)
        case .windowSnappingGrid:
            ContextHUDWindowSnapView(entries: viewModel.allEntries)
        case .launcherIcons:
            ContextHUDLauncherView(entries: viewModel.allEntries)
        case .symbolPicker:
            ContextHUDSymbolView(entries: viewModel.allEntries)
        }
    }

    private var headerColor: Color {
        if let firstGroup = viewModel.groups.first {
            return firstGroup.color
        }
        return Color(red: 0.85, green: 0.45, blue: 0.15)
    }
}
