import Foundation
@testable import KeyPathAppKit
import XCTest

final class MarkdownToHTMLTests: XCTestCase {

    // MARK: - Headings

    func testH1() {
        let result = MarkdownToHTML.convert("# Hello")
        XCTAssertEqual(result, "<h1>Hello</h1>")
    }

    func testH2() {
        let result = MarkdownToHTML.convert("## Section")
        XCTAssertEqual(result, "<h2>Section</h2>")
    }

    func testH3() {
        let result = MarkdownToHTML.convert("### Subsection")
        XCTAssertEqual(result, "<h3>Subsection</h3>")
    }

    // MARK: - Inline formatting

    func testBold() {
        let result = MarkdownToHTML.convert("This is **bold** text")
        XCTAssertTrue(result.contains("<strong>bold</strong>"))
    }

    func testItalic() {
        let result = MarkdownToHTML.convert("This is *italic* text")
        XCTAssertTrue(result.contains("<em>italic</em>"))
    }

    func testInlineCode() {
        let result = MarkdownToHTML.convert("Use `tap-hold` here")
        XCTAssertTrue(result.contains("<code>tap-hold</code>"))
    }

    func testLink() {
        let result = MarkdownToHTML.convert("[Click here](https://example.com)")
        XCTAssertTrue(result.contains("<a href=\"https://example.com\">Click here</a>"))
    }

    // MARK: - Block elements

    func testBulletList() {
        let md = """
        - First item
        - Second item
        - Third item
        """
        let result = MarkdownToHTML.convert(md)
        XCTAssertTrue(result.contains("<ul>"))
        XCTAssertTrue(result.contains("<li>First item</li>"))
        XCTAssertTrue(result.contains("<li>Second item</li>"))
        XCTAssertTrue(result.contains("<li>Third item</li>"))
        XCTAssertTrue(result.contains("</ul>"))
    }

    func testFencedCodeBlock() {
        let md = """
        ```
        let x = 1
        let y = 2
        ```
        """
        let result = MarkdownToHTML.convert(md)
        XCTAssertTrue(result.contains("<pre><code>"))
        XCTAssertTrue(result.contains("let x = 1"))
        XCTAssertTrue(result.contains("</code></pre>"))
    }

    func testHorizontalRule() {
        let result = MarkdownToHTML.convert("---")
        XCTAssertEqual(result, "<hr>")
    }

    // MARK: - Tables

    func testPipeTable() {
        let md = """
        | Aspect | KeyPath | Karabiner |
        |---|---|---|
        | Config | Visual UI | JSON editing |
        """
        let result = MarkdownToHTML.convert(md)
        XCTAssertTrue(result.contains("<table>"))
        XCTAssertTrue(result.contains("<th>Aspect</th>"))
        XCTAssertTrue(result.contains("<td>Visual UI</td>"))
        XCTAssertTrue(result.contains("</table>"))
    }

    // MARK: - HTML escaping

    func testHTMLEscaping() {
        let result = MarkdownToHTML.convert("Use <div> & \"quotes\"")
        XCTAssertTrue(result.contains("&lt;div&gt;"))
        XCTAssertTrue(result.contains("&amp;"))
    }

    // MARK: - Internal help links

    func testHelpLinkRendersAsCrossLink() {
        let result = MarkdownToHTML.convert("[Advanced Techniques](help:advanced-hrm-techniques)")
        XCTAssertTrue(result.contains("class=\"cross-link\""))
        XCTAssertTrue(result.contains("href=\"keypath-help://advanced-hrm-techniques\""))
        XCTAssertTrue(result.contains("Advanced Techniques"))
    }

    func testExternalLinkNotAffectedByHelpHandling() {
        let result = MarkdownToHTML.convert("[Example](https://example.com)")
        XCTAssertFalse(result.contains("cross-link"))
        XCTAssertTrue(result.contains("href=\"https://example.com\""))
    }

    // MARK: - Document wrapping

    func testExternalLinkIndicatorCSS() {
        let html = MarkdownToHTML.wrapInHTMLDocument(body: "<p>test</p>", isDark: false)
        XCTAssertTrue(html.contains("a[href^=\"http\"]::after"))
        XCTAssertTrue(html.contains(".cross-link"))
    }

    func testWrapInHTMLDocumentLight() {
        let html = MarkdownToHTML.wrapInHTMLDocument(body: "<p>Hello</p>", isDark: false)
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<p>Hello</p>"))
        XCTAssertTrue(html.contains("body class=\"\""))
    }

    func testWrapInHTMLDocumentDark() {
        let html = MarkdownToHTML.wrapInHTMLDocument(body: "<p>Hello</p>", isDark: true)
        XCTAssertTrue(html.contains("body class=\"dark\""))
    }

    // MARK: - Paragraphs

    func testParagraph() {
        let result = MarkdownToHTML.convert("Just a paragraph.")
        XCTAssertEqual(result, "<p>Just a paragraph.</p>")
    }

    // MARK: - Combined elements

    func testListClosesBeforeHeading() {
        let md = """
        - item
        ## Heading
        """
        let result = MarkdownToHTML.convert(md)
        let ulClose = result.range(of: "</ul>")!.lowerBound
        let h2Open = result.range(of: "<h2>")!.lowerBound
        XCTAssertTrue(ulClose < h2Open, "List should close before heading")
    }

    func testCodeBlockPreservesContent() {
        let md = """
        ```
        ┌───┬───┐
        │ A │ B │
        └───┴───┘
        ```
        """
        let result = MarkdownToHTML.convert(md)
        // Box-drawing characters should be present inside the code block
        XCTAssertTrue(result.contains("┌───┬───┐"))
    }
}
