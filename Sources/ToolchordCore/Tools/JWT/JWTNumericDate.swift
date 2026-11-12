import Foundation

struct JWTNumericDate {
    let milliseconds: Int64?
    let seconds: Double

    /// The input has already passed JSON validation. Decimal shifting avoids
    /// binary floating point rounding at millisecond and date-range boundaries.
    static func parse(_ token: String, cancellation: CancellationCheck) throws -> JWTNumericDate? {
        let bytes = Array(token.utf8)
        guard let first = bytes.first, first == 45 || (48...57).contains(first) else { return nil }
        let negative = first == 45
        var digits: [UInt8] = []
        var fractionCount = 0
        var fractional = false
        var index = negative ? 1 : 0
        while index < bytes.count, bytes[index] != 101, bytes[index] != 69 {
            if index % 4096 == 0, cancellation.isCancelled { throw JSONText.Failure.cancelled }
            let byte = bytes[index]
            if byte == 46 { fractional = true }
            else {
                digits.append(byte - 48)
                if fractional { fractionCount += 1 }
            }
            index += 1
        }
        var exponent = 0
        if index < bytes.count {
            index += 1
            let exponentNegative = index < bytes.count && bytes[index] == 45
            if index < bytes.count, bytes[index] == 45 || bytes[index] == 43 { index += 1 }
            while index < bytes.count {
                if index % 4096 == 0, cancellation.isCancelled { throw JSONText.Failure.cancelled }
                // More than any possible mantissa length; saturation preserves
                // classification even for a million-digit exponent.
                exponent = min(2_000_000, exponent * 10 + Int(bytes[index] - 48))
                index += 1
            }
            if exponentNegative { exponent = -exponent }
        }
        var start = 0
        while start < digits.count, digits[start] == 0 {
            if start % 4096 == 0, cancellation.isCancelled { throw JSONText.Failure.cancelled }
            start += 1
        }
        let nonzero = start < digits.count
        let shift = exponent - fractionCount + 3
        let integerCount = digits.count - start + shift
        var magnitude: Int64 = 0
        var milliseconds: Int64?
        if !nonzero { milliseconds = 0 }
        else if integerCount <= 15 {
            let retained = max(0, min(digits.count - start, integerCount))
            for offset in 0..<retained { magnitude = magnitude * 10 + Int64(digits[start + offset]) }
            if integerCount > retained {
                for _ in retained..<integerCount { magnitude *= 10 }
            }
            var discardedNonzero = false
            if start + retained < digits.count {
                for offset in (start + retained)..<digits.count {
                    if offset % 4096 == 0, cancellation.isCancelled { throw JSONText.Failure.cancelled }
                    if digits[offset] != 0 { discardedNonzero = true }
                }
            }
            milliseconds = negative ? -magnitude - (discardedNonzero ? 1 : 0) : magnitude
        }
        // Bound the exact decimal value, including fractions below one millisecond.
        if let value = milliseconds, value < -62_135_596_800_000 || value > 253_402_300_799_999 {
            milliseconds = nil
        }
        var seconds = Double(token) ?? (negative ? -.infinity : .infinity)
        if seconds == 0, nonzero { seconds = negative ? -Double.leastNonzeroMagnitude : Double.leastNonzeroMagnitude }
        return JWTNumericDate(milliseconds: milliseconds, seconds: seconds)
    }

    var instant: String {
        guard let milliseconds else { return "Outside the supported date range" }
        let dayLength: Int64 = 86_400_000
        var days = milliseconds / dayLength
        var remainder = milliseconds % dayLength
        if remainder < 0 { days -= 1; remainder += dayLength }
        // Proleptic Gregorian civil date, with March as the first month.
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let dayOfEra = z - era * 146097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        var year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthOfYear = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthOfYear + 2) / 5 + 1
        let month = monthOfYear + (monthOfYear < 10 ? 3 : -9)
        year += month <= 2 ? 1 : 0
        return String(format: "%04lld-%02lld-%02lldT%02lld:%02lld:%02lld.%03lldZ", year, month, day,
                      remainder / 3_600_000, remainder / 60_000 % 60, remainder / 1000 % 60, remainder % 1000)
    }

    func relative(to now: Double) -> String? {
        guard milliseconds != nil, now.isFinite else { return nil }
        let difference = seconds - now
        let magnitude = abs(difference)
        if magnitude < 1 { return "now" }
        let units: [(Double, String)] = [(31_536_000, "year"), (2_592_000, "month"), (86_400, "day"),
                                          (3600, "hour"), (60, "minute"), (1, "second")]
        for (length, unit) in units where magnitude >= length {
            let count = floor(magnitude / length)
            let amount = String(format: "%.0f", count)
            let description = "\(amount) \(unit)\(count == 1 ? "" : "s")"
            return difference <= 0 ? "Expired \(description) ago" : "Expires in \(description)"
        }
        return "now"
    }
}
