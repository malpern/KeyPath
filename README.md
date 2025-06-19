<div align="center">

# ⌨️ &nbsp;&nbsp;KeyPath

**Keyboard Remapping Made Simple**

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

## Overview

KeyPath is an intuitive macOS application that makes keyboard remapping accessible to everyone. Powered by AI, it translates natural language descriptions into powerful keyboard customizations using [Kanata](https://github.com/jtroo/kanata) under the hood.

## Features

- **Natural Language Input**: Describe your desired keyboard behavior in plain English
- **AI-Powered Translation**: Automatically converts descriptions to Kanata configuration rules
- **Visual Rule Preview**: See your remappings visualized before applying them
- **Instant Application**: Apply keyboard changes without restarting
- **Rule History**: Track and undo recent changes
- **Liquid Glass UI**: Beautiful, modern interface following Apple's latest design guidelines

## Examples

Simply describe what you want:

- "Make caps lock act as escape when tapped, control when held"
- "Swap command and option keys"
- "Create vim-style arrow keys with hjkl when holding space"
- "Make the right shift key type an underscore"

## Requirements

- macOS 14.0+ (optimized for macOS 26.0 Tahoe)
- [Kanata](https://github.com/jtroo/kanata) keyboard remapper
- Anthropic API key (for AI translation)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/malpern/KeyPath.git
```

2. Open the project in Xcode:
```bash
cd KeyPath
open KeyPath.xcodeproj
```

3. Build and run the application

4. Follow the in-app setup wizard to:
   - Install Kanata
   - Configure permissions
   - Add your Anthropic API key

## Usage

1. Launch KeyPath
2. Describe your desired keyboard remapping in the text field
3. Review the generated rule preview
4. Click "Apply" to activate the remapping
5. Use the History feature to undo changes if needed

## Architecture

KeyPath combines several technologies:

- **SwiftUI** with @Observable for modern, reactive UI
- **Anthropic Claude API** for natural language understanding
- **Kanata** for low-level keyboard remapping
- **Liquid Glass Effects** for visual polish

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available under the [MIT License](LICENSE).

## Acknowledgments

- Chat interface based on [Apple Intelligence Chat](https://github.com/PallavAg/Apple-Intelligence-Chat) by Pallav Agarwal
- Built with [Kanata](https://github.com/jtroo/kanata) by jtroo
- AI powered by [Anthropic Claude](https://www.anthropic.com/)
- Liquid Glass UI design inspired by Apple's WWDC 2025 guidelines
