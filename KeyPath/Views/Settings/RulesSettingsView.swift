import SwiftUI

// Showcase rule data structure
struct ShowcaseRule {
    let explanation: String
    let detailedExplanation: String
    let kanataRule: String
    let visualization: EnhancedRemapVisualization
}

// Showcase rules data
let showcaseRules: [ShowcaseRule] = [
    ShowcaseRule(
        explanation: "Caps Lock → Escape",
        detailedExplanation: "Replaces the rarely-used Caps Lock key with Escape. Essential for Vim users and helpful for anyone who uses Escape frequently.",
        kanataRule: "(defsrc\n  caps\n)\n\n(deflayer default\n  esc\n)",
        visualization: EnhancedRemapVisualization(
            behavior: .simpleRemap(from: "caps", toKey: "esc"),
            title: "Caps Lock to Escape",
            description: "Popular among Vim users"
        )
    ),
    ShowcaseRule(
        explanation: "Space Cadet Shift (tap Space = Space, hold = Shift)",
        detailedExplanation: "Makes the spacebar dual-function: tap for space, hold for Shift. Reduces finger movement and makes typing symbols more ergonomic.",
        kanataRule: "(defsrc\n  spc\n)\n\n(deflayer default\n  (tap-hold 200 200 spc lsft)\n)",
        visualization: EnhancedRemapVisualization(
            behavior: .tapHold(key: "spc", tap: "spc", hold: "lsft"),
            title: "Space Cadet Shift",
            description: "Space bar acts as Shift when held"
        )
    ),
    ShowcaseRule(
        explanation: "Home Row Mods (A = A/Ctrl, S = S/Alt, D = D/Cmd)",
        detailedExplanation: "Transform home row keys into modifier keys when held. Keeps your hands on the home row for faster typing and shortcuts without reaching for modifier keys.",
        kanataRule: "(defsrc\n  a s d\n)\n\n(deflayer default\n  (tap-hold 200 200 a lctl) (tap-hold 200 200 s lalt) (tap-hold 200 200 d lmet)\n)",
        visualization: EnhancedRemapVisualization(
            behavior: .tapHold(key: "a", tap: "a", hold: "lctl"),
            title: "Home Row Mods",
            description: "Turn home row keys into dual-function modifier keys"
        )
    ),
    ShowcaseRule(
        explanation: "Multi-tap F (1x = F, 2x = Find, 3x = Find All)",
        detailedExplanation: "Single F key does different actions based on how many times you tap it. Perfect for frequently used functions without remembering complex shortcuts.",
        kanataRule: "(defsrc\n  f\n)\n\n(deflayer default\n  (tap-dance 200 (f (C-f) (C-S-f)))\n)",
        visualization: EnhancedRemapVisualization(
            behavior: .tapDance(key: "f", actions: [
                TapDanceAction(tapCount: 1, action: "f", description: "Normal F"),
                TapDanceAction(tapCount: 2, action: "C-f", description: "Find"),
                TapDanceAction(tapCount: 3, action: "C-S-f", description: "Find All")
            ]),
            title: "Multi-tap F",
            description: "Different actions based on tap count"
        )
    ),
    ShowcaseRule(
        explanation: "Email Expander (type 'em' → your@email.com)",
        detailedExplanation: "Automatically expands short sequences into longer text. Great for email addresses, common phrases, or code snippets you type frequently.",
        kanataRule: "(defseq em (e m))\n\n(deffakekeys\n  em (macro y o u r @ e m a i l . c o m)\n)\n\n(defsrc)\n(deflayer default)",
        visualization: EnhancedRemapVisualization(
            behavior: .sequence(trigger: "em", sequence: ["y", "o", "u", "r", "@", "e", "m", "a", "i", "l", ".", "c", "o", "m"]),
            title: "Email Expander",
            description: "Type 'em' to expand to your email"
        )
    ),
    ShowcaseRule(
        explanation: "Quick Copy/Paste (J+K = Copy, K+L = Paste)",
        detailedExplanation: "Press multiple keys simultaneously for instant actions. Much faster than traditional Cmd+C/Cmd+V, especially for frequent copy-paste workflows.",
        kanataRule: "(defchords default 30\n  (j k) C-c\n  (k l) C-v\n)\n\n(defsrc\n  j k l\n)\n\n(deflayer default\n  j k l\n)",
        visualization: EnhancedRemapVisualization(
            behavior: .combo(keys: ["j", "k"], result: "C-c"),
            title: "Quick Copy/Paste",
            description: "Chord combinations for common actions"
        )
    ),
    ShowcaseRule(
        explanation: "Tab Navigation ([ = Previous Tab, ] = Next Tab)",
        detailedExplanation: "Navigate browser tabs using intuitive bracket keys. Much more natural than reaching for Cmd+Shift+Tab when you're browsing or researching.",
        kanataRule: "(defsrc\n  [ ]\n)\n\n(deflayer default\n  C-S-tab C-tab\n)",
        visualization: EnhancedRemapVisualization(
            behavior: .simpleRemap(from: "[", toKey: "C-S-tab"),
            title: "Tab Navigation",
            description: "Quick tab switching with square brackets"
        )
    ),
    ShowcaseRule(
        explanation: "Vim Arrow Keys (Ctrl+H/J/K/L = ←↓↑→)",
        detailedExplanation: "Use Vim-style navigation (H/J/K/L) as arrow keys when held. Keeps your hands on the home row while navigating text and interfaces efficiently.",
        kanataRule: "(defsrc\n  h j k l\n)\n\n(deflayer default\n  (tap-hold-press 200 200 h left) (tap-hold-press 200 200 j down) (tap-hold-press 200 200 k up) (tap-hold-press 200 200 l rght)\n)",
        visualization: EnhancedRemapVisualization(
            behavior: .layer(key: "ctrl", layerName: "vim-nav", mappings: ["h": "left", "j": "down", "k": "up", "l": "rght"]),
            title: "Vim Arrow Keys",
            description: "Navigate with Vim-style keybindings"
        )
    )
]

