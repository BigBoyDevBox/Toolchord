import Foundation

/// Writes a ``MarkdownDocument`` tree as plain text with ``PlainTextWriter``.
enum MarkdownTextRenderer {
    static func inline(_ runs: [MarkdownInline], writer: PlainTextWriter, request: ToolRequest) throws {
        var link: String?; var label = ""
        // An inline HTML `<a href>` open across the runs between its tags.
        var anchor: (url: String, text: String)?
        // Inline HTML whose content isn't shown (`<script>`, `<span hidden>`),
        // skipped across runs until its end tag. Raw-text elements (`script`,
        // `style`) end at their first end tag and don't nest; one inside a
        // skipped element hides any tags in its text from the outer element.
        var skipped: (name: String, depth: Int, raw: Bool)?
        var rawInsideSkipped: String?
        func finishLink() throws {
            if let url = link, request.options.flag("links") { try writer.write(markupLinkSuffix(text: label, url: url)) }
            link = nil; label = ""
        }
        func finishAnchor() throws {
            if let open = anchor, request.options.flag("links") { try writer.write(markupLinkSuffix(text: open.text, url: open.url)) }
            anchor = nil
        }
        func emit(_ text: String) throws {
            if link != nil { label += text }
            if anchor != nil { anchor!.text += text }
            try writer.write(text)
        }
        // Inline HTML converts like HTML: line breaks, image alt text, and
        // link URLs; other tags and comments are dropped. One run can hold
        // several tags (`<br><img …>`), so walk all of them in order.
        func inlineHTML(_ html: String) throws {
            let bytes = Array(html.utf8)
            var index = 0
            while index < bytes.count {
                guard bytes[index] == 0x3C else { index += 1; continue }
                // In raw text only the element's own end tag counts; comments
                // and other tags are part of the text.
                if let raw = rawInsideSkipped ?? (skipped?.raw == true ? skipped?.name : nil) {
                    if let after = rawEndTag(raw, in: bytes, at: index) {
                        if rawInsideSkipped != nil { rawInsideSkipped = nil } else { skipped = nil }
                        index = after
                    } else {
                        index += 1
                    }
                    continue
                }
                if bytes[index...].starts(with: "<!--".utf8) {
                    index = (index + 4..<bytes.count).first { bytes[$0...].starts(with: "-->".utf8) }.map { $0 + 3 } ?? bytes.count
                    continue
                }
                guard let (tag, end) = try HTMLTextConverter.tag(bytes, at: index, cancellation: request.cancellation) else {
                    index += 1
                    continue
                }
                index = end
                if let open = skipped {
                    if tag.name == open.name {
                        if tag.end {
                            skipped = open.depth > 1 ? (open.name, open.depth - 1, false) : nil
                        } else if !tag.selfClosing {
                            skipped = (open.name, open.depth + 1, false)
                        }
                    } else if !tag.end, HTMLTextConverter.raw.contains(tag.name) || tag.name == "textarea" {
                        rawInsideSkipped = tag.name
                    }
                    continue
                }
                if HTMLTextConverter.opensHiddenContent(tag) {
                    skipped = (tag.name, 1, HTMLTextConverter.raw.contains(tag.name) || tag.name == "textarea")
                    continue
                }
                if !tag.end, HTMLTextConverter.isHiddenByAttribute(tag) { continue }
                switch (tag.name, tag.end) {
                case ("br", false): try writer.hardBreak()
                case ("img", false):
                    let alt = (tag.attributes["alt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !alt.isEmpty { try emit("[\(alt)]") }
                case ("a", false): try finishAnchor(); anchor = (tag.attributes["href"] ?? "", "")
                case ("a", true): try finishAnchor()
                default: break
                }
            }
        }
        for run in runs {
            // Text, images, and links inside skipped HTML aren't shown.
            if skipped != nil && !run.html { continue }
            if run.link != link { try finishLink(); link = run.link }
            if run.image != nil {
                let alt = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
                try emit(alt.isEmpty || alt == "\u{FFFC}" ? "" : "[\(alt)]")
            } else if run.soft {
                try emit(" ")
            } else if run.hard {
                try writer.hardBreak()
            } else if run.html {
                try inlineHTML(run.text)
            } else {
                try emit(run.text)
            }
        }
        try finishLink()
        try finishAnchor()
    }

    /// The index just past `</name …>` starting at `index` (name matched
    /// case-insensitively), or `nil` when that isn't the end tag.
    static func rawEndTag(_ name: String, in bytes: [UInt8], at index: Int) -> Int? {
        let target = Array("</\(name)".utf8)
        guard index + target.count <= bytes.count else { return nil }
        for (offset, expected) in target.enumerated() {
            let byte = bytes[index + offset]
            guard ((65...90).contains(byte) ? byte + 32 : byte) == expected else { return nil }
        }
        var close = index + target.count
        if close < bytes.count, ![0x3E, 0x2F, 0x20, 0x09, 0x0A, 0x0D, 0x0C].contains(bytes[close]) { return nil }
        while close < bytes.count, bytes[close] != 0x3E { close += 1 }
        return min(close + 1, bytes.count)
    }

    static func render(_ root: MarkdownBlock, writer: PlainTextWriter, request: ToolRequest) throws {
        func block(_ node: MarkdownBlock, boundary: Int = 2, ordered: Bool = false) throws {
            if request.cancellation.isCancelled { throw MarkupFailure.cancelled }
            writer.boundary(boundary)
            switch node.kind {
            case .root: for child in node.children { try block(child) }
            case .paragraph, .header: try inline(node.runs, writer: writer, request: request)
            case .quote:
                writer.pushQuote()
                for child in node.children { try block(child) }
                writer.popPrefix()
            case .orderedList, .unorderedList:
                let isOrdered: Bool; if case .orderedList = node.kind { isOrdered = true } else { isOrdered = false }
                for child in node.children { try block(child, boundary: node.loose ? 2 : 1, ordered: isOrdered) }
            case .item(let ordinal):
                try writer.beginItem(ordered ? "\(ordinal). " : "• ")
                for child in node.children { try block(child, boundary: boundary) }
                writer.popPrefix()
            case .code:
                var text = node.runs.map(\.text).joined()
                if text.hasSuffix("\n") { text.removeLast() }
                try writer.write(text, verbatim: true)
            case .thematic: break
            case .html:
                try HTMLTextConverter.convert(node.runs.map(\.text).joined(), writer: writer, request: request)
            case .table(let columns):
                for row in node.children {
                    var cells = Array(repeating: "", count: columns)
                    for cell in row.children {
                        if case .cell(let index) = cell.kind, index < columns {
                            let cellWriter = PlainTextWriter(request: request)
                            try inline(cell.runs, writer: cellWriter, request: request)
                            cells[index] = cellWriter.finish().split(whereSeparator: { $0 == "\n" || $0 == "\r" }).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    writer.boundary(1); try writer.row(cells)
                }
            case .cell, .row, .headerRow: break
            }
            writer.boundary(boundary)
        }
        try block(root)
    }
}
