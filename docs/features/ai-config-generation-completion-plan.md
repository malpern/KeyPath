# AI Config Generation Feature Completion Plan

## Overview

Complete the AI-powered config generation feature to work seamlessly for both developers and non-technical users. This includes UI for API key management, clear documentation, cost transparency, and user-friendly messaging about limitations.

## Current State

- ✅ **Backend Implementation**: `KanataConfigGenerator` and `AnthropicConfigRepairService` are implemented
- ✅ **API Key Retrieval**: Checks environment variable first, then Keychain
- ✅ **Fallback Behavior**: Falls back to basic generation if API unavailable
- ❌ **UI for Key Management**: No user interface for storing API key in Keychain
- ❌ **User Documentation**: No clear explanation of what AI does, costs, or limitations
- ❌ **User Messaging**: No clear indicators when AI is unavailable or what limitations apply

## Required Components

### 1. Keychain Service Extension

**File**: `Sources/KeyPathAppKit/Services/KeychainService.swift`

Add methods for Claude API key storage:

```swift
// MARK: - Claude API Key Storage

private let claudeAPIKeyAccount = "claude-api-key"

/// Store Claude API key securely in Keychain
nonisolated func storeClaudeAPIKey(_ key: String) throws {
    let keyData = key.data(using: .utf8) ?? Data()
    
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: claudeAPIKeyAccount,
        kSecValueData as String: keyData,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    // Delete existing item first
    SecItemDelete(query as CFDictionary)
    
    // Add new item
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeyPathError.permission(.keychainSaveFailed(status: Int(status)))
    }
    
    AppLogger.shared.log("🔐 [Keychain] Claude API key stored securely")
}

/// Retrieve Claude API key from Keychain
nonisolated func retrieveClaudeAPIKey() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: claudeAPIKeyAccount,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    if status == errSecItemNotFound {
        return nil
    }
    
    guard status == errSecSuccess,
          let data = result as? Data,
          let key = String(data: data, encoding: .utf8)
    else {
        return nil
    }
    
    return key
}

/// Delete Claude API key from Keychain
nonisolated func deleteClaudeAPIKey() throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: claudeAPIKeyAccount
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeyPathError.permission(.keychainDeleteFailed(status: Int(status)))
    }
    
    AppLogger.shared.log("🔐 [Keychain] Claude API key deleted")
}

/// Check if Claude API key is stored
var hasClaudeAPIKey: Bool {
    retrieveClaudeAPIKey() != nil
}
```

**No separate PricingService needed** - Pricing constants are in the `estimateCost()` function.

