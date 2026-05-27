import KeyPathCore
import SwiftUI

/// A section with a category header and its layouts
struct LayoutCategorySection: View {
    let category: LayoutCategory
    let layouts: [PhysicalLayout]
    @Binding var selectedLayoutId: String
    let isDark: Bool
    @Binding var showImportSheet: Bool
    @Binding var refreshTrigger: UUID
    var onToast: ((String, KanataViewModel.ToastType) -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: 12)
    ]

    /// Whether to show section header (US Standard has no header)
    private var showHeader: Bool {
        category != .usStandard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header (hidden for US Standard)
            if showHeader {
                HStack {
                    Text(category.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.8)

                    Spacer()

                    // Import button for Custom section
                    if category == .custom {
                        Button {
                            showImportSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10))
                                Text("Import")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("import-custom-layout-button")
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 4)
                .padding(.top, 8)
            }

            // Layout cards in grid
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(layouts) { layout in
                    KeyboardIllustrationCard(
                        layout: layout,
                        isSelected: selectedLayoutId == layout.id,
                        isDark: isDark,
                        isCustom: layout.id.hasPrefix("custom-")
                    ) {
                        // No animation on selection - keeps drawer stable
                        selectedLayoutId = layout.id
                    } onDelete: {
                        if layout.id.hasPrefix("custom-") {
                            Task {
                                let layoutId = String(layout.id.dropFirst(7))
                                await QMKImportService.shared.deleteCustomLayout(layoutId: layoutId)
                                // If deleted layout was selected, reset to default
                                if selectedLayoutId == layout.id {
                                    selectedLayoutId = LayoutPreferences.defaultLayoutId
                                }
                                // Trigger refresh to update UI
                                refreshTrigger = UUID()
                            }
                        }
                    } onRefreshKeymap: {
                        if layout.id.hasPrefix("custom-") {
                            Task {
                                let layoutId = String(layout.id.dropFirst(7))
                                let result = await QMKImportService.shared.refreshKeymap(layoutId: layoutId)
                                await MainActor.run {
                                    switch result {
                                    case let .success(tokenCount):
                                        refreshTrigger = UUID()
                                        onToast?("Keymap refreshed — \(tokenCount) keys mapped", .success)
                                    case let .failure(message):
                                        onToast?(message, .warning)
                                    }
                                }
                            }
                        }
                    }
                    .id("layout-\(layout.id)")
                }

                // Import button card for Custom section (if no layouts yet)
                if category == .custom, layouts.isEmpty {
                    ImportLayoutCard(isDark: isDark) {
                        showImportSheet = true
                    }
                }
            }
        }
    }
}
