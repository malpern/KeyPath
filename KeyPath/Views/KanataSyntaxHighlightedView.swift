import SwiftUI

struct KanataSyntaxHighlightedView: View {
    let code: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            highlightedCode
                .font(.system(.title3, design: .monospaced))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    }

    private var highlightedCode: some View {
        // Create attributed string for better text selection
        Text(createAttributedText())
            .textSelection(.enabled)
    }
    
    private func createAttributedText() -> AttributedString {
        let tokens = tokenize(code)
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

#Preview {
    VStack(spacing: 20) {
        KanataSyntaxHighlightedView(code: "(defsrc caps) (deflayer base esc)")
            .padding()

        KanataSyntaxHighlightedView(code: "(defsrc spc) (deflayer base (tap-hold 200 200 spc lsft))")
            .padding()

        KanataSyntaxHighlightedView(code: """
            ;; Multi-tap example
            (defsrc f)
            (deflayer base
              (tap-dance 200 (f (lctl f) (lgui f)))
            )
            """)
            .padding()
    }
    .frame(width: 600)
}