```swift
import Foundation

/// Service for managing Anthropic API pricing for cost estimates
/// 
/// IMPORTANT LIMITATIONS:
/// - ❌ Anthropic does NOT provide a public pricing API endpoint
/// - ❌ No endpoint like `api.anthropic.com/v1/pricing` exists
/// - ⚠️ Cost API (`/v1/organizations/cost_report`) requires Admin API key + organization account
/// - ✅ We track token usage accurately (from API responses)
/// - ⚠️ Pricing is estimated using cached defaults (updated with app releases)
/// 
/// Strategy:
/// 1. Use cached defaults (updated with each app release)
/// 2. Allow manual override via UserDefaults (for power users)
/// 3. Link to Anthropic pricing page for current rates
/// 4. Track token usage accurately (we get this from API responses)
/// 
/// FUTURE POSSIBILITIES (not recommended):
/// - Could scrape/parse pricing page HTML (fragile, breaks easily)
/// - Could use third-party pricing aggregator (if one exists)
/// - Could parse JSON-LD structured data from pricing page (if Anthropic adds it)
/// - None of these are reliable enough for production use
@MainActor
public class PricingService {
    public static let shared = PricingService()
    
    private struct Pricing: Codable {
        let model: String
        let inputPricePerMillion: Double
        let outputPricePerMillion: Double
        let lastUpdated: Date
        let source: String // "default", "manual", "cached"
    }
    
    private var cachedPricing: Pricing?
    private let cacheKey = "KeyPath.AI.CachedPricing"
    
    private init() {
        loadCachedPricing()
    }
    
    /// Get current pricing (from cache, manual override, or defaults)
    /// Returns pricing for Claude 3.5 Sonnet (default model)
    public func getCurrentPricing() async -> (inputPricePerMillion: Double, outputPricePerMillion: Double) {
        // Check for manual override first (user-set)
        if let override = getManualOverride() {
            return override
        }
        
        // Check if cache is valid (from previous app version or manual update)
        if let cached = cachedPricing {
            return (cached.inputPricePerMillion, cached.outputPricePerMillion)
        }
        
        // Return defaults (updated with app releases)
        return getDefaultPricing()
    }
    
    /// Default pricing (Claude 3.5 Sonnet as of Dec 2024)
    /// ⚠️ UPDATE THESE DEFAULTS WHEN RELEASING NEW APP VERSIONS
    /// Check https://www.anthropic.com/pricing for current rates
    private func getDefaultPricing() -> (inputPricePerMillion: Double, outputPricePerMillion: Double) {
        // Claude 3.5 Sonnet pricing (as of Dec 2024)
        return (inputPricePerMillion: 3.0, outputPricePerMillion: 15.0)
    }
    
    /// Manual override via UserDefaults (for power users who want to update pricing)
    /// Set via: UserDefaults.standard.set(["input": 3.0, "output": 15.0], forKey: "KeyPath.AI.ManualPricing")
    private func getManualOverride() -> (inputPricePerMillion: Double, outputPricePerMillion: Double)? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "KeyPath.AI.ManualPricing"),
              let input = dict["input"] as? Double,
              let output = dict["output"] as? Double else {
            return nil
        }
        return (inputPricePerMillion: input, outputPricePerMillion: output)
    }
    
    /// Load cached pricing from UserDefaults
    private func loadCachedPricing() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let pricing = try? JSONDecoder().decode(Pricing.self, from: data) else {
            return
        }
        cachedPricing = pricing
    }
    
    /// Update pricing cache (for manual updates or future API integration)
    public func updatePricing(input: Double, output: Double, model: String = "claude-3-5-sonnet-20241022", source: String = "manual") {
        let pricing = Pricing(
            model: model,
            inputPricePerMillion: input,
            outputPricePerMillion: output,
            lastUpdated: Date(),
            source: source
        )
        cachedPricing = pricing
        
        if let data = try? JSONEncoder().encode(pricing) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        
        AppLogger.shared.log("💰 [PricingService] Updated pricing: Input $\(input)/1M, Output $\(output)/1M (source: \(source))")
    }
    
    /// Get pricing info for display
    public func getPricingInfo() -> String {
        let pricing = await getCurrentPricing()
        return "Input: $\(String(format: "%.2f", pricing.inputPricePerMillion))/1M tokens, Output: $\(String(format: "%.2f", pricing.outputPricePerMillion))/1M tokens"
    }
    
    /// Get pricing source for display (to show if using defaults vs manual)
    public func getPricingSource() -> String {
        if getManualOverride() != nil {
            return "Manual override"
        }
        if let cached = cachedPricing {
            return "Cached (\(cached.source))"
        }
        return "Default (app version)"
    }
**File**: `Sources/KeyPathAppKit/Services/AI/APIKeyValidator.swift` (new file)

Add API key validation before storing:

```swift
import Foundation

/// Validates Anthropic API keys by making a test request
public actor APIKeyValidator {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    
    /// Validate an API key by making a minimal test request
    /// Returns true if key is valid, throws error if invalid
    public func validateAPIKey(_ key: String) async throws -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(key, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Minimal test request - just check auth, don't actually generate
        let requestBody: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 10, // Minimal tokens for validation
            "messages": [
                [
                    "role": "user",
                    "content": "test" // Minimal content
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "APIKeyValidator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response from API"]
            )
        }
        
        // 200-299 = valid key, 401 = invalid key, other = network/API error
        if 200...299 ~= httpResponse.statusCode {
            return true
        } else if httpResponse.statusCode == 401 {
            throw NSError(
                domain: "APIKeyValidator",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Invalid API key. Please check your key and try again."]
            )
        } else {
            throw NSError(
                domain: "APIKeyValidator",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API request failed (status \(httpResponse.statusCode))"]
            )
        }
    }
}
```

**File**: `Sources/KeyPathAppKit/Services/AI/BiometricAuthService.swift` (new file)

Add biometric authentication before expensive API calls:

```swift
import Foundation
import LocalAuthentication

