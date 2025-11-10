import SwiftUI
import KeyPathCore

struct RulesSummaryView: View {
    @EnvironmentObject var kanataManager: KanataViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Rules", systemImage: "list.bullet")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Text("\(kanataManager.keyMappings.count) total")
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            if kanataManager.keyMappings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No rules found").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(kanataManager.keyMappings, id: \.self.input) { mapping in
                            HStack(spacing: 8) {
                                Text(mapping.input)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                Text(mapping.output)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 360)
    }
}


