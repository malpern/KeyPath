import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyPath Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsWindowView())
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

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

struct RuleDetailView: View {
    @State var rule: MockRule
    let onBack: () -> Void
    let onUpdate: (MockRule) -> Void
    @State private var isEditingName = false
    @State private var editedName = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Rule name (editable)
                if isEditingName {
                    TextField("Rule name", text: $editedName, onCommit: {
                        rule.name = editedName
                        isEditingName = false
                        onUpdate(rule)
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.title2)
                    .fontWeight(.semibold)
                } else {
                    Button(action: {
                        editedName = rule.name
                        isEditingName = true
                    }) {
                        Text(rule.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Large visualization with demo button
                    VStack(spacing: 16) {
                        EnhancedRemapVisualizer(behavior: rule.behavior)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColor.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(rule.explanation)
                            .foregroundColor(.secondary)
                    }
                    
                    // Kanata code with syntax highlighting
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kanata Configuration")
                            .font(.headline)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(rule.kanataCode)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RuleRowView: View {
    let rule: MockRule
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Checkbox
                Button(action: onToggle) {
                    Image(systemName: rule.isActive ? "checkmark.square.fill" : "square")
                        .foregroundColor(rule.isActive ? .accentColor : .secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .onTapGesture {
                    onToggle()
                }
                
                // Rule name and visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text(rule.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    CompactRuleVisualizer(behavior: rule.behavior, explanation: rule.explanation)
                        .opacity(rule.isActive ? 1.0 : 0.6)
                }
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Delete rule")
                .onTapGesture {
                    onDelete()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12) // Increased from 8 to 12 for 25% more height
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rule.isActive ? Color.clear : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GeneralSettingsView: View {
    @State private var securityManager = SecurityManager()
    @State private var showOnboarding = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                // Setup and Security Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Setup & Security")
                        .font(.headline)
                    
                    HStack {
                        Button(action: { showOnboarding = true }) {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                Text("Setup Guide")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                        
                        Button(action: {
                            securityManager.forceRefresh()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh Setup")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Divider()
                
                // Chat Management Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Chat Management")
                        .font(.headline)
                    
                    Button(action: {
                        // This would need to be connected to the main view's reset function
                        // For now, it's a placeholder
                    }) {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("New Chat")
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Text("Note: Use Cmd+N or menu bar to start a new chat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                securityManager: securityManager,
                showOnboarding: $showOnboarding
            )
        }
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("useStreaming") private var useStreaming = AppSettings.useStreaming
    @AppStorage("temperature") private var temperature = AppSettings.temperature
    @AppStorage("systemInstructions") private var systemInstructions = AppSettings.systemInstructions
    @AppStorage("chatProvider") private var chatProvider = AppSettings.chatProvider
    @State private var anthropicAPIKey = ""
    @State private var showAPIKey = false
    @State private var saveError: String? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Advanced Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.top)
                
                Divider()
                
                // API Configuration
                VStack(alignment: .leading, spacing: 16) {
                    Text("API Configuration")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anthropic API Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if showAPIKey {
                                TextField("sk-ant-api...", text: $anthropicAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-ant-api...", text: $anthropicAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(action: { showAPIKey.toggle() }) {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .help("Your Anthropic API key. Get one at https://console.anthropic.com/")
                        
                        if let error = saveError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        if anthropicAPIKey.isEmpty {
                            Label("API key required for KeyPath to work", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("API key configured")
                                    .font(.caption)
                            }
                        }
                        
                        Link("Get an API key from Anthropic", destination: URL(string: "https://console.anthropic.com/")!)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // Generation Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Generation Settings")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Stream Responses", isOn: $useStreaming)
                        
                        VStack(alignment: .leading) {
                            Text("Temperature: \(temperature, specifier: "%.2f")")
                            Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                            Text("Higher values make output more creative but less focused")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Instructions")
                                .font(.subheadline)
                            TextEditor(text: $systemInstructions)
                                .frame(minHeight: 100)
                                .font(.body)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Load API key from Keychain if available
            if let keychainKey = KeychainManager.shared.apiKey, !keychainKey.isEmpty {
                anthropicAPIKey = keychainKey
            }
        }
        .onChange(of: anthropicAPIKey) { oldValue, newValue in
            // Save to Keychain when API key changes
            if !newValue.isEmpty {
                do {
                    try KeychainManager.shared.setAPIKey(newValue)
                    saveError = nil
                } catch {
                    saveError = "Failed to save API key securely: \(error.localizedDescription)"
                }
            }
        }
    }
}

// Mock data for demo
struct MockRule: Identifiable {
    let id = UUID()
    var name: String
    let behavior: KanataBehavior
    let explanation: String
    let kanataCode: String
    var isActive: Bool
}

struct MockRuleData {
    static let sampleRules: [MockRule] = [
        MockRule(
            name: "Caps to Escape",
            behavior: .simpleRemap(from: "Caps Lock", toKey: "Escape"),
            explanation: "Map Caps Lock to Escape for modal editing",
            kanataCode: "(defsrc caps) (deflayer base esc)",
            isActive: true
        ),
        MockRule(
            name: "Space Shift",
            behavior: .tapHold(key: "Space", tap: "Space", hold: "Shift"),
            explanation: "Space acts as Shift when held",
            kanataCode: "(defsrc spc) (deflayer base (tap-hold 200 200 spc lsft))",
            isActive: true
        ),
        MockRule(
            name: "F Multi-Tap",
            behavior: .tapDance(key: "F", actions: [
                TapDanceAction(tapCount: 1, action: "F", description: ""),
                TapDanceAction(tapCount: 2, action: "Ctrl+F", description: ""),
                TapDanceAction(tapCount: 3, action: "Cmd+F", description: "")
            ]),
            explanation: "F key with multiple tap actions",
            kanataCode: "(defsrc f) (deflayer base (tap-dance 200 (f (lctl f) (lgui f))))",
            isActive: false
        ),
        MockRule(
            name: "Email Expander",
            behavior: .sequence(trigger: "email", sequence: ["j", "o", "h", "n", "@", "e", "x", "a", "m", "p", "l", "e", ".", "c", "o", "m"]),
            explanation: "Type 'email' to expand to email address",
            kanataCode: "(defseq email (macro john@example.com))",
            isActive: true
        ),
        MockRule(
            name: "Hello Chord",
            behavior: .combo(keys: ["A", "S", "D"], result: "Hello World"),
            explanation: "Chord typing for quick text expansion",
            kanataCode: "(defchords base 50 (a s d) (macro \"Hello World\"))",
            isActive: true
        ),
        MockRule(
            name: "Gaming Layer",
            behavior: .layer(key: "Fn", layerName: "Gaming", mappings: ["W": "↑", "A": "←", "S": "↓", "D": "→"]),
            explanation: "Gaming layer with arrow key mappings",
            kanataCode: "(deflayer gaming up left down right)",
            isActive: false
        ),
        MockRule(
            name: "Right Cmd Enter",
            behavior: .simpleRemap(from: "Right Cmd", toKey: "Enter"),
            explanation: "Right Command as Enter key",
            kanataCode: "(defsrc rcmd) (deflayer base ret)",
            isActive: true
        ),
        MockRule(
            name: "Tab Control",
            behavior: .tapHold(key: "Tab", tap: "Tab", hold: "Ctrl"),
            explanation: "Tab key doubles as Control when held",
            kanataCode: "(defsrc tab) (deflayer base (tap-hold 200 200 tab lctl))",
            isActive: false
        ),
        MockRule(
            name: "Address Shortcut",
            behavior: .sequence(trigger: "addr", sequence: ["1", "2", "3", " ", "M", "a", "i", "n", " ", "S", "t"]),
            explanation: "Quick address expansion",
            kanataCode: "(defseq addr (macro \"123 Main St\"))",
            isActive: true
        ),
        MockRule(
            name: "KeyPath Combo",
            behavior: .combo(keys: ["Cmd", "Shift", "K"], result: "KeyPath Rocks!"),
            explanation: "Special KeyPath combo",
            kanataCode: "(defchords base 50 (lgui lsft k) (macro \"KeyPath Rocks!\"))",
            isActive: true
        )
    ]
}