/// Service for biometric authentication before expensive API operations
@MainActor
public class BiometricAuthService {
    public static let shared = BiometricAuthService()
    
    private let context = LAContext()
    private var lastAuthTime: Date?
    private let authTimeout: TimeInterval = 300 // 5 minutes - re-auth after this
    
    private init() {}
    
    /// Check if biometric authentication is available
    public func isBiometricAvailable() -> Bool {
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return available
    }
    
    /// Authenticate user with biometrics before expensive operation
    /// Returns true if authenticated, false if cancelled, throws on error
    public func authenticate(reason: String = "Authenticate to use AI config generation (this will use your API quota and cost money)") async throws -> Bool {
        // Check if we recently authenticated (within timeout window)
        if let lastAuth = lastAuthTime,
           Date().timeIntervalSince(lastAuth) < authTimeout {
            return true
        }
        
        // Check availability
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fallback: if biometrics unavailable, allow with password prompt
            return try await authenticateWithPassword(reason: reason)
        }
        
        // Perform biometric authentication
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            
            if success {
                lastAuthTime = Date()
            }
            
            return success
        } catch let authError as LAError {
            switch authError.code {
            case .userCancel, .userFallback:
                return false // User cancelled
            case .biometryNotAvailable:
                // Fallback to password
                return try await authenticateWithPassword(reason: reason)
            default:
                throw authError
            }
        }
    }
    
    /// Fallback to password authentication if biometrics unavailable
    private func authenticateWithPassword(reason: String) async throws -> Bool {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // If no auth available at all, allow (user can disable in settings)
            return true
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            
            if success {
                lastAuthTime = Date()
            }
            
            return success
        } catch {
            return false
        }
    }
    
    /// Clear authentication cache (force re-auth on next call)
    public func clearAuthCache() {
        lastAuthTime = nil
        context.invalidate()
    }
}
```

**Update**: `Sources/KeyPathAppKit/Services/KanataConfigGenerator.swift`

Add biometric check before API call:

```swift
private func callClaudeAPIDirectly(prompt: String) async throws -> String {
    // Check for API key
    guard let apiKey = getClaudeAPIKey() else {
        throw NSError(
            domain: "ClaudeAPI", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Claude API key not found. Set ANTHROPIC_API_KEY environment variable or store in Keychain."
            ]
        )
    }
    
    // Biometric authentication before expensive API call
    // Check user preference first
    let requireBiometric = UserDefaults.standard.bool(forKey: "KeyPath.AI.RequireBiometricAuth")
    
    if requireBiometric {
        let authService = await BiometricAuthService.shared
        let authenticated = try await authService.authenticate(
            reason: "This AI generation will use your Anthropic API quota and cost approximately $0.01-0.03. Authenticate to proceed?"
        )
        
        guard authenticated else {
            throw NSError(
                domain: "ClaudeAPI", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Authentication cancelled"]
            )
        }
    }
    
    // Continue with API call...
}
```

### 2. Settings UI - AI Config Generation Section

**File**: `Sources/KeyPathAppKit/UI/SettingsView.swift`

Add new section in `GeneralSettingsTabView`:

```swift
// AI Config Generation Section
VStack(alignment: .leading, spacing: 8) {
    Text("AI Config Generation")
        .font(.headline)
        .foregroundColor(.secondary)
    
    // Status indicator
    HStack(spacing: 8) {
        Image(systemName: hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .foregroundColor(hasAPIKey ? .green : .orange)
        Text(hasAPIKey ? "API Key Configured" : "API Key Not Configured")
            .font(.body)
    }
    
    // Description
    Text("Optional: Use Claude AI to generate complex key mappings (sequences, chords, macros). Without an API key, KeyPath uses basic generation for simple mappings only.")
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    
    // API Key Input (SecureTextField)
    HStack {
        SecureField("sk-ant-...", text: $apiKeyInput)
            .textFieldStyle(.roundedBorder)
            .disabled(isSavingKey)
        
        if hasAPIKey {
            Button("Remove") {
                removeAPIKey()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button("Save") {
                saveAPIKey()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(apiKeyInput.isEmpty || isSavingKey)
        }
    }
    
    // Security note
    HStack(spacing: 6) {
        Image(systemName: "lock.shield.fill")
            .foregroundColor(.green)
            .font(.caption)
        Text("Stored securely in macOS Keychain")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    
    // Biometric authentication toggle
    Toggle(isOn: Binding(
        get: { UserDefaults.standard.bool(forKey: "KeyPath.AI.RequireBiometricAuth") },
        set: { UserDefaults.standard.set($0, forKey: "KeyPath.AI.RequireBiometricAuth") }
    )) {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "faceid")
                    .foregroundColor(.blue)
                Text("Require authentication before AI generation")
                    .font(.body)
            }
            Text("Uses Touch ID or password to confirm before each API call. Prevents accidental charges.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .toggleStyle(.switch)
    .accessibilityIdentifier("settings-ai-require-biometric-toggle")
    
    // Cost tracking display
    if let costHistory = UserDefaults.standard.array(forKey: "KeyPath.AI.CostHistory") as? [[String: Any]],
       !costHistory.isEmpty {
        let totalCost = costHistory.compactMap { $0["estimated_cost"] as? Double }.reduce(0, +)
        let recentCosts = costHistory.suffix(10).compactMap { $0["estimated_cost"] as? Double }
        let recentTotal = recentCosts.reduce(0, +)
        
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage Tracking")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Estimated Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(String(format: "%.4f", totalCost))")
                        .font(.body.weight(.semibold))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last 10 Calls")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(String(format: "%.4f", recentTotal))")
                        .font(.body.weight(.semibold))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Calls")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(costHistory.count)")
                        .font(.body.weight(.semibold))
                }
            }
            
            Text("⚠️ These are estimates based on token usage. Actual costs may vary. Check your Anthropic dashboard for exact charges.")
                .font(.caption2)
                .foregroundColor(.orange)
                .italic()
            
            Link("View Current Anthropic Pricing →", destination: URL(string: "https://www.anthropic.com/pricing")!)
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(.top, 2)
            
            Button("Clear History") {
                UserDefaults.standard.removeObject(forKey: "KeyPath.AI.CostHistory")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("settings-ai-clear-cost-history-button")
        }
        .padding(.top, 8)
    }
    
    // Info link
    Link("Get API Key from Anthropic", destination: URL(string: "https://console.anthropic.com/")!)
        .font(.caption)
        .foregroundColor(.blue)
    
    // Cost disclaimer
    DisclosureGroup("Cost Information") {
        VStack(alignment: .leading, spacing: 4) {
            Text("• Rough estimate: ~$0.01-0.03 per complex mapping")
            Text("• Costs vary based on usage and Anthropic's pricing")
            Text("• We don't track or manage costs - check Anthropic's dashboard")
            Text("• Simple mappings (single key) are always free (no API call)")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    // Limitations without AI
    DisclosureGroup("Limitations Without AI") {
        VStack(alignment: .leading, spacing: 4) {
            Text("Without an API key, KeyPath can only generate:")
            Text("• Single key → single key mappings")
            Text("• Basic modifier combinations")
            Text("")
            Text("Complex features require AI:")
            Text("• Multi-key sequences (e.g., 'jk' → Escape)")
            Text("• Complex chords with multiple modifiers")
            Text("• Macros and timing-sensitive mappings")
            Text("• Advanced Kanata syntax patterns")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}
```

### 3. User Documentation

**File**: `docs/guides/ai-config-generation.md`

Create comprehensive guide covering:

1. **What is AI Config Generation?**
   - Explains that AI helps generate complex Kanata configs
   - When it's used vs. basic generation

2. **Why is it Optional?**
   - KeyPath works completely offline by default
   - AI only used for complex mappings
   - Simple mappings never require API calls

3. **How to Get Started**
   - Step-by-step: Get API key from Anthropic
   - How to add it in Settings (stored securely in macOS Keychain)
   - How to verify it's working
   - Privacy: API key is stored securely in macOS Keychain, only sent to Anthropic's API

4. **Cost Information**
   - Rough estimates (with disclaimer that costs change)
   - Link to Anthropic pricing page
   - Note that we don't track costs

5. **Limitations Without AI**
   - What works: Simple mappings
   - What doesn't: Complex sequences, chords, macros
   - Examples of each

6. **Cost Tracking**
   - How costs are calculated (token usage)
   - Where to see cost history (Settings)
   - How to clear cost history
   - Disclaimer: estimates only, check Anthropic dashboard for exact charges

7. **Troubleshooting**
   - API key not working
   - Fallback behavior
   - How to check if AI was used
   - How to view cost history

### 4. First-Time API Key Dialog

**File**: `Sources/KeyPathAppKit/UI/Dialogs/AIKeyRequiredDialog.swift` (new file)

When a user tries to create a complex mapping (sequence/chord/macro) and no API key is available, show a modal dialog:

```swift
import SwiftUI

/// Dialog shown when user attempts complex mapping without API key configured
struct AIKeyRequiredDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyInput: String = ""
    @State private var isSaving: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingCostInfo: Bool = false
    
    let onSave: (String) async throws -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("AI Config Generation")
                    .font(.title2.weight(.semibold))
                
                Text("This mapping requires AI-powered generation.\nAdd your Anthropic API key to enable advanced features.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Cost awareness
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundColor(.orange)
                    Text("Each generation costs ~$0.01-0.03. We'll show you the exact cost after.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // API Key Input Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anthropic API Key")
                            .font(.headline)
                        
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isSaving)
                            .accessibilityIdentifier("ai-key-dialog-api-key-field")
                        
                        HStack {
                            Link("Get API Key from Anthropic →", destination: URL(string: "https://console.anthropic.com/")!)
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Spacer()
                        }
                        
                    // Security note
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Your API key will be stored securely in macOS Keychain")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    
                    // Validation note
                    Text("We'll validate your key before saving")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                    }
                    
                    // Cost Information
                    DisclosureGroup(isExpanded: $showingCostInfo) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• Rough estimate: ~$0.01-0.03 per complex mapping")
                            Text("• Costs vary - check Anthropic's pricing page")
                            Text("• Simple mappings are always free (no API call)")
                            Text("• We don't track costs - check your Anthropic dashboard")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    } label: {
                        Text("Cost Information")
                            .font(.subheadline)
                    }
                    
                    // Limitations
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Without an API key, KeyPath can only generate:")
                            Text("• Single key → single key mappings")
                            Text("• Basic modifier combinations")
                            Text("")
                            Text("Complex features require AI:")
                            Text("• Multi-key sequences (e.g., 'jk' → Escape)")
                            Text("• Complex chords with multiple modifiers")
                            Text("• Macros and timing-sensitive mappings")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    } label: {
                        Text("Limitations Without AI")
                            .font(.subheadline)
                    }
                    
            // Cost awareness note
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundColor(.orange)
                    Text("This will use your API quota")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Each complex mapping costs approximately $0.01-0.03. We'll show you the exact cost after generation.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Link to check actual pricing
                Link("Check current Anthropic pricing →", destination: URL(string: "https://www.anthropic.com/pricing")!)
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
                    
                    // Error message
                    if showingError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer buttons
            HStack(spacing: 12) {
                Button("Skip for Now") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("ai-key-dialog-skip-button")
                
                Spacer()
                
                Button("Save & Enable") {
                    Task {
                        await saveAPIKey()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.isEmpty || isSaving)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("ai-key-dialog-save-button")
                .help("Save API key and enable AI generation. You'll be asked to authenticate before each generation (costs money).")
            }
            .padding(16)
        }
        .frame(width: 520, height: 600)
        .overlay(alignment: .topTrailing) {
            Button(action: {
                onDismiss()
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityIdentifier("ai-key-dialog-close-button")
            .accessibilityLabel("Close")
        }
    }
    
    private func saveAPIKey() async {
        isSaving = true
        showingError = false
        
        // Validate API key before saving
        let validator = APIKeyValidator()
        do {
            let isValid = try await validator.validateAPIKey(apiKeyInput)
            if isValid {
                try await onSave(apiKeyInput)
                dismiss()
            }
        } catch {
            // Show validation error
            if let nsError = error as NSError?, nsError.domain == "APIKeyValidator" {
                errorMessage = nsError.localizedDescription
            } else {
                errorMessage = "Failed to validate API key: \(error.localizedDescription)"
            }
            showingError = true
        }
        
        isSaving = false
    }
}
```

**Usage in Views**:

```swift
// In MapperView or ContentView
.sheet(isPresented: $showingAIKeyDialog) {
    AIKeyRequiredDialog(
        onSave: { apiKey in
            try KeychainService.shared.storeClaudeAPIKey(apiKey)
            // Mark dialog as dismissed
            UserDefaults.standard.set(true, forKey: "KeyPath.AI.HasDismissedKeyDialog")
        },
        onDismiss: {
            // Mark dialog as dismissed so it doesn't show again
            UserDefaults.standard.set(true, forKey: "KeyPath.AI.HasDismissedKeyDialog")
        }
    )
    .customizeSheetWindow()
}
```

**Trigger Logic**:

1. **Helper function to check if mapping is complex**:
   ```swift
   // In KanataConfigGenerator or shared utility
   func isComplexMapping(input: KeySequence, output: KeySequence) -> Bool {
       // Complex if:
       // - Multiple keys in sequence
       // - Modifiers present
       // - More than simple single-key mapping
       return input.keys.count > 1 
           || output.keys.count > 1
           || !input.keys.first?.modifiers.isEmpty ?? false
           || !output.keys.first?.modifiers.isEmpty ?? false
   }
   ```

2. **MapperViewModel.save()** - Check if complex mapping and no API key:
   ```swift
   @State private var showingAIKeyDialog = false
   
   func save(kanataManager: RuntimeCoordinator) async {
       guard let inputSeq = inputSequence,
             let outputSeq = outputSequence else { return }
       
       let isComplex = isComplexMapping(inputSeq, outputSeq)
       let hasAPIKey = KeychainService.shared.hasClaudeAPIKey() 
           || ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil
       let hasDismissedDialog = UserDefaults.standard.bool(forKey: "KeyPath.AI.HasDismissedKeyDialog")
       
       if isComplex && !hasAPIKey && !hasDismissedDialog {
           // Show dialog - don't proceed with save yet
           await MainActor.run {
               showingAIKeyDialog = true
           }
           return
       }
       
       // If dismissed but no key, proceed with basic generation
       if isComplex && !hasAPIKey && hasDismissedDialog {
           AppLogger.shared.log("⚠️ [Mapper] Complex mapping but AI unavailable - using basic generation")
       }
       
       // Continue with save (will use basic generation if no API key)...
   }
   ```

3. **RecordingCoordinator.saveMapping()** - Similar check before complex path:
   ```swift
   @State private var showingAIKeyDialog = false
   
   // After detecting complex mapping (around line 191)
   let hasAPIKey = KeychainService.shared.hasClaudeAPIKey() 
       || ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil
   let hasDismissedDialog = UserDefaults.standard.bool(forKey: "KeyPath.AI.HasDismissedKeyDialog")
   
   if isComplex && !hasAPIKey && !hasDismissedDialog {
       await MainActor.run {
           showingAIKeyDialog = true
       }
       return
   }
   
   // If dismissed but no key, proceed with basic generation
   if isComplex && !hasAPIKey && hasDismissedDialog {
       AppLogger.shared.log("⚠️ [Recording] Complex mapping but AI unavailable - using basic generation")
   }
   ```

4. **Dialog completion** - After saving key, retry the save:
   ```swift
   // In the view that shows the dialog
   .sheet(isPresented: $showingAIKeyDialog) {
       AIKeyRequiredDialog(
           onSave: { apiKey in
               try KeychainService.shared.storeClaudeAPIKey(apiKey)
               // Retry the save operation
               await viewModel.save(kanataManager: kanataManager)
           },
           onDismiss: {
               UserDefaults.standard.set(true, forKey: "KeyPath.AI.HasDismissedKeyDialog")
               // Proceed with basic generation
               await viewModel.save(kanataManager: kanataManager)
           }
       )
       .customizeSheetWindow()
   }
   ```

### 5. User Messaging in UI

**When AI is unavailable:**

1. **Mapper View** - Show subtle indicator (only if user dismissed dialog):
   ```swift
   if !hasAPIKey && isComplexMapping && hasDismissedDialog {
       HStack(spacing: 4) {
           Image(systemName: "info.circle")
               .foregroundColor(.orange)
           Text("Complex mapping - AI unavailable, using basic generation")
               .font(.caption)
               .foregroundColor(.secondary)
       }
   }
   ```

2. **Recording Coordinator** - Log message when falling back:
   ```swift
   AppLogger.shared.log("⚠️ [Recording] Complex mapping detected but AI unavailable - using basic generation")
   ```

3. **Settings** - Clear status indicator (already planned above)

### 5. Update Existing Services

**File**: `Sources/KeyPathAppKit/Services/KanataConfigGenerator.swift`

Update `getClaudeAPIKey()` to use `KeychainService`:

```swift
private func getClaudeAPIKey() -> String? {
    // First try environment variable (for developers)
    if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
        return envKey
    }
    
    // Then try Keychain (for end users)
    return KeychainService.shared.retrieveClaudeAPIKey()
}
```

Same update for `AnthropicConfigRepairService`.

### 6. Update FAQ

**File**: `docs/faq.md`

Add section:

```markdown
## AI Config Generation

