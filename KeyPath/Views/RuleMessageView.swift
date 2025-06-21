import SwiftUI

struct RuleMessageView: View {
    let rule: KanataRule
    let onInstall: () -> Void
    @AppStorage("showKanataCode") private var showKanataCode = false
    @State private var showExplanation = false
    @State private var showCopiedMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Compact visual representation with code toggle
            VStack(alignment: .leading, spacing: 16) {
                CompactRuleVisualizer(
                    behavior: rule.visualization.behavior,
                    explanation: rule.explanation,
                    showCodeToggle: true,
                    onCodeToggle: {
                        if showKanataCode {
                            showExplanation = true
                        }
                    }
                )

                // Kanata code section (collapsible)
                if showKanataCode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kanata rule:")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        ZStack(alignment: .topTrailing) {
                            KanataSyntaxHighlightedView(code: rule.completeKanataConfig)
                                .frame(maxWidth: .infinity)

                            VStack(alignment: .trailing, spacing: 4) {
                                // Copied feedback message above buttons
                                if showCopiedMessage {
                                    Text("Copied")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(4)
                                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                                }

                                // Copy and Help buttons inside code area
                                HStack(spacing: 8) {
                                // Copy button
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(rule.completeKanataConfig, forType: .string)

                                    // Show "Copied to Clipboard" message
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showCopiedMessage = true
                                    }

                                    // Hide the message after 2 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            showCopiedMessage = false
                                        }
                                    }
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.title3)
                                        .foregroundColor(.primary)
                                        .fontWeight(.medium)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.clear)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                .help("Copy Kanata code to clipboard")

                                // Question mark button for explanation
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showExplanation.toggle()
                                    }
                                }) {
                                    Image(systemName: "questionmark.circle")
                                        .font(.title3)
                                        .foregroundColor(showExplanation ? .white : .primary)
                                        .fontWeight(.medium)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(showExplanation ?
                                              Color.orange :
                                              Color.clear)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    showExplanation ?
                                                    Color.clear :
                                                    Color.secondary.opacity(0.3),
                                                    lineWidth: 1
                                                )
                                        )
                                        .shadow(color: showExplanation ? Color.orange.opacity(0.3) : Color.clear, radius: 6, x: 0, y: 2)
                                )
                                .help("Show explanation of this Kanata rule")
                                }
                            }
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                        }

                        // Educational explanation section
                        if showExplanation {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Explanation:")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .padding(.top, 12)

                                Text(generateKanataExplanation(for: rule.visualization.behavior, config: rule.completeKanataConfig))
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                                    .textSelection(.enabled)

                                if let exampleCode = generateExampleCode(for: rule.visualization.behavior) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Example variations:")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)

                                        // Use matching syntax highlighting with vertical wrapping
                                        MultiLineKanataSyntaxView(code: exampleCode)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }

            // Install button
            Button(action: {
                DebugLogger.shared.log("🔧 DEBUG: Add Rule button clicked!")
                DebugLogger.shared.log("🔧 DEBUG: About to call onInstall() for rule: \(rule.explanation)")
                onInstall()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Rule")
                }
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.green)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Educational Content Generation

    private func generateKanataExplanation(for behavior: KanataBehavior, config: String) -> String {
        switch behavior {
        case .simpleRemap(let from, let toKey):
            return """
            🔄 This is a simple key remapping rule.  Here's how it works:

            • 🎯 **(defsrc \(from.lowercased()))** - This tells Kanata which key to intercept.  The **"defsrc"** section defines the source keys that Kanata will monitor.

            • ⚡ **(deflayer default \(toKey.lowercased()))** - This defines what happens when the key is pressed.  The **"deflayer"** section maps each source key to its replacement.

            ✨ When you press **\(from)**, Kanata will intercept it and send **\(toKey)** instead.  This happens at the operating system level, so it works in all applications.
            """

        case .tapHold(let key, let tap, let hold):
            return """
            ⏰ This is a tap-hold rule that gives one key two different behaviors:

            • 🎭 **(defalias th_\(key.lowercased()) (tap-hold 200 200 \(tap.lowercased()) \(hold.lowercased())))** - This creates an alias that defines the tap-hold behavior.  The two **"200"** values are timing thresholds in milliseconds.

            • 🎯 **(defsrc \(key.lowercased()))** - Tells Kanata to intercept the **\(key)** key.

            • ⚡ **(deflayer default @th_\(key.lowercased()))** - Uses the alias we created (note the **@** symbol).

            🔀 When you quickly tap **\(key)**, it acts like **\(tap)**.  When you hold it down, it acts like **\(hold)**.  The timing determines which behavior activates.
            """

        case .tapDance(_, let actions):
            let actionsText = actions.enumerated().map { _, action in
                "• 🔢 **\(action.tapCount) tap\(action.tapCount > 1 ? "s" : "")** = **\(action.action)**"
            }.joined(separator: "\n            ")

            return """
            💃 This is a tap-dance rule that performs different actions based on how many times you tap a key quickly:

            \(actionsText)

            ⚡ Kanata detects rapid successive taps and performs different actions based on the count.  There's a timeout period - if you wait too long between taps, it resets to single tap behavior.
            """

        case .sequence(let trigger, let sequence):
            return """
            📝 This is a sequence rule that types multiple keys when you press one trigger key:

            • 🎯 When you press **\(trigger)**, Kanata will automatically type: **\(sequence.joined(separator: " → "))**

            ✨ This is useful for:
            • Text expansion
            • Common phrases
            • Complex key combinations you use frequently
            """

        case .combo(let keys, let result):
            return """
            🎹 This is a chord/combo rule that activates when you press multiple keys simultaneously:

            • 🤝 Press **\(keys.joined(separator: " + "))** together to get: **\(result)**

            ⏱️ Key requirements:
            • All keys must be pressed within a short time window
            • Similar to how **Ctrl+C** works, but with your custom combinations
            • Great for creating shortcuts that don't conflict with existing ones
            """

        case .layer(let key, let layerName, let mappings):
            let mappingsText = mappings.map { "**\($0.key) → \($0.value)**" }.joined(separator: ", ")
            return """
            🎚️ This creates a layer that temporarily changes your keyboard layout:

            • 🔒 Hold **\(key)** to activate the **"\(layerName)"** layer
            • 🔄 While held, these keys change: \(mappingsText)

            🚀 Layers are powerful for creating:
            • Temporary number pads
            • Function key clusters
            • Navigation controls
            • Gaming mode layouts
            """
        }
    }

    private func generateExampleCode(for behavior: KanataBehavior) -> String? {
        switch behavior {
        case .simpleRemap:
            return """
            ;; Other simple remapping examples:
            (defsrc j k l)
            (deflayer default left down right)

            ;; This would remap J→Left, K→Down, L→Right
            """

        case .tapHold:
            return """
            ;; Other tap-hold examples:
            (defalias
              spc_sft (tap-hold 200 200 spc lsft)
              a_ctrl  (tap-hold 150 150 a lctl)
            )

            ;; Space becomes Shift when held
            ;; A becomes Ctrl when held
            """

        case .tapDance:
            return """
            ;; Tap-dance with more actions:
            (defalias
              td_esc (tap-dance 200 (
                esc        ;; 1 tap
                (layer-toggle nav)  ;; 2 taps
                (cmd "open -a Terminal")  ;; 3 taps
              ))
            )
            """

        default:
            return nil
        }
    }
}

