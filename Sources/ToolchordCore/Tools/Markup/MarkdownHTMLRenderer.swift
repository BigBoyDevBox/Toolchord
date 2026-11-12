import Foundation

/// Accumulates HTML bytes with output-limit and cancellation checks. A final
/// line break is held back, so the finished output has no trailing newline.
final class MarkupHTMLWriter {
    let request: ToolRequest
    var bytes: [UInt8] = []
    init(request: ToolRequest) { self.request = request }
    var pendingLF = false
    var endsInLF: Bool { pendingLF || bytes.last == 10 }
    func flushLF() throws {
        if pendingLF {
            guard bytes.count < request.limits.maxOutputBytes else { throw MarkupFailure.output }
            bytes.append(10); pendingLF = false
        }
    }
    func append(_ text: String) throws {
        if request.cancellation.isCancelled { throw MarkupFailure.cancelled }
        guard !text.isEmpty else { return }
        try flushLF()
        let finalLF = text.utf8.last == 10
        let count = text.utf8.count - (finalLF ? 1 : 0)
        guard count <= request.limits.maxOutputBytes - bytes.count else { throw MarkupFailure.output }
        bytes.append(contentsOf: text.utf8.prefix(count))
        pendingLF = finalLF
    }
    func cr() throws { if (!bytes.isEmpty || pendingLF) && !endsInLF { try append("\n") } }
    func escaped(_ text: String) throws {
        for (i, b) in text.utf8.enumerated() {
            if i % 4096 == 0, request.cancellation.isCancelled { throw MarkupFailure.cancelled }
            switch b {
            case 38: try append("&amp;")
            case 60: try append("&lt;")
            case 62: try append("&gt;")
            case 34: try append("&quot;")
            default:
                try flushLF()
                if bytes.count >= request.limits.maxOutputBytes { throw MarkupFailure.output }
                bytes.append(b)
            }
        }
    }
}

/// Writes a ``MarkdownDocument`` tree as HTML the way cmark-gfm does.
enum MarkdownHTMLRenderer {
    /// An open inline element. `inner` marks formatting inside link text,
    /// which nests inside the link rather than around it.
    struct Element: Equatable { var tag: String; var url: String?; var inner = false }
    static func inline(_ runs: [MarkdownInline], writer: MarkupHTMLWriter, drop: Int = 0) throws {
        var stack: [Element] = []; var remaining = drop
        func close(_ element: Element) throws { try writer.append("</\(element.tag)>") }
        for var run in runs {
            if remaining > 0 {
                let count = min(remaining, run.text.utf8.count)
                run.text = String(decoding: run.text.utf8.dropFirst(count), as: UTF8.self); remaining -= count
                if run.text.isEmpty { continue }
            }
            // Foundation drops formatting inside link text, so a run's own
            // formatting surrounds its link; formatting restored from the link
            // text's source nests inside it.
            var wanted: [Element] = []
            if run.strike { wanted.append(Element(tag: "del")) }
            if run.emphasis { wanted.append(Element(tag: "em")) }
            if run.strong { wanted.append(Element(tag: "strong")) }
            if let link = run.link { wanted.append(Element(tag: "a", url: link)) }
            if run.linkStrike { wanted.append(Element(tag: "del", inner: true)) }
            if run.linkEmphasis { wanted.append(Element(tag: "em", inner: true)) }
            if run.linkStrong { wanted.append(Element(tag: "strong", inner: true)) }
            // Keep an existing valid order; only unwind from the first missing element.
            var keep = stack.firstIndex(where: { !wanted.contains($0) }) ?? stack.count
            // Outer formatting opens outside the link: if some is missing while
            // a link is open, close back to the link and reopen it inside, so
            // `[a](x)**[b](x)**` keeps two links as cmark does.
            if wanted.contains(where: { $0.tag != "a" && !$0.inner && !stack[..<keep].contains($0) }),
               let link = stack[..<keep].firstIndex(where: { $0.tag == "a" }) {
                keep = link
            }
            for e in stack[keep...].reversed() { try close(e) }
            stack.removeSubrange(keep...)
            for e in wanted where !stack.contains(e) {
                if let url = e.url { try writer.append("<a href=\""); try writer.escaped(url); try writer.append("\">") }
                else { try writer.append("<\(e.tag)>") }
                stack.append(e)
            }
            if let image = run.image {
                try writer.append("<img src=\""); try writer.escaped(image); try writer.append("\" alt=\"")
                try writer.escaped(run.text == "\u{FFFC}" ? "" : run.text); try writer.append("\" />")
            } else if run.soft { try writer.append("\n")
            } else if run.hard { try writer.append("<br />\n")
            } else if run.html { try writer.append(run.text)
            } else if run.code { try writer.append("<code>"); try writer.escaped(run.text); try writer.append("</code>")
            } else { try writer.escaped(run.text) }
        }
        for e in stack.reversed() { try close(e) }
    }

