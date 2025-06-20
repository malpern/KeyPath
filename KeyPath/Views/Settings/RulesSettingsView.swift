import SwiftUI

struct RulesSettingsView: View {
    @State private var userRuleManager = UserRuleManager()
    @State private var selectedRule: UserRule?
    @State private var ruleHistory = RuleHistory()
    @State private var showDeleteConfirmation: UUID? = nil

    var body: some View {
        if let selectedRule = selectedRule {
            UserRuleDetailView(
                rule: selectedRule,
                onBack: { self.selectedRule = nil }
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

                    Text("\(userRuleManager.enabledRules.count) of \(userRuleManager.activeRules.count) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()

                Divider()

                // Rules list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(userRuleManager.allRules) { rule in
                            UserRuleRowView(
                                rule: rule,
                                onToggle: { toggleRule(rule.id) },
                                onDelete: { showDeleteConfirmation = rule.id },
                                onTap: { selectedRule = rule }
                            )
                        }
                    }
                    .padding()
                }
                .alert("Delete Rule?", isPresented: .constant(showDeleteConfirmation != nil)) {
                    Button("Cancel", role: .cancel) {
                        showDeleteConfirmation = nil
                    }
                    Button("Delete", role: .destructive) {
                        if let ruleId = showDeleteConfirmation {
                            deleteRule(ruleId)
                        }
                        showDeleteConfirmation = nil
                    }
                } message: {
                    Text("This rule will be deleted permanently after 48 hours. Are you sure?")
                }
            }
        }
    }

    private func toggleRule(_ ruleId: UUID) {
        userRuleManager.toggleRule(ruleId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let isActive):
                    print("Rule \(isActive ? "activated" : "deactivated") successfully")
                case .failure(let error):
                    print("Failed to toggle rule: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteRule(_ ruleId: UUID) {
        userRuleManager.deleteRule(ruleId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Rule deleted successfully")
                case .failure(let error):
                    print("Failed to delete rule: \(error.localizedDescription)")
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