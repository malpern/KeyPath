import SwiftUI

struct OnboardingView: View {
    var securityManager: SecurityManager
    @Binding var showOnboarding: Bool
    @State private var currentStep = 0
    @Environment(\.colorScheme) var colorScheme
    @State private var anthropicAPIKey = ""
    @State private var tempAPIKey = ""
    @State private var showAPIKey = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("KeyPath Setup")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button("Skip") {
                    showOnboarding = false
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            // Progress indicator
            ProgressView(value: Double(currentStep + 1), total: 4)
                .padding(.horizontal)
            
            // Content
            ZStack {
                switch currentStep {
                case 0:
                    WelcomeStep()
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 1:
                    APIKeyStep(tempAPIKey: $tempAPIKey, showAPIKey: $showAPIKey)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 2:
                    KanataInstallStep(isInstalled: securityManager.isKanataInstalled)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 3:
                    ConfigurationStep(hasAccess: securityManager.hasConfigAccess)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                default:
                    WelcomeStep()
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            
            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Previous") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    // Invisible spacer for alignment
                    Button("Previous") {
                        // Do nothing
                    }
                    .buttonStyle(.plain)
                    .opacity(0)
                    .disabled(true)
                }
                
                Spacer()
                
                if currentStep < 3 {
                    Button("Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        // Save the API key if entered
                        if !tempAPIKey.isEmpty {
                            do {
                                try KeychainManager.shared.setAPIKey(tempAPIKey)
                            } catch {
                                // Log error but don't block onboarding
                                print("Failed to save API key: \(error)")
                            }
                        }
                        showOnboarding = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 600)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ?
                      Color(NSColor.windowBackgroundColor) :
                      Color.white)
        )
    }
}

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Welcome to KeyPath")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("KeyPath helps you create custom keyboard remappings using natural language and AI.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "message.fill",
                    title: "Natural Language",
                    description: "Describe your remapping in plain English"
                )
                
                FeatureRow(
                    icon: "cpu",
                    title: "AI-Powered",
                    description: "Claude Sonnet 4 understands your intent"
                )
                
                FeatureRow(
                    icon: "checkmark.shield.fill",
                    title: "Safe & Validated",
                    description: "All rules are validated before installation"
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(.vertical, 20)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct APIKeyStep: View {
    @Binding var tempAPIKey: String
    @Binding var showAPIKey: Bool
    @State private var isValidating = false
    @State private var savedAPIKey = ""
    @State private var saveError: String? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Connect to Claude AI")
                .font(.title)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("KeyPath uses Claude AI to translate your natural language into keyboard remapping rules.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Anthropic API Key:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-api...", text: $tempAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-ant-api...", text: $tempAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: 400)
                    
                    HStack(spacing: 4) {
                        Text("Don't have an API key?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link("Get one at console.anthropic.com", 
                             destination: URL(string: "https://console.anthropic.com/")!)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 40)
                
                if !tempAPIKey.isEmpty {
                    Button("Save API Key") {
                        do {
                            try KeychainManager.shared.setAPIKey(tempAPIKey)
                            savedAPIKey = tempAPIKey
                            saveError = nil
                        } catch {
                            saveError = "Failed to save API key: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                }
                
                if let error = saveError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal, 40)
                }
                
                Text("You can skip this step and add your API key later in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding(.vertical, 20)
        .onAppear {
            // Check for existing API key from Keychain
            if let keychainKey = KeychainManager.shared.apiKey, !keychainKey.isEmpty {
                tempAPIKey = keychainKey
                savedAPIKey = keychainKey
            }
        }
    }
}

struct KanataInstallStep: View {
    let isInstalled: Bool
    @State private var showInstallCommands = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(isInstalled ? .green : .red)
            
            Text(isInstalled ? "Kanata Detected" : "Kanata Not Found")
                .font(.title)
                .fontWeight(.semibold)
            
            if isInstalled {
                Text("Great! Kanata is installed on your system.")
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 16) {
                    Text("KeyPath requires Kanata to remap your keyboard.")
                        .foregroundColor(.secondary)
                    
                    Button("Show Installation Steps") {
                        showInstallCommands.toggle()
                    }
                    
                    if showInstallCommands {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("1. Download Kanata:")
                                .fontWeight(.medium)
                            Link("github.com/jtroo/kanata", 
                                 destination: URL(string: "https://github.com/jtroo/kanata/releases")!)
                            
                            Text("2. Install the binary:")
                                .fontWeight(.medium)
                                .padding(.top, 8)
                            
                            CodeBlock(code: """
                                # Move to /usr/local/bin
                                sudo mv kanata /usr/local/bin/
                                
                                # Make executable
                                sudo chmod +x /usr/local/bin/kanata
                                """)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

struct ConfigurationStep: View {
    let hasAccess: Bool
    @State private var showConfigSteps = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: hasAccess ? "checkmark.circle.fill" : "folder.badge.questionmark")
                .font(.system(size: 80))
                .foregroundColor(hasAccess ? .green : .orange)
            
            Text(hasAccess ? "Configuration Ready" : "Configuration Setup Needed")
                .font(.title)
                .fontWeight(.semibold)
            
            if hasAccess {
                Text("Your Kanata configuration is ready for KeyPath.")
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 16) {
                    Text("KeyPath will automatically create the configuration file when you first use it.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What KeyPath will create:")
                            .fontWeight(.medium)
                        
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.green)
                            Text("~/.config/kanata/ directory")
                        }
                        
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .foregroundColor(.green)
                            Text("kanata.kbd configuration file")
                        }
                        
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("Default settings for remapping")
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 40)
    }
}

struct CodeBlock: View {
    let code: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ?
                          Color.white.opacity(0.05) :
                          Color.black.opacity(0.05))
            )
            .textSelection(.enabled)
    }
}
