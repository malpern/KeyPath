import SwiftUI

struct RulesSettingsView: View {
    @State private var mockRules = MockRuleData.sampleRules
    @State private var selectedRule: MockRule?
    @State private var ruleHistory = RuleHistory()

    var body: some View {
        if let selectedRule = selectedRule {
            RuleDetailView(
                rule: selectedRule,
                onBack: { self.selectedRule = nil },
                onUpdate: { updatedRule in
                    if let index = mockRules.firstIndex(where: { $0.id == updatedRule.id }) {
                        mockRules[index] = updatedRule
                    }
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Active Rules")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    if !ruleHistory.items.isEmpty {
                        Button(action: undoLastRule) {
                            HStack {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Undo Last")
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("\(mockRules.filter(\.isActive).count) of \(mockRules.count) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()

                Divider()

                // Rules list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(mockRules.enumerated()), id: \.element.id) { index, rule in
                            RuleRowView(
                                rule: rule,
                                onToggle: { mockRules[index].isActive.toggle() },
                                onDelete: { mockRules.remove(at: index) },
                                onTap: { selectedRule = rule }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func undoLastRule() {
        guard let lastRule = ruleHistory.getLastRule() else { return }

        let installer = KanataInstaller()

        installer.undoLastRule(backupPath: lastRule.backupPath) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.ruleHistory.removeLastRule()
                    // Could show success message
                case .failure(let error):
                    // Could show error message
                    print("Failed to undo: \(error.localizedDescription)")
                }
            }
        }
    }
}