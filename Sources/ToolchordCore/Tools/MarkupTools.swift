import Foundation

/// HTML to plain text, Markdown to HTML, and Markdown to plain text.
///
/// Markdown is parsed by Foundation (CommonMark with GitHub tables,
/// strikethrough, and autolinks) and rebuilt from its attributed runs in
/// ``MarkdownDocument``. Both plain-text converters lay out text with the
/// shared ``PlainTextWriter``.
public enum MarkupTools {
    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "html.plaintext",
            title: "Convert HTML to Plain Text",
            summary: "Strip tags and keep the readable text",
            group: .plainText,
            icon: .symbol("chevron.left.forwardslash.chevron.right"),
            aliases: ["html to text", "html to plain text", "strip html", "strip tags", "remove html tags", "extract text", "plain text"],
            options: [linksOption],
            copyNoun: "text",
            affinity: { $0.has(.html) ? 85 : 0 },
            evaluate: { evaluate($0, format: .htmlText) }
        ),
        ToolCommand(
            id: "markdown.html",
            title: "Render Markdown to HTML",
            summary: "CommonMark and GitHub tables to HTML",
            group: .markdown,
            icon: .glyph("M↓"),
            aliases: ["markdown to html", "md to html", "render markdown", "convert markdown", "commonmark", "gfm", "markdown html"],
            copyNoun: "HTML",
            affinity: { $0.has(.markdown) ? 90 : 0 },
            evaluate: { evaluate($0, format: .markdownHTML) }
        ),
        ToolCommand(
            id: "markdown.plaintext",
            title: "Convert Markdown to Plain Text",
            summary: "Remove Markdown syntax, keep the text",
            group: .markdown,
            icon: .glyph("M↓"),
            aliases: ["markdown to text", "markdown to plain text", "strip markdown", "remove markdown", "md to text", "plain text"],
            options: [linksOption],
            copyNoun: "text",
            affinity: { $0.has(.markdown) ? 80 : 0 },
            evaluate: { evaluate($0, format: .markdownText) }
        ),
    ]

    private static let linksOption = ToolOption.toggle("links", "Show link URLs", default: false)

    enum Format { case htmlText, markdownHTML, markdownText }

    static func evaluate(_ request: ToolRequest, format: Format) -> ToolResult {
        guard let text = request.input.text else { return .needsInput("Paste text to convert.") }
        if request.cancellation.isCancelled { return .cancelled }
        do {
            let output: String
            switch format {
            case .htmlText:
                let writer = PlainTextWriter(request: request)
                try HTMLTextConverter.convert(text, writer: writer, request: request)
                output = writer.finish()
            case .markdownHTML:
                output = try MarkdownHTMLRenderer.render(MarkdownDocument.parse(text, request: request), request: request)
            case .markdownText:
                let writer = PlainTextWriter(request: request)
                try MarkdownTextRenderer.render(MarkdownDocument.parse(text, request: request), writer: writer, request: request)
                output = writer.finish()
            }
            let isHTML = format == .markdownHTML
            return .success(ToolOutput(
                primaryText: output,
                status: isHTML ? "Rendered HTML" : "Plain text",
                presentation: .text,
                syntax: isHTML ? .xml : .plain
            ))
        } catch MarkupFailure.cancelled {
            return .cancelled
        } catch MarkupFailure.output {
            return .tooLarge(request.limits.outputLimitMessage)
        } catch MarkupFailure.nesting {
            return .tooLarge(request.limits.nestingLimitMessage)
        } catch {
            return .invalid(ToolDiagnostic("Couldn’t parse the Markdown."))
        }
    }
}

/// Why a conversion stopped early.
enum MarkupFailure: Error { case cancelled, output, nesting }

/// The ` (URL)` written after a link's text when Show link URLs is on:
/// nothing for empty, in-page, and `javascript:` links, or when the text
/// already is the address (with or without `mailto:`, `http://`, `https://`).
func markupLinkSuffix(text: String, url: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !url.isEmpty, !url.hasPrefix("#"), !url.lowercased().hasPrefix("javascript:") else { return "" }
    var short = url
    for prefix in ["mailto:", "http://", "https://"] where url.lowercased().hasPrefix(prefix) {
        short = String(url.dropFirst(prefix.count))
        break
    }
    return trimmed == url || trimmed == short ? "" : " (\(url))"
}