    static func render(_ root: MarkdownBlock, request: ToolRequest) throws -> String {
        let writer = MarkupHTMLWriter(request: request)
        func block(_ node: MarkdownBlock, tight: Bool = false, taskDrop: Int = 0) throws {
            if request.cancellation.isCancelled { throw MarkupFailure.cancelled }
            switch node.kind {
            case .root: for child in node.children { try block(child) }
            case .paragraph:
                if !tight { try writer.cr(); try writer.append("<p>") }
                try inline(node.runs, writer: writer, drop: taskDrop)
                if !tight { try writer.append("</p>\n") }
            case .header(let level):
                try writer.cr(); try writer.append("<h\(level)>"); try inline(node.runs, writer: writer); try writer.append("</h\(level)>\n")
            case .quote:
                try writer.cr(); try writer.append("<blockquote>\n")
                for child in node.children { try block(child) }
                try writer.cr(); try writer.append("</blockquote>\n")
            case .orderedList, .unorderedList:
                let ordered: Bool; if case .orderedList = node.kind { ordered = true } else { ordered = false }
                let tag = ordered ? "ol" : "ul"
                var start = 1
                if let first = node.children.first, case .item(let n) = first.kind { start = n }
                try writer.cr(); try writer.append(ordered && start != 1 ? "<ol start=\"\(start)\">\n" : "<\(tag)>\n")
                for child in node.children { try block(child, tight: !node.loose) }
                try writer.append("</\(tag)>\n")
            case .item:
                try writer.cr(); try writer.append("<li>")
                let checked = node.task
                if let checked { try writer.append(checked ? "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> " : "<input type=\"checkbox\" disabled=\"\" /> ") }
                for (i, child) in node.children.enumerated() { try block(child, tight: tight, taskDrop: i == 0 && checked != nil ? 4 : 0) }
                try writer.append("</li>\n")
            case .code(let language):
                try writer.cr(); try writer.append("<pre><code")
                if let hint = language?.split(whereSeparator: { $0.isWhitespace }).first, !hint.isEmpty {
                    try writer.append(" class=\"language-"); try writer.escaped(String(hint)); try writer.append("\"")
                }
                try writer.append(">")
                for run in node.runs { try writer.escaped(run.text) }
                try writer.append("</code></pre>\n")
            case .thematic: try writer.cr(); try writer.append("<hr />\n")
            case .html:
                try writer.cr(); for run in node.runs { try writer.append(run.text) }; try writer.cr()
            case .table(let columns):
                try writer.cr(); try writer.append("<table>")
                var body = false
                for row in node.children {
                    let header: Bool; if case .headerRow = row.kind { header = true } else { header = false }
                    if header { try writer.cr(); try writer.append("<thead>") }
                    else if !body { try writer.cr(); try writer.append("<tbody>"); try writer.cr(); body = true }
                    try writer.cr(); try writer.append("<tr>")
                    var cells: [Int: MarkdownBlock] = [:]
                    for cell in row.children { if case .cell(let index) = cell.kind { cells[index] = cell } }
                    for i in 0..<columns {
                        let tag = header ? "th" : "td"
                        try writer.cr(); try writer.append("<\(tag)")
                        if i < node.alignments.count, let alignment = node.alignments[i] { try writer.append(" align=\"\(alignment)\"") }
                        try writer.append(">")
                        if let cell = cells[i] { try inline(cell.runs, writer: writer) }
                        try writer.append("</\(tag)>")
                    }
                    try writer.cr(); try writer.append("</tr>")
                    if header { try writer.cr(); try writer.append("</thead>") }
                }
                if body { try writer.cr(); try writer.append("</tbody>"); try writer.cr() }
                try writer.cr(); try writer.append("</table>"); try writer.cr()
            case .cell, .row, .headerRow: break
            }
        }
        try block(root)
        return String(decoding: writer.bytes, as: UTF8.self)
    }
}
