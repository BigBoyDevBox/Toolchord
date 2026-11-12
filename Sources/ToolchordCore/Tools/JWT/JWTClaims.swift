import Foundation

struct JWTClaims {
    var name: String
    var value: String

    /// Scans only validated, minified objects; punctuation inside strings is opaque.
    static func scan(_ text: String, request: ToolRequest) throws -> [JWTClaims] {
        let bytes = Array(text.utf8)
        var index = 1
        var result: [JWTClaims] = []
        var nextCheck = 0
        func checkpoint(_ offset: Int) throws {
            if offset >= nextCheck {
                if request.cancellation.isCancelled { throw JSONText.Failure.cancelled }
                nextCheck = offset + 4096
            }
        }
        while index < bytes.count - 1 {
            let nameStart = index
            index += 1
            while bytes[index] != 34 {
                try checkpoint(index)
                index += bytes[index] == 92 ? 2 : 1
            }
            index += 1
            let name = try JSONStringCodec.unescape(String(decoding: bytes[nameStart..<index], as: UTF8.self),
                                                    limits: request.limits, cancellation: request.cancellation)
            index += 1 // colon
            let valueStart = index
            var depth = 0
            var inString = false
            while index < bytes.count {
                try checkpoint(index)
                let byte = bytes[index]
                if inString {
                    if byte == 92 { index += 2; continue }
                    if byte == 34 { inString = false }
                } else {
                    if depth == 0 && (byte == 44 || byte == 125) { break }
                    if byte == 34 { inString = true }
                    if byte == 123 || byte == 91 { depth += 1 }
                    if byte == 125 || byte == 93 { depth -= 1 }
                }
                index += 1
            }
            result.append(JWTClaims(name: name, value: String(decoding: bytes[valueStart..<index], as: UTF8.self)))
            if bytes[index] == 44 { index += 1 }
        }
        return result
    }
}