**Q: Do I need an API key to use KeyPath?**
A: No. KeyPath works completely offline. An API key is only needed for AI-powered generation of complex key mappings (sequences, chords, macros). Simple single-key mappings work without any API key.

**Q: How much does AI config generation cost?**
A: Rough estimates: ~$0.01-0.03 per complex mapping. Costs vary based on Anthropic's pricing. We don't track or manage costs - check your Anthropic dashboard. Simple mappings are always free (no API call).

**Q: What are the limitations without an API key?**
A: Without an API key, you can only create simple mappings (single key → single key). Complex features like multi-key sequences, complex chords, and macros require AI generation.

**Q: How do I get an API key?**
A: Sign up at https://console.anthropic.com/ and create an API key. Then add it in KeyPath Settings → General → AI Config Generation. Your API key is stored securely in macOS Keychain.

**Q: Is my API key secure?**
A: Yes. Your API key is stored securely in macOS Keychain using the same security system that protects your passwords. It's never stored in plain text or transmitted anywhere except to Anthropic's API when generating configs.

**Q: Why does it ask for Touch ID/Face ID before generating configs?**
A: AI config generation uses your API quota and costs money (~$0.01-0.03 per complex mapping). Biometric authentication ensures you intentionally authorize each API call and prevents accidental charges. You can disable this in Settings → General → AI Config Generation, but we recommend keeping it enabled.

