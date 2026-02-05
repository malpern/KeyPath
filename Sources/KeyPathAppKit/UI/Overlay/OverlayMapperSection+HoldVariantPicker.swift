import SwiftUI

extension OverlayMapperSection {
    // MARK: - Hold Variant Picker

    /// Button that opens the hold variant popover
    var holdVariantButton: some View {
        Button {
            isHoldVariantPopoverOpen = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                Text(currentHoldVariant.label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hold-variant-button")
        .popover(isPresented: $isHoldVariantPopoverOpen, arrowEdge: .bottom) {
            holdVariantPopover
        }
    }

    /// Popover content for hold variant selection
    var holdVariantPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(HoldVariant.allCases, id: \.self) { variant in
                holdVariantRow(variant)

                if variant != HoldVariant.allCases.last {
                    Divider().opacity(0.2).padding(.horizontal, 8)
                }
            }

            // Custom keys input (shown when Custom is selected)
            if viewModel.holdBehavior == .customKeys {
                Divider().opacity(0.3).padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap-trigger keys:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g., a s d f j k l", text: $viewModel.customTapKeysText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            // Auto-save when custom keys are entered
                            if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
                                Task {
                                    await viewModel.save(kanataManager: manager)
                                }
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.2), value: viewModel.holdBehavior)
    }

    /// Single row in hold variant popover
    func holdVariantRow(_ variant: HoldVariant) -> some View {
        let isSelected = currentHoldVariant == variant

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.holdBehavior = variant.toBehaviorType
            }
            // Auto-save when variant changes
            if let manager = kanataViewModel?.underlyingManager, viewModel.inputKeyCode != nil {
                Task {
                    await viewModel.save(kanataManager: manager)
                }
            }
            // Close popover unless switching to Custom (need to show text field)
            if variant != .custom {
                isHoldVariantPopoverOpen = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(variant.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(LayerPickerItemButtonStyle())
        .accessibilityIdentifier("hold-variant-\(variant.rawValue)")
    }

    /// Current hold variant based on viewModel.holdBehavior
    var currentHoldVariant: HoldVariant {
        HoldVariant.from(viewModel.holdBehavior)
    }

    /// Hold behavior variants with user-friendly labels and explanations
    enum HoldVariant: String, CaseIterable {
        case basic
        case press
        case release
        case custom

        var label: String {
            switch self {
            case .basic: "Basic"
            case .press: "Eager"
            case .release: "Permissive"
            case .custom: "Custom Keys"
            }
        }

        var explanation: String {
            switch self {
            case .basic:
                "Hold activates after timeout"
            case .press:
                "Hold activates when another key is pressed (best for home-row mods)"
            case .release:
                "Tap registers even if another key was pressed during timeout"
            case .custom:
                "Only specific keys trigger early tap"
            }
        }

        var toBehaviorType: MapperViewModel.HoldBehaviorType {
            switch self {
            case .basic: .basic
            case .press: .triggerEarly
            case .release: .quickTap
            case .custom: .customKeys
            }
        }

        static func from(_ behaviorType: MapperViewModel.HoldBehaviorType) -> HoldVariant {
            switch behaviorType {
            case .basic: .basic
            case .triggerEarly: .press
            case .quickTap: .release
            case .customKeys: .custom
            }
        }
    }

}
