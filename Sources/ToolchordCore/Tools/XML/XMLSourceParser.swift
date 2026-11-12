import Foundation

struct XMLSourceFailure: Error {
    let result: ToolResult
}

/// Scalar offsets make XML names explicit; byte offsets retain the exact source.
/// No DTD, schema, file, URL, or system XML parser is ever consulted.
struct XMLSourceParser {
    struct Node {
        let start: Int
        var end: Int
        var startTagEnd: Int
        var endTagStart: Int
        var children: [Int] = []
        var structural: Bool = false
    }

    struct Frame {
        let node: Int
        let name: String
        let namespaceUndo: [NamespaceUndo]
        let preserve: Bool
    }

    struct NamespaceUndo {
        let prefix: [UInt8]
        let previous: String?
    }

    struct Attribute {
        let name: String
        let value: String
        let start: Int
    }

    // XML compares names and namespace URIs scalar-for-scalar. Swift String
    // equality folds canonical Unicode equivalents, so use UTF-8 keys instead.
    struct ExpandedName: Hashable {
        let uri: [UInt8]
        let local: [UInt8]
    }

    static let xmlURI = "http://www.w3.org/XML/1998/namespace"
    static let xmlnsURI = "http://www.w3.org/2000/xmlns/"
    static let doctypeMessage = "Document type declarations (DOCTYPE) aren’t supported. Toolchord checks well-formedness without loading DTDs or entities."

    let bytes: [UInt8]
    let scalars: [UInt32]
    let offsets: [Int]
    let request: ToolRequest
    var cursor = 0
    var nodes: [Node] = []
    var topLevel: [Int] = []
    var stack: [Frame] = []
    // Only declarations made by an element are stored in its frame.
    var namespaces: [[UInt8]: String] = [Array("xml".utf8): xmlURI]
    var hasRoot = false
    var hasBOM = false
    var nextCancellationCheck = 0

    init(_ text: String, request: ToolRequest) throws {
        self.request = request
        if request.cancellation.isCancelled { throw XMLSourceFailure(result: .cancelled) }
        bytes = Array(text.utf8)
        var values: [UInt32] = []
        var positions: [Int] = []
        values.reserveCapacity(bytes.count)
        positions.reserveCapacity(bytes.count + 1)
        var byteOffset = 0
        for scalar in text.unicodeScalars {
            if values.count & 2047 == 0, request.cancellation.isCancelled {
                throw XMLSourceFailure(result: .cancelled)
            }
            positions.append(byteOffset)
            values.append(scalar.value)
            byteOffset += scalar.utf8.count
        }
        positions.append(byteOffset)
        scalars = values
        offsets = positions
    }

    var atEnd: Bool { cursor == scalars.count }
    var current: UInt32? { atEnd ? nil : scalars[cursor] }
    var bytePosition: Int { offsets[cursor] }

    func fail(_ message: String, at position: Int? = nil) throws -> Never {
        throw XMLSourceFailure(result: .invalid(ToolDiagnostic(
            message, at: TextLocator.location(ofUTF8Offset: position ?? bytePosition, in: bytes)
        )))
    }

    static func legalCharacter(_ value: UInt32) -> Bool {
        value == 9 || value == 10 || value == 13 || (0x20...0xD7FF).contains(value)
            || (0xE000...0xFFFD).contains(value) || (0x10000...0x10FFFF).contains(value)
    }

    static func whitespace(_ value: UInt32) -> Bool { value == 32 || value == 9 || value == 10 || value == 13 }

    static func nameStart(_ value: UInt32) -> Bool {
        value == 58 || value == 95 || (65...90).contains(value) || (97...122).contains(value)
            || (0xC0...0xD6).contains(value) || (0xD8...0xF6).contains(value)
            || (0xF8...0x2FF).contains(value) || (0x370...0x37D).contains(value)
            || (0x37F...0x1FFF).contains(value) || (0x200C...0x200D).contains(value)
            || (0x2070...0x218F).contains(value) || (0x2C00...0x2FEF).contains(value)
            || (0x3001...0xD7FF).contains(value) || (0xF900...0xFDCF).contains(value)
            || (0xFDF0...0xFFFD).contains(value) || (0x10000...0xEFFFF).contains(value)
    }

    static func nameCharacter(_ value: UInt32) -> Bool {
        nameStart(value) || value == 45 || value == 46 || (48...57).contains(value)
            || value == 0xB7 || (0x300...0x36F).contains(value) || (0x203F...0x2040).contains(value)
    }