// Showcase rule row view
struct ShowcaseRuleRow: View {
    let rule: ShowcaseRule
    let onInstall: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Rule visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text(rule.visualization.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(rule.detailedExplanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    CompactRuleVisualizer(
                        behavior: rule.visualization.behavior,
                        explanation: rule.explanation
                    )
                }
                
                Spacer()
                
                // Add button
                Button(action: onInstall) {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .onTapGesture {
                    onInstall()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RulesSettingsView: View {
    @State private var userRuleManager = UserRuleManager.shared
    @State private var selectedRule: UserRule?
    @State private var selectedShowcaseRule: ShowcaseRule?
    @State private var ruleHistory = RuleHistory()
    @State private var showDeleteConfirmation: UUID?
    @State private var showExamples = true  // Default to showing examples

    var body: some View {
        if let selectedRule = selectedRule {
            UserRuleDetailView(
                rule: selectedRule,
                onBack: { self.selectedRule = nil }
            )
        } else if let selectedShowcaseRule = selectedShowcaseRule {
            ShowcaseRuleDetailView(
                rule: selectedShowcaseRule,
                onBack: { self.selectedShowcaseRule = nil },
                onInstall: { 
                    installShowcaseRule(selectedShowcaseRule)
                    self.selectedShowcaseRule = nil
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

                    Text("\(userRuleManager.enabledRules.count) of \(userRuleManager.activeRules.count) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()

                Divider()

                // Rules list
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Example Rules Section
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: { 
                                withAnimation { 
                                    showExamples.toggle()
                                    print("🔧 DEBUG: Example rules toggled, now showing: \(showExamples)")
                                } 
                            }) {
                                HStack {
                                    Text("Example Rules")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: showExamples ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            if showExamples {
                                Text("Popular keyboard remapping examples to get you started")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                LazyVStack(spacing: 8) {
                                    ForEach(showcaseRules, id: \.explanation) { rule in
                                        ShowcaseRuleRow(
                                            rule: rule,
                                            onInstall: { installShowcaseRule(rule) },
                                            onTap: { selectedShowcaseRule = rule }
                                        )
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Divider between sections
                        if !userRuleManager.allRules.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                        }
                        
                        // Active Rules Section
                        if !userRuleManager.allRules.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Rules")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ForEach(userRuleManager.allRules) { rule in
                                    UserRuleRowView(
                                        rule: rule,
                                        onToggle: { toggleRule(rule.id) },
                                        onDelete: { showDeleteConfirmation = rule.id },
                                        onTap: { selectedRule = rule }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .onAppear {
                    print("🔧 DEBUG: RulesSettingsView appeared")
                    print("🔧 DEBUG: Number of showcase rules: \(showcaseRules.count)")
                    print("🔧 DEBUG: Number of active rules: \(userRuleManager.activeRules.count)")
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
    
    private func installShowcaseRule(_ showcaseRule: ShowcaseRule) {
        let kanataRule = KanataRule(
            visualization: showcaseRule.visualization,
            kanataRule: showcaseRule.kanataRule,
            confidence: .high,
            explanation: showcaseRule.explanation
        )
        
        userRuleManager.addRule(kanataRule) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Successfully installed showcase rule: \(showcaseRule.explanation)")
                case .failure(let error):
                    print("Failed to install showcase rule: \(error.localizedDescription)")
                }
            }
        }
    }
}
