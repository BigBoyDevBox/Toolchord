import Foundation

/// Converts offsets into one-based line and column positions.
///
/// Lines break at LF, CR, or CRLF (CRLF counts once). Columns count Unicode
/// scalars, so a non-ASCII character advances the column by one regardless of
/// its UTF-8 length.
public enum TextLocator {
    /// The location of the UTF-8 byte at `offset` (`0...utf8.count`).
    public static func location<Bytes: Collection>(ofUTF8Offset offset: Int, in utf8: Bytes) -> TextLocation where Bytes.Element == UInt8 {
        var line = 1
        var column = 1
        var previousWasCR = false
        var position = 0
        for byte in utf8 {
            if position >= offset { break }
            position += 1
            if byte == 0x0A {
                if previousWasCR {
                    previousWasCR = false
                    continue
                }
                line += 1
                column = 1
            } else if byte == 0x0D {
                line += 1
                column = 1
                previousWasCR = true
                continue
            } else if byte & 0xC0 != 0x80 {
                column += 1
            }
            previousWasCR = false
        }
        return TextLocation(line: line, column: column)
    }

    public static func location(ofUTF8Offset offset: Int, in text: String) -> TextLocation {
        location(ofUTF8Offset: offset, in: text.utf8)
    }

    /// The location of a scalar index in `text`.
    public static func location(of index: String.Index, in text: String) -> TextLocation {
        let offset = text.utf8.distance(from: text.utf8.startIndex, to: index)
        return location(ofUTF8Offset: offset, in: text.utf8)
    }

    /// The location of the `scalarOffset`-th Unicode scalar in `text`.
    public static func location(ofScalarOffset scalarOffset: Int, in text: String) -> TextLocation {
        let scalars = text.unicodeScalars
        let index = scalars.index(scalars.startIndex, offsetBy: scalarOffset, limitedBy: scalars.endIndex) ?? scalars.endIndex
        return location(of: index, in: text)
    }
}

extension String {
    /// Byte-for-byte UTF-8 equality. Swift's `==` uses canonical equivalence,
    /// so "é" (U+00E9) equals "e" + U+0301 even though tools such as Base64
    /// produce different output for them.
    public func hasSameUTF8(as other: String) -> Bool {
        utf8.elementsEqual(other.utf8)
    }
}
