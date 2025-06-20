import SwiftUI

struct SettingsWindowView: View {
    @State private var selectedTab: SettingsTab = .rules

    enum SettingsTab: String, CaseIterable {
        case rules = "Rules"
        case general = "General"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .rules: return "list.bullet"
            case .general: return "gearshape"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding()

                Divider()

                VStack(spacing: 0) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button(action: { selectedTab = tab }) {
                            HStack {
                                Image(systemName: tab.icon)
                                    .frame(width: 20)
                                Text(tab.rawValue)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Spacer()
            }
            .frame(minWidth: 200, maxWidth: 200)
            .background(Color(NSColor.controlBackgroundColor))

            // Main content
            Group {
                switch selectedTab {
                case .rules:
                    RulesSettingsView()
                case .general:
                    GeneralSettingsView()
                case .advanced:
                    AdvancedSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