    mutating func advance() throws {
        guard !atEnd else { return }
        if cursor >= nextCancellationCheck {
            if request.cancellation.isCancelled { throw XMLSourceFailure(result: .cancelled) }
            nextCancellationCheck = cursor + 2048
        }
        guard Self.legalCharacter(scalars[cursor]) else {
            try fail("Illegal XML character.")
        }
        cursor += 1
    }

    func starts(_ token: StaticString) -> Bool {
        token.withUTF8Buffer { tokenBytes in
            guard cursor + tokenBytes.count <= scalars.count else { return false }
            for index in tokenBytes.indices where scalars[cursor + index] != UInt32(tokenBytes[index]) { return false }
            return true
        }
    }

    mutating func consume(_ token: StaticString) throws {
        for _ in 0..<token.utf8CodeUnitCount { try advance() }
    }

    @discardableResult
    mutating func skipWhitespace() throws -> Bool {
        let start = cursor
        while let value = current, Self.whitespace(value) { try advance() }
        return start != cursor
    }

    func source(_ start: Int, _ end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    mutating func name(qname: Bool = true) throws -> String {
        let start = bytePosition
        let scalarStart = cursor
        guard let value = current, Self.nameStart(value) else { try fail("Expected an XML name.") }
        var colons = 0
        var invalidQualifiedName = false
        while let value = current, Self.nameCharacter(value) {
            if qname, value == 58 {
                colons += 1
                if colons > 1 || cursor == scalarStart || cursor + 1 == scalars.count {
                    invalidQualifiedName = true
                } else {
                    let next = scalars[cursor + 1]
                    if next == 58 || !Self.nameStart(next) { invalidQualifiedName = true }
                }
            }
            try advance()
        }
        let result = source(start, bytePosition)
        if invalidQualifiedName { try fail("Invalid qualified name “\(result)”.", at: start) }
        return result
    }

    static func parts(_ name: String) -> (prefix: String?, local: String) {
        let utf8 = name.utf8
        if let colon = utf8.firstIndex(of: 58) {
            return (
                String(decoding: utf8[..<colon], as: UTF8.self),
                String(decoding: utf8[utf8.index(after: colon)...], as: UTF8.self)
            )
        }
        return (nil, name)
    }

    mutating func parse() throws {
        if current == 0xFEFF { hasBOM = true; try advance() }
        while !atEnd {
            if starts("<!--") {
                try comment()
            } else if starts("<?") {
                try processingInstruction()
            } else if starts("<!DOCTYPE"), stack.isEmpty, !hasRoot {
                throw XMLSourceFailure(result: .unsupported(Self.doctypeMessage))
            } else if starts("<![CDATA[") {
                try cdata()
            } else if starts("</") {
                try endTag()
            } else if starts("<!") {
                try fail("Unexpected markup declaration.")
            } else if current == 60 {
                try startTag()
            } else {
                try characterData()
            }
        }
        if let frame = stack.last {
            try fail("Expected “</\(frame.name)>” before the end of the input.", at: nodes[frame.node].start)
        }
        guard hasRoot else { try fail("Expected a root element.") }
    }

    mutating func addNode(start: Int, end: Int) {
        let index = nodes.count
        nodes.append(Node(start: start, end: end, startTagEnd: end, endTagStart: end))
        if let parent = stack.last { nodes[parent.node].children.append(index) }
        else { topLevel.append(index) }
    }

    mutating func comment() throws {
        let start = bytePosition
        try consume("<!--")
        while !atEnd {
            if starts("-->") { try consume("-->"); addNode(start: start, end: bytePosition); return }
            if starts("--") { try fail("Comments must not contain “--” or end with “-”.", at: start) }
            try advance()
        }
        try fail("Expected “-->” to close the comment.", at: start)
    }

    mutating func processingInstruction() throws {
        let start = bytePosition
        try consume("<?")
        let targetStart = bytePosition
        let target = try name(qname: false)
        if let colon = target.utf8.firstIndex(of: 58) {
            try fail("Processing instruction targets can’t contain “:”.",
                     at: targetStart + target.utf8.distance(from: target.utf8.startIndex, to: colon))
        }
        if target == "xml" {
            guard start == (hasBOM ? 3 : 0) else {
                try fail("The XML declaration must be at the very start of the document.", at: start)
            }
            try declaration(start: start)
            return
        }
        guard target.lowercased() != "xml" else {
            try fail("The processing instruction target “\(target)” is reserved.", at: start)
        }
        let separated = try skipWhitespace()
        guard starts("?>") || separated else {
            try fail("Expected whitespace after the processing instruction target.", at: start)
        }
        while !atEnd {
            if starts("?>") { try consume("?>"); addNode(start: start, end: bytePosition); return }
            try advance()
        }
        try fail("Expected “?>” to close the processing instruction.", at: start)
    }

    mutating func declaration(start: Int) throws {
        guard try skipWhitespace() else { try fail("Expected a version in the XML declaration.", at: start) }
        guard try name(qname: false) == "version" else { try fail("Expected version first in the XML declaration.", at: start) }
        let version = try declarationValue()
        let versionBytes = Array(version.utf8)
        guard versionBytes.count >= 3, versionBytes[0] == 49, versionBytes[1] == 46,
              versionBytes.dropFirst(2).allSatisfy({ (48...57).contains($0) }) else {
            try fail("The XML version must have the form “1.x” with decimal digits.", at: start)
        }
        var hasEncoding = false
        var hasStandalone = false
        while true {
            let separated = try skipWhitespace()
            if starts("?>") { try consume("?>"); addNode(start: start, end: bytePosition); return }
            guard separated, !atEnd else { try fail("Expected “?>” or a declaration attribute.", at: start) }
            let attribute = try name(qname: false)
            let value = try declarationValue()
            if attribute == "encoding", !hasEncoding, !hasStandalone {
                let chars = Array(value.utf8)
                guard let first = chars.first, (65...90).contains(first) || (97...122).contains(first),
                      chars.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 95 || $0 == 45 }) else {
                    try fail("Invalid encoding name in the XML declaration.", at: start)
                }
                hasEncoding = true
            } else if attribute == "standalone", !hasStandalone {
                guard value == "yes" || value == "no" else { try fail("Standalone must be “yes” or “no”.", at: start) }
                hasStandalone = true
            } else {
                try fail("Unexpected or out-of-order XML declaration attribute “\(attribute)”.", at: start)
            }
        }
    }

    mutating func equals() throws {
        try skipWhitespace()
        guard current == 61 else { try fail("Expected “=” after the attribute name.") }
        try advance()
        try skipWhitespace()
    }

    mutating func declarationValue() throws -> String {
        try equals()
        let start = bytePosition
        guard let quote = current, quote == 34 || quote == 39 else { try fail("Attribute values must be quoted.") }
        try advance()
        let valueStart = bytePosition
        while let value = current, value != quote { try advance() }
        guard !atEnd else { try fail("Expected a closing quote for the attribute value.", at: start) }
        let value = source(valueStart, bytePosition)
        try advance()
        return value
    }

    mutating func cdata() throws {
        let start = bytePosition
        guard let parent = stack.last else { try fail("CDATA isn’t allowed outside the root element.", at: start) }
        nodes[parent.node].structural = false
        try consume("<![CDATA[")
        while !atEnd {
            if starts("]]>") { try consume("]]>"); return }
            try advance()
        }
        try fail("Expected “]]>” to close the CDATA section.", at: start)
    }

    mutating func characterData() throws {
        while let value = current, value != 60 {
            if stack.isEmpty {
                guard Self.whitespace(value) else { try fail("Text isn’t allowed outside the root element.") }
                try advance()
            } else {
                if starts("]]>") { try fail("Character data must not contain “]]>”.") }
                if value == 38 {
                    nodes[stack.last!.node].structural = false
                    _ = try reference()
                } else {
                    if !Self.whitespace(value) { nodes[stack.last!.node].structural = false }
                    try advance()
                }
            }
        }
    }

    mutating func reference() throws -> UInt32 {
        let start = bytePosition
        try advance() // &
        if current == 35 {
            try advance()
            let hex = current == 120
            if hex { try advance() }
            let digitStart = cursor
            var number: UInt32 = 0
            var overflow = false
            while let value = current {
                let digit: UInt32
                if (48...57).contains(value) { digit = value - 48 }
                else if hex, (65...70).contains(value) { digit = value - 65 + 10 }
                else if hex, (97...102).contains(value) { digit = value - 97 + 10 }
                else { break }
                if number > 0x10FFFF / (hex ? 16 : 10) { overflow = true }
                if !overflow {
                    number = number * (hex ? 16 : 10) + digit
                    if number > 0x10FFFF { overflow = true }
                }
                try advance()
            }
            guard cursor > digitStart, current == 59 else { try fail("Invalid character reference.", at: start) }
            try advance()
            guard !overflow, Self.legalCharacter(number) else { try fail("Character reference refers to an illegal XML character.", at: start) }
            return number
        }
        guard let value = current, Self.nameStart(value) else { try fail("Expected an entity or character reference after “&”.", at: start) }
        let entity = try name(qname: false)
        guard current == 59 else { try fail("Expected “;” after the entity reference.", at: start) }
        try advance()
        switch entity {
        case "lt": return 60
        case "gt": return 62
        case "amp": return 38
        case "apos": return 39
        case "quot": return 34
        default: try fail("Undefined entity “&\(entity);”. XML only predefines &lt;, &gt;, &amp;, &apos;, and &quot;.", at: start)
        }
    }

    mutating func attributeValue() throws -> String {
        let start = bytePosition
        guard let quote = current, quote == 34 || quote == 39 else { try fail("Attribute values must be quoted.") }
        try advance()
        var value = String.UnicodeScalarView()
        var previousCR = false
        while let scalar = current, scalar != quote {
            if scalar == 60 { try fail("Attribute values must not contain a raw “<”.") }
            if scalar == 38 {
                value.append(Unicode.Scalar(try reference())!)
                previousCR = false
            } else {
                // XML attribute normalization applies to literal whitespace only.
                if !(scalar == 10 && previousCR) {
                    value.append(Unicode.Scalar(Self.whitespace(scalar) ? 32 : scalar)!)
                }
                previousCR = scalar == 13
                try advance()
            }
        }
        guard !atEnd else { try fail("Expected a closing quote for the attribute value.", at: start) }
        try advance()
        return String(value)
    }

    mutating func startTag() throws {
        let start = bytePosition
        guard !stack.isEmpty || !hasRoot else { try fail("Only one root element is allowed.", at: start) }
        guard stack.count < request.limits.maxNestingDepth else {
            throw XMLSourceFailure(result: .tooLarge(request.limits.nestingLimitMessage))
        }
        try advance()
        let elementName = try name()
        var attributes: [Attribute] = []
        var seen: Set<[UInt8]> = []
        var empty = false
        while true {
            let separated = try skipWhitespace()
            if starts("/>") { try consume("/>"); empty = true; break }
            if current == 62 { try advance(); break }
            guard !atEnd else { try fail("Expected “>” to close the start tag.", at: start) }
            guard separated else { try fail("Expected whitespace between attributes.") }
            let attributeStart = bytePosition
            let attributeName = try name()
            guard seen.insert(Array(attributeName.utf8)).inserted else { try fail("Duplicate attribute “\(attributeName)”.", at: attributeStart) }
            try equals()
            let value = try attributeValue()
            attributes.append(Attribute(name: attributeName, value: value, start: attributeStart))
        }
        var namespaceUndo: [NamespaceUndo] = []
        var preserve = stack.last?.preserve ?? false
        for attribute in attributes {
            let parts = Self.parts(attribute.name)
            if attribute.name == "xmlns" || parts.prefix == "xmlns" {
                let prefix = attribute.name == "xmlns" ? "" : parts.local
                let uri = attribute.value
                if prefix == "xmlns" || uri == Self.xmlnsURI {
                    try fail("The “xmlns” prefix and its namespace URI must not be declared.", at: attribute.start)
                }
                if (prefix == "xml" && uri != Self.xmlURI) || (prefix != "xml" && uri == Self.xmlURI) {
                    try fail("Only the “xml” prefix may be bound to the XML namespace URI.", at: attribute.start)
                }
                if !prefix.isEmpty && uri.isEmpty {
                    try fail("A namespace prefix must not be bound to an empty URI.", at: attribute.start)
                }
                let key = Array(prefix.utf8)
                namespaceUndo.append(NamespaceUndo(prefix: key, previous: namespaces.updateValue(uri, forKey: key)))
            }
            if attribute.name == "xml:space" {
                if attribute.value == "preserve" { preserve = true }
                else if attribute.value == "default" { preserve = false }
            }
        }
        let elementParts = Self.parts(elementName)
        if let prefix = elementParts.prefix {
            guard prefix != "xmlns", namespaces[Array(prefix.utf8)] != nil else { try fail("Undeclared namespace prefix “\(prefix)”.", at: start) }
        }
        var expanded: Set<ExpandedName> = []
        for attribute in attributes {
            let parts = Self.parts(attribute.name)
            if attribute.name == "xmlns" || parts.prefix == "xmlns" { continue }
            var uri = ""
            if let prefix = parts.prefix {
                guard let bound = namespaces[Array(prefix.utf8)] else { try fail("Undeclared namespace prefix “\(prefix)”.", at: attribute.start) }
                uri = bound
            }
            guard expanded.insert(ExpandedName(uri: Array(uri.utf8), local: Array(parts.local.utf8))).inserted else {
                try fail("Duplicate expanded attribute name “\(attribute.name)”.", at: attribute.start)
            }
        }
        let index = nodes.count
        addNode(start: start, end: bytePosition)
        if stack.isEmpty { hasRoot = true }
        if !empty {
            nodes[index].structural = !preserve
            stack.append(Frame(node: index, name: elementName, namespaceUndo: namespaceUndo, preserve: preserve))
        } else {
            try restoreNamespaces(namespaceUndo)
        }
    }

    mutating func restoreNamespaces(_ undo: [NamespaceUndo]) throws {
        for (index, binding) in undo.reversed().enumerated() {
            if index & 2047 == 0, request.cancellation.isCancelled {
                throw XMLSourceFailure(result: .cancelled)
            }
            namespaces[binding.prefix] = binding.previous
        }
    }

    mutating func endTag() throws {
        let start = bytePosition
        try consume("</")
        let endName = try name()
        try skipWhitespace()
        guard current == 62 else { try fail("Expected “>” to close the end tag.", at: start) }
        try advance()
        guard let frame = stack.last else { try fail("Unexpected end tag “</\(endName)>”.", at: start) }
        guard endName.utf8.elementsEqual(frame.name.utf8) else { try fail("Expected “</\(frame.name)>”, found “</\(endName)>”.", at: start) }
        nodes[frame.node].endTagStart = start
        nodes[frame.node].end = bytePosition
        if nodes[frame.node].children.isEmpty { nodes[frame.node].structural = false }
        stack.removeLast()
        try restoreNamespaces(frame.namespaceUndo)
    }

    func formatted(indent: String) throws -> String {
        var output: [UInt8] = []
        output.reserveCapacity(min(bytes.count, max(0, request.limits.maxOutputBytes)))
        let unit = Array(indent.utf8)
        func check(_ count: Int) throws {
            guard count <= request.limits.maxOutputBytes - output.count else {
                throw XMLSourceFailure(result: .tooLarge(request.limits.outputLimitMessage))
            }
            if request.cancellation.isCancelled { throw XMLSourceFailure(result: .cancelled) }
        }
        func append(_ range: Range<Int>) throws {
            try check(range.count)
            var position = range.lowerBound
            while position < range.upperBound {
                let end = min(position + 4096, range.upperBound)
                if request.cancellation.isCancelled { throw XMLSourceFailure(result: .cancelled) }
                output.append(contentsOf: bytes[position..<end])
                position = end
            }
        }
        func newline(depth: Int) throws {
            let (width, overflow) = depth.multipliedReportingOverflow(by: unit.count)
            guard !overflow, width < Int.max else { throw XMLSourceFailure(result: .tooLarge(request.limits.outputLimitMessage)) }
            try check(1 + width)
            output.append(10)
            for level in 0..<depth {
                if level & 2047 == 0, request.cancellation.isCancelled { throw XMLSourceFailure(result: .cancelled) }
                output.append(contentsOf: unit)
            }
        }
        // An explicit work stack also handles a caller-specified large nesting limit.
        enum Work {
            case node(Int, Int)
            case line(Int)
            case raw(Range<Int>)
        }
        if hasBOM { try append(0..<3) }
        var work: [Work] = []
        for index in topLevel.indices.reversed() {
            work.append(.node(topLevel[index], 0))
            if index != 0 { work.append(.line(0)) }
        }
        while let item = work.popLast() {
            switch item {
            case .line(let depth): try newline(depth: depth)
            case .raw(let range): try append(range)
            case .node(let index, let depth):
                let node = nodes[index]
                if !node.structural { try append(node.start..<node.end); continue }
                try append(node.start..<node.startTagEnd)
                work.append(.raw(node.endTagStart..<node.end))
                work.append(.line(depth))
                for child in node.children.reversed() {
                    work.append(.node(child, depth + 1))
                    work.append(.line(depth + 1))
                }
            }
        }
        return String(decoding: output, as: UTF8.self)
    }
}
