# AI Config Generation

KeyPath can use Claude AI to generate complex Kanata keyboard configurations. This optional feature helps you create advanced mappings that would be difficult to write by hand.

## Overview

AI-powered config generation is useful for:

- **Key sequences**: Type "hello" with one key press
- **Chord combinations**: Press A+B together to trigger an action
- **Macros**: Complex multi-step keyboard actions
- **App-specific shortcuts**: Custom shortcuts for specific applications

**Simple single-key remaps work without AI** — only complex mappings require the API.

## Getting Started

### 1. Get an Anthropic API Key

1. Go to [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
2. Create an account if you don't have one
3. Generate a new API key (starts with `sk-ant-`)
4. Copy the key

### 2. Add Your API Key to KeyPath

**Option A: Settings UI**
1. Open KeyPath
2. Go to Settings → General
3. Find "AI Config Generation" section
4. Paste your API key and click "Save"

**Option B: Environment Variable (for developers)**
```bash
export ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### 3. Create a Complex Mapping

1. Open the Mapper (⌘M)
2. Record your input sequence
3. Record your output sequence
4. Click "Save Mapping"

If the mapping is complex, KeyPath will use AI to generate it automatically.

## Cost Information

AI config generation uses Claude 3.5 Sonnet and costs money per use:

| What | Estimated Cost |
|------|---------------|
| Single complex mapping | ~$0.01-0.03 |
| Simple single-key remap | Free (no API call) |

**Important notes:**
- Costs are estimates based on token usage
- Actual costs depend on Anthropic's current pricing
- Check your [Anthropic dashboard](https://console.anthropic.com/) for exact charges
- View [current Anthropic pricing](https://www.anthropic.com/pricing)

### Viewing Your Usage

1. Go to Settings → General → AI Config Generation
2. Click "View Usage History"
3. See estimated costs and token usage

## Security

### API Key Storage

Your API key is stored securely in the macOS Keychain:

- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Key is never sent anywhere except to Anthropic
- You can remove the key at any time in Settings

### Biometric Protection (Optional)

Enable Touch ID/Face ID before AI generation to:

- Protect against accidental API usage
- Confirm before incurring costs
- Add an extra layer of security

**You'll only be asked once per session** - after authenticating, all AI generations in that session proceed without additional prompts.

To enable:
1. Go to Settings → General → AI Config Generation
2. Toggle "Require [Touch ID/Face ID] before AI generation"

## Limitations

### Without an API Key

If you don't have an API key, KeyPath will:

- ✅ Work for simple single-key remaps
- ⚠️ Use basic generation for complex mappings (may not work for all cases)
- ❌ Not be able to generate sequences, chords, or macros

### What AI Can't Do

- Parse or modify existing Kanata configs
- Fix all possible configuration errors
- Guarantee 100% working configs (rare edge cases may need manual adjustment)

## Troubleshooting

### "Invalid API Key" Error

1. Check that your key starts with `sk-ant-`
2. Verify the key hasn't been revoked in Anthropic console
3. Try removing and re-adding the key

### "Authentication Cancelled" Error

You cancelled the biometric prompt. Either:
- Try again and authenticate
- Disable biometric requirement in Settings

### "API request failed" Error

1. Check your internet connection
2. Verify you have API credits in your Anthropic account
3. Check [Anthropic status page](https://status.anthropic.com/) for outages

## FAQ

**Q: Is the API key required?**
A: No. KeyPath works without an API key for simple mappings. AI is only needed for complex sequences, chords, and macros.

**Q: Is my API key secure?**
A: Yes. It's stored in macOS Keychain with the highest security level and only sent to Anthropic's API.

**Q: Can I use a different AI provider?**
A: Currently only Anthropic's Claude is supported. We chose Claude for its strong code generation capabilities.

**Q: What if Anthropic changes pricing?**
A: Our cost estimates are updated with each KeyPath release. Always check Anthropic's pricing page for current rates.