**Q: Can I see how much I've spent?**
A: Yes! KeyPath tracks estimated costs based on token usage. View your cost history in Settings → General → AI Config Generation. Note: These are estimates based on cached pricing - check your Anthropic dashboard for exact charges. Pricing defaults are updated with each app release, and power users can override pricing in Advanced settings.

**Q: How accurate are the cost estimates?**
A: Estimates are based on token usage and hardcoded pricing (updated with app releases). Actual costs may vary if Anthropic changes pricing between releases. For exact charges, check your Anthropic dashboard. We track token usage accurately, but pricing is an estimate.

**Q: Can I get my actual usage/costs from Anthropic?**
A: Yes! Anthropic provides usage data in their dashboard at https://console.anthropic.com/. KeyPath shows estimates based on token counts, but Anthropic's dashboard shows your actual billed amounts. We don't query Anthropic's API for usage (they don't provide a public usage endpoint for individual users), so estimates are based on token counts from API responses.
```

## Implementation Order

1. **Phase 1: Keychain Service & Validation** (Foundation)
   - Extend `KeychainService` with Claude API key methods
   - Create `APIKeyValidator` to validate keys before storing
   - Create `BiometricAuthService` for authentication before expensive calls
   - Update `KanataConfigGenerator` and `AnthropicConfigRepairService` to use KeychainService

2. **Phase 2: First-Time Dialog** (Proactive UX)
   - Create `AIKeyRequiredDialog` component with SecureField
   - Add API key validation before saving
   - Add detection logic in `MapperViewModel` and `RecordingCoordinator`
   - Track dismissal preference
   - Link to Anthropic console

3. **Phase 3: Settings UI** (User Interface)
   - Add AI Config Generation section to General Settings
   - Implement SecureField for API key input
   - Add validation before saving
   - Add biometric authentication toggle (default: enabled)
   - Add status indicators and info sections
   - Show security messaging about Keychain storage

4. **Phase 4: Biometric Integration** (Cost Protection)
   - Integrate biometric auth before API calls in `KanataConfigGenerator`
   - Add authentication timeout (5 minutes) to avoid repeated prompts
   - Handle fallback to password if biometrics unavailable
   - Respect user preference (can disable in Settings)

5. **Phase 5: Documentation** (User Education)
   - Create `ai-config-generation.md` guide
   - Update FAQ with security and cost information
   - Explain biometric authentication feature
   - Add links from Settings UI and dialog to docs

6. **Phase 6: User Messaging** (UX Polish)
   - Add indicators in Mapper views when AI unavailable (if dialog dismissed)
   - Improve logging messages
   - Add helpful tooltips
   - Show authentication prompt with clear cost messaging

## Testing Checklist

- [ ] **SecureField is used for API key input** (not regular TextField)
- [ ] **API key validation works before saving**
- [ ] **Invalid API keys show clear error messages**
- [ ] **Valid API keys are stored successfully**
- [ ] **Biometric authentication prompts before API calls** (if enabled)
- [ ] **Biometric prompt clearly explains cost** ("will use your API quota and cost money")
- [ ] **Biometric auth respects timeout** (doesn't prompt repeatedly within 5 min)
- [ ] **Password fallback works** if biometrics unavailable
- [ ] **User can disable biometric auth** in Settings
- [ ] **Cost tracking works** (extracts usage from API response)
- [ ] **Cost history displays correctly** in Settings
- [ ] **Cost estimates are accurate** (based on token usage)
- [ ] **Cost disclaimer shown** (estimates only, check Anthropic dashboard)
- [ ] API key can be saved to Keychain via Settings
- [ ] API key can be saved to Keychain via first-time dialog
- [ ] API key can be retrieved and used for generation
- [ ] API key can be removed from Keychain
- [ ] Environment variable still takes precedence
- [ ] Fallback to basic generation works when no key
- [ ] **First-time dialog appears when complex mapping attempted**
- [ ] **Dialog can save API key successfully**
- [ ] **Dialog can be dismissed (and doesn't reappear)**
- [ ] **Dialog link to Anthropic console works**
- [ ] **Dialog shows error if API key invalid**
- [ ] **Security messaging about Keychain is visible**
- [ ] Settings UI shows correct status
- [ ] Documentation is clear and helpful
- [ ] Cost information is accurate (check Anthropic pricing)
- [ ] Limitations are clearly explained
- [ ] Links to Anthropic console work

## Notes

- **Cost Tracking Limitations**:
  - ✅ **Token counts are accurate** - Extracted from API responses (`usage` object)
  - ⚠️ **Pricing is estimated** - Hardcoded constants (updated with app releases)
  - ❌ **No public pricing API** - Anthropic does NOT provide `api.anthropic.com/v1/pricing` or similar
  - ✅ **Solution**: 
    - Track token usage accurately (we get this from every API response)
    - Use hardcoded pricing constants (updated with each app release)
    - Link to Anthropic pricing page for current rates
    - Link to Anthropic dashboard for exact billed amounts
  - 📝 **Release Checklist**: Update `estimateCost()` pricing constants when releasing new app versions
  
- **Pricing Updates**:
  - Pricing constants in `estimateCost()` function (updated with app releases)
  - ⚠️ **Release Checklist**: Check https://www.anthropic.com/pricing and update constants before each release
  - Always link to Anthropic pricing page for current rates
  - Always link to Anthropic console for exact usage/billing
  
- **Cost Disclaimer**: Always emphasize that costs are estimates based on token usage and cached pricing. Actual costs may vary - check Anthropic dashboard for exact charges.
- **Privacy & Security**: 
  - ✅ **SecureField used for input** (not regular TextField) - prevents key from appearing in plain text
  - ✅ **API key validation** - validate key works before storing (prevents storing invalid keys)
  - ✅ **macOS Keychain storage** - same system that protects passwords
  - ✅ **Never stored in plain text** - Keychain encrypts at rest
  - ✅ **Never transmitted except to Anthropic's API** - only when generating configs
  - ✅ **Users can remove anytime** - from Settings or macOS Keychain Access
  - ✅ **Clear security messaging** - make this visible in dialog, settings UI, and documentation
  - ✅ **Biometric authentication** - Touch ID/Face ID before expensive API calls (cost protection)
  - ✅ **Authentication timeout** - 5-minute window to avoid repeated prompts
  - ✅ **Password fallback** - works even if biometrics unavailable
  - ✅ **User preference** - can disable biometric auth in Settings
  - Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - key only accessible when device unlocked
- **Optional Nature**: Emphasize repeatedly that this is completely optional - KeyPath works great without it for simple mappings.
- **Developer vs. User**: Environment variable is for developers, Keychain is for end users. Both work.
