import SwiftUI

/// Root SwiftUI view for the Context HUD floating window
struct ContextHUDView: View {
    let viewModel: ContextHUDViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.style == .kindaVimLearning {
                kindaVimHeader
            } else {
                defaultHeader
            }

            Divider()
                .background(Color.white.opacity(0.15))

            contentView
        }
        .padding(20)
        .modifier(HUDSizeModifier(style: viewModel.style))
        .appGlassSheet(cornerRadius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context HUD: \(viewModel.layerName)")
    }

    private var contentView: some View {
        Group {
            switch viewModel.style {
            case .defaultList:
                ContextHUDDefaultListView(groups: viewModel.groups)
            case .windowSnappingGrid:
                ContextHUDWindowSnapView(entries: viewModel.allEntries)
            case .launcherIcons:
                ContextHUDLauncherView(entries: viewModel.allEntries)
            case .symbolPicker:
                ContextHUDSymbolView(entries: viewModel.allEntries)
            case .kindaVimLearning:
                ContextHUDKindaVimLearningView(
                    groups: viewModel.groups,
                    state: viewModel.kindaVimState,
                    modeSetting: viewModel.kindaVimLeaderHUDMode
                )
            case .neovimTerminal:
                ContextHUDNeovimTerminalView(groups: viewModel.groups)
            }
        }
        .environment(\.pressedKeyCodes, viewModel.pressedKeyCodes)
    }

    private struct HUDSizeModifier: ViewModifier {
        let style: HUDContentStyle

        func body(content: Content) -> some View {
            if style == .kindaVimLearning {
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: hudWidth)
            } else {
                content
                    .fixedSize()
                    .frame(minWidth: 240)
            }
        }

        private var hudWidth: CGFloat {
            let screen = NSScreen.main?.visibleFrame.width ?? 1440
            return min(screen * 0.75, 960)
        }
    }

    private var defaultHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(headerColor)
                .frame(width: 6, height: 6)
            Text(viewModel.layerName.uppercased())
                .font(.subheadline.monospaced().weight(.bold))
                .foregroundStyle(.white)
                .tracking(1.5)
        }
    }

    private var kindaVimHeader: some View {
        let vimMode = viewModel.kindaVimState?.mode ?? .normal
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(kindaVimModeColor(vimMode))
                    .frame(width: 7, height: 7)
                Text(vimMode.displayName.uppercased())
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .tracking(1.5)
            }
            Spacer(minLength: 16)
            Text(kindaVimCoachTip(for: vimMode))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func kindaVimModeColor(_ mode: KindaVimStateAdapter.Mode) -> Color {
        switch mode {
        case .insert: .green
        case .normal: .blue
        case .visual: .purple
        case .operatorPending: .orange
        case .unknown: .gray
        }
    }

    private func kindaVimCoachTip(for mode: KindaVimStateAdapter.Mode) -> String {
        switch mode {
        case .insert: "Press Esc to enter Normal mode"
        case .normal: "Navigate with motions, operators, and text objects"
        case .visual: "Extend selection with motion keys"
        case .operatorPending: "Pick a motion or text object"
        case .unknown: "Waiting for mode signal…"
        }
    }

    private var headerColor: Color {
        if let firstGroup = viewModel.groups.first {
            return firstGroup.color
        }
        return Color(red: 0.85, green: 0.45, blue: 0.15)
    }
}