// MARK: - Multi-Line Kanata Syntax View

struct MultiLineKanataSyntaxView: View {
    let code: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        highlightedCode
            .font(.system(.title3, design: .monospaced))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ?
                          Color(NSColor.textBackgroundColor) :
                          Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ?
                           Color.white.opacity(0.15) :
                           Color.black.opacity(0.15), lineWidth: 1)
            )
            .textSelection(.enabled)
    }

    private var highlightedCode: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(code.components(separatedBy: .newlines).indices, id: \.self) { lineIndex in
                let line = code.components(separatedBy: .newlines)[lineIndex]
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    syntaxHighlightedLine(line)
                } else {
                    Text(" ")
                        .font(.system(.title3, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syntaxHighlightedLine(_ line: String) -> some View {
        HStack(spacing: 0) {
            Text(createAttributedText(for: line))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func createAttributedText(for line: String) -> AttributedString {
        let tokens = tokenize(line)
        var attributedString = AttributedString()

        for token in tokens {
            var tokenText = AttributedString(token.text)
            tokenText.foregroundColor = color(for: token.type)
            attributedString.append(tokenText)
        }

        return attributedString
    }

    private func tokenize(_ code: String) -> [Token] {
        var tokens: [Token] = []
        var currentWord = ""
        var inString = false
        var inComment = false

        for char in code {
            if inComment {
                currentWord.append(char)
                if char == "\n" {
                    tokens.append(Token(text: currentWord, type: .comment))
                    currentWord = ""
                    inComment = false
                }
            } else if inString {
                currentWord.append(char)
                if char == "\"" && !currentWord.dropLast().hasSuffix("\\") {
                    tokens.append(Token(text: currentWord, type: .string))
                    currentWord = ""
                    inString = false
                }
            } else if char == "\"" {
                if !currentWord.isEmpty {
                    tokens.append(Token(text: currentWord, type: determineType(currentWord)))
                    currentWord = ""
                }
                currentWord.append(char)
                inString = true
            } else if char == ";" && !inString {
                if !currentWord.isEmpty {
                    tokens.append(Token(text: currentWord, type: determineType(currentWord)))
                    currentWord = ""
                }
                currentWord.append(char)
                inComment = true
            } else if char == "(" || char == ")" {
                if !currentWord.isEmpty {
                    tokens.append(Token(text: currentWord, type: determineType(currentWord)))
                    currentWord = ""
                }
                tokens.append(Token(text: String(char), type: .parenthesis))
            } else if char.isWhitespace {
                if !currentWord.isEmpty {
                    tokens.append(Token(text: currentWord, type: determineType(currentWord)))
                    currentWord = ""
                }
                tokens.append(Token(text: String(char), type: .whitespace))
            } else {
                currentWord.append(char)
            }
        }

        if !currentWord.isEmpty {
            tokens.append(Token(text: currentWord, type: determineType(currentWord)))
        }

        return tokens
    }

    private func determineType(_ word: String) -> TokenType {
        let keywords = ["defsrc", "deflayer", "defalias", "defcfg", "defseq", "defchords",
                       "tap-hold", "tap-dance", "multi-tap", "macro", "layer-toggle",
                       "layer-switch", "around", "cmd", "alt", "ctrl", "shift", "met"]

        if keywords.contains(word.lowercased()) {
            return .keyword
        } else if word.starts(with: "@") {
            return .alias
        } else if Int(word) != nil {
            return .number
        } else {
            return .identifier
        }
    }

    private func color(for type: TokenType) -> Color {
        switch type {
        case .keyword:
            return colorScheme == .dark ? Color.blue.opacity(0.9) : Color.blue
        case .string:
            return colorScheme == .dark ? Color.green.opacity(0.9) : Color(red: 0.0, green: 0.5, blue: 0.0)
        case .comment:
            return colorScheme == .dark ? Color.gray : Color.gray.opacity(0.8)
        case .parenthesis:
            return colorScheme == .dark ? Color.purple.opacity(0.8) : Color.purple
        case .number:
            return colorScheme == .dark ? Color.orange.opacity(0.9) : Color.orange.opacity(0.8)
        case .alias:
            return colorScheme == .dark ? Color.cyan : Color.cyan.opacity(0.8)
        case .identifier:
            return colorScheme == .dark ? Color.primary.opacity(0.9) : Color.primary
        case .whitespace:
            return Color.primary
        }
    }

    private struct Token {
        let text: String
        let type: TokenType
    }

    private enum TokenType {
        case keyword
        case string
        case comment
        case parenthesis
        case number
        case alias
        case identifier
        case whitespace
    }
}
