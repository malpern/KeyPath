import Foundation

/// Pure markdown-to-HTML converter supporting a practical subset of markdown.
/// No external dependencies — just string processing.
enum MarkdownToHTML {
    // MARK: - Public API

    /// Convert a markdown string to an HTML body fragment.
    static func convert(_ markdown: String) -> String {
        var html: [String] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var inList = false
        var inCodeBlock = false
        var codeLines: [String] = []

        while i < lines.count {
            let line = lines[i]

            // Fenced code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html.append("<pre><code>\(codeLines.joined(separator: "\n"))</code></pre>")
                    codeLines = []
                    inCodeBlock = false
                } else {
                    if inList { html.append("</ul>"); inList = false }
                    inCodeBlock = true
                }
                i += 1
                continue
            }
            if inCodeBlock {
                codeLines.append(escapeHTML(line))
                i += 1
                continue
            }

            // Blockquotes (accumulate consecutive `> ` lines)
            if line.hasPrefix("> ") {
                if inList { html.append("</ul>"); inList = false }
                var blockLines: [String] = []
                while i < lines.count, lines[i].hasPrefix("> ") {
                    blockLines.append(String(lines[i].dropFirst(2)))
                    i += 1
                }
                html.append(renderBlockquote(blockLines))
                continue
            }

            // Close list if the current line is not a list item
            if inList, !line.hasPrefix("- ") {
                html.append("</ul>")
                inList = false
            }

            // Blank lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Horizontal rule — watercolor splotch divider
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                html.append("<div class=\"decor-divider\"><img src=\"decor-divider.png\" alt=\"\" class=\"decor-img\"></div>")
                i += 1
                continue
            }

            // Headings
            if line.hasPrefix("### ") {
                html.append("<h3>\(inlineFormat(String(line.dropFirst(4))))</h3>")
                i += 1
                continue
            }
            if line.hasPrefix("## ") {
                html.append("<h2>\(inlineFormat(String(line.dropFirst(3))))</h2>")
                i += 1
                continue
            }
            if line.hasPrefix("# ") {
                html.append("<h1>\(inlineFormat(String(line.dropFirst(2))))</h1>")
                i += 1
                continue
            }

            // Bullet lists
            if line.hasPrefix("- ") {
                if !inList {
                    html.append("<ul>")
                    inList = true
                }
                html.append("<li>\(inlineFormat(String(line.dropFirst(2))))</li>")
                i += 1
                continue
            }

            // Pipe tables
            if line.hasPrefix("|") {
                var tableLines: [String] = []
                while i < lines.count, lines[i].hasPrefix("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                html.append(renderTable(tableLines))
                continue
            }

            // Paragraph
            html.append("<p>\(inlineFormat(line))</p>")
            i += 1
        }

        if inList { html.append("</ul>") }
        if inCodeBlock {
            html.append("<pre><code>\(codeLines.joined(separator: "\n"))</code></pre>")
        }

        // End-of-page flourish
        html.append("<div class=\"decor-end\"><img src=\"decor-end.png\" alt=\"\" class=\"decor-img decor-end-img\"></div>")

        return html.joined(separator: "\n")
    }

    /// Wrap an HTML body fragment in a full HTML document with inline CSS.
    static func wrapInHTMLDocument(body: String, isDark _: Bool) -> String {
        let css: String = if let url = Bundle.module.url(forResource: "help-theme", withExtension: "css"),
                             let contents = try? String(contentsOf: url, encoding: .utf8)
        {
            contents
        } else {
            "/* help-theme.css not found — using fallback */\nbody { font-family: Georgia, serif; }"
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - Private Helpers

    /// Apply inline formatting: bold, italic, code, links.
    static func inlineFormat(_ text: String) -> String {
        var result = escapeHTML(text)

        // Code spans (must come before bold/italic to avoid conflicts)
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Bold
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic
        result = result.replacingOccurrences(
            of: "\\*(.+?)\\*",
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Images (must come before links to avoid ![alt](url) matching as link)
        result = result.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)",
            with: "<img src=\"$2\" alt=\"$1\" class=\"help-img\">",
            options: .regularExpression
        )

        // Internal help links (help:resource-name → keypath-help://resource-name)
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(help:([^)]+)\\)",
            with: "<a class=\"cross-link\" href=\"keypath-help://$2\">$1</a>",
            options: .regularExpression
        )

        // Links
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        return result
    }

    private static func renderBlockquote(_ lines: [String]) -> String {
        let content = lines.map { inlineFormat($0) }.joined(separator: "<br>")
        if content.hasPrefix("⚠️") || content.hasPrefix("&#x26A0;&#xFE0F;") {
            return "<div class=\"callout callout-warning\">\(content)</div>"
        } else if content.hasPrefix("💡") || content.hasPrefix("&#x1F4A1;") {
            return "<div class=\"callout callout-tip\">\(content)</div>"
        }
        return "<blockquote>\(content)</blockquote>"
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func renderTable(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }

        func parseCells(_ line: String) -> [String] {
            line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        var html = "<table>"

        // Header row
        let headers = parseCells(lines[0])
        html += "<thead><tr>"
        for h in headers {
            html += "<th>\(inlineFormat(h))</th>"
        }
        html += "</tr></thead>"

        // Skip separator row (line with dashes)
        let dataStart = lines.count > 1 && lines[1].contains("---") ? 2 : 1

        html += "<tbody>"
        for j in dataStart ..< lines.count {
            let cells = parseCells(lines[j])
            html += "<tr>"
            for cell in cells {
                html += "<td>\(inlineFormat(cell))</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"

        return html
    }
}
