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

            // Horizontal rule
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                html.append("<hr>")
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

        return html.joined(separator: "\n")
    }

    /// Wrap an HTML body fragment in a full HTML document with inline CSS.
    static func wrapInHTMLDocument(body: String, isDark: Bool) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root {
            --text: #3d3229;
            --text-secondary: #6b5d52;
            --bg: #faf6f0;
            --code-bg: rgba(139, 109, 75, 0.08);
            --border: rgba(139, 109, 75, 0.15);
            --link: #8b5e3c;
            --link-hover: #6b4226;
            --table-header-bg: rgba(139, 109, 75, 0.06);
            --heading: #4a3728;
            --accent: #c49a6c;
        }
        body.dark {
            --text: #e8ddd0;
            --text-secondary: #b0a090;
            --bg: #2a2420;
            --code-bg: rgba(200, 170, 130, 0.1);
            --border: rgba(200, 170, 130, 0.15);
            --link: #d4a574;
            --link-hover: #e8c098;
            --table-header-bg: rgba(200, 170, 130, 0.08);
            --heading: #e0cdb8;
            --accent: #c49a6c;
        }
        body {
            font-family: "Charter", "Georgia", "Times New Roman", serif;
            font-size: 14px;
            line-height: 1.65;
            color: var(--text);
            background: var(--bg);
            margin: 0;
            padding: 20px 28px;
            -webkit-font-smoothing: antialiased;
        }
        h1 {
            font-family: "Charter", "Georgia", serif;
            font-size: 22px;
            font-weight: 700;
            color: var(--heading);
            margin: 28px 0 10px;
            letter-spacing: -0.01em;
        }
        h2 {
            font-family: "Charter", "Georgia", serif;
            font-size: 17px;
            font-weight: 700;
            color: var(--heading);
            margin: 28px 0 8px;
            padding-bottom: 4px;
            border-bottom: 1px solid var(--border);
        }
        h3 {
            font-family: "Charter", "Georgia", serif;
            font-size: 15px;
            font-weight: 600;
            color: var(--heading);
            margin: 20px 0 6px;
        }
        p { margin: 8px 0; color: var(--text-secondary); }
        ul { margin: 8px 0; padding-left: 20px; }
        li { margin: 4px 0; color: var(--text-secondary); }
        a { color: var(--link); text-decoration: none; border-bottom: 1px solid transparent; }
        a:hover { color: var(--link-hover); border-bottom-color: var(--link-hover); }
        code {
            font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
            font-size: 12px;
            background: var(--code-bg);
            padding: 1px 5px;
            border-radius: 4px;
        }
        pre {
            background: var(--code-bg);
            border-radius: 8px;
            padding: 12px 16px;
            overflow-x: auto;
            margin: 12px 0;
        }
        pre code {
            background: none;
            padding: 0;
            font-size: 11.5px;
            line-height: 1.4;
        }
        hr {
            border: none;
            border-top: 1px solid var(--border);
            margin: 20px 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 12px 0;
            font-size: 12.5px;
        }
        th {
            text-align: left;
            font-weight: 600;
            padding: 6px 10px;
            background: var(--table-header-bg);
            border-bottom: 1px solid var(--border);
        }
        td {
            padding: 6px 10px;
            border-bottom: 1px solid var(--border);
            color: var(--text-secondary);
        }
        strong { color: var(--heading); font-weight: 600; }
        .help-img {
            max-width: 100%;
            height: auto;
            border-radius: 6px;
            margin: 16px 0;
            display: block;
        }
        /* External links get an arrow indicator */
        a[href^="http"]::after { content: " ↗"; font-size: 0.85em; }
        /* Internal cross-links styled as a nav card */
        .cross-link {
            display: block;
            padding: 10px 14px;
            margin: 12px 0;
            border-radius: 6px;
            background: var(--code-bg);
            border: 1px solid var(--border);
            text-decoration: none;
            color: var(--link);
            border-bottom: none;
        }
        .cross-link:hover { background: var(--table-header-bg); border-bottom: none; }
        .cross-link::after { content: " →"; }
        </style>
        </head>
        <body class="\(isDark ? "dark" : "")">
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
