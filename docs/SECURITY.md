# KeyPath Security Implementation

## API Key Storage

KeyPath implements secure storage for Anthropic API keys using the following priority order:

1. **Environment Variable** (ANTHROPIC_API_KEY)
   - Highest priority
   - Useful for development and CI/CD environments
   - Not stored in source code

2. **macOS Keychain**
   - Secure encrypted storage
   - User-specific and protected by macOS security
   - Automatically migrates from UserDefaults if found

3. **UserDefaults** (Deprecated)
   - Only used for backwards compatibility
   - Automatically migrated to Keychain on first access
   - Removed after successful migration

## Security Features

### Keychain Storage
- API keys are stored in the macOS Keychain using `kSecClassGenericPassword`
- Access is restricted to when the device is unlocked (`kSecAttrAccessibleWhenUnlocked`)
- Keys are encrypted at rest by macOS
- User authentication required for access

### Environment Variable Support
- Allows secure configuration without storing keys in code
- Can be set in Xcode scheme for development
- Supports override through Settings UI

### No Source Code Storage
- API keys are never stored in source code
- `.gitignore` should exclude any local configuration files
- Environment variables keep keys out of version control

## Best Practices

1. **For Development**
   - Use environment variables set in Xcode scheme
   - Never commit API keys to git

2. **For Distribution**
   - Users enter their own API keys during onboarding
   - Keys stored securely in their personal Keychain
   - No shared or default keys included

3. **Key Rotation**
   - Users can update keys anytime through Settings
   - Old keys automatically replaced in Keychain
   - Clear override option to revert to environment variable

## Implementation Details

The security implementation consists of:

- `KeychainManager.swift`: Handles secure storage operations
- `AnthropicModelProvider.swift`: Checks keys in priority order
- `SettingsView.swift`: Secure key management UI
- `OnboardingView.swift`: Initial key setup with Keychain storage

All API key operations use the Keychain API for maximum security on macOS.