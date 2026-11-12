import Foundation

/// Calendar calculations use integers throughout, including dates before 1582.
enum TimeMath {
    static let range: ClosedRange<Int64> = -62_135_596_800_000...253_402_300_799_999
    static let rangeMessage = "Out of range. Toolchord supports dates from year 0001 to 9999."
    static let millisecondHint = " If this is a millisecond timestamp, set Unit to Milliseconds."

    static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    // Foundation supplies the clock as a floating-point Date. This is the only
    // bridge from that clock; parsed timestamps and calendar conversion never
    // pass through floating point. Guard the conversion for arbitrary Dates.
    static func clockMilliseconds(_ date: Date) -> Int64? {
        let value = (date.timeIntervalSince1970 * 1000).rounded(.down)
        guard value.isFinite, value >= Double(Int64.min), value < Double(Int64.max) else { return nil }
        return Int64(value)
    }

    static func isLeap(_ year: Int64) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

    static func monthDays(_ month: Int64, _ year: Int64) -> Int64 {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // March-based Gregorian eras, with 1970-01-01 as day zero.
    static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let year = year - (month <= 2 ? 1 : 0)
        let era = floorDivide(year, 400)
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    static func civilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let days = days + 719468
        let era = floorDivide(days, 146097)
        let dayOfEra = days - era * 146097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        var year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let marchMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * marchMonth + 2) / 5 + 1
        let month = marchMonth + (marchMonth < 10 ? 3 : -9)
        year += month <= 2 ? 1 : 0
        return (year, month, day)
    }

    static func padded(_ value: Int64, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    static func timeOfDay(_ milliseconds: Int64) -> String {
        let seconds = floorDivide(milliseconds, 1000)
        let daySeconds = seconds - floorDivide(seconds, 86400) * 86400
        return "\(padded(daySeconds / 3600, 2)):\(padded(daySeconds / 60 % 60, 2)):\(padded(daySeconds % 60, 2))"
    }

    static func format(_ milliseconds: Int64, suffix: String) -> String {
        let days = floorDivide(milliseconds, 86_400_000)
        let civil = civilFromDays(days)
        let fraction = milliseconds - floorDivide(milliseconds, 1000) * 1000
        return "\(padded(civil.year, 4))-\(padded(civil.month, 2))-\(padded(civil.day, 2))T\(timeOfDay(milliseconds)).\(padded(fraction, 3))\(suffix)"
    }

    static func offsetText(_ offset: Int) -> String {
        let magnitude = Int64(abs(offset))
        let base = "\(offset < 0 ? "-" : "+")\(padded(magnitude / 3600, 2)):\(padded(magnitude / 60 % 60, 2))"
        return magnitude % 60 == 0 ? base : base + ":\(padded(magnitude % 60, 2))"
    }

    static func secondsText(_ milliseconds: Int64) -> String {
        let magnitude = milliseconds.magnitude
        let whole = magnitude / 1000
        let remainder = magnitude % 1000
        let sign = milliseconds < 0 ? "-" : ""
        guard remainder != 0 else { return sign + String(whole) }
        var fraction = padded(Int64(remainder), 3)
        while fraction.last == "0" { fraction.removeLast() }
        return "\(sign)\(whole).\(fraction)"
    }

    static func relative(_ milliseconds: Int64, to now: Date) -> String {
        guard let nowMilliseconds = clockMilliseconds(now) else { return "now" }
        let (delta, overflow) = milliseconds.subtractingReportingOverflow(nowMilliseconds)
        let magnitude = overflow ? UInt64.max : delta.magnitude
        if magnitude < 1000 { return "now" }
        let units: [(UInt64, String)] = [(31_536_000_000, "year"), (2_592_000_000, "month"), (86_400_000, "day"), (3_600_000, "hour"), (60_000, "minute"), (1000, "second")]
        let unit = units.first { magnitude >= $0.0 }!
        let count = magnitude / unit.0
        let value = "\(count) \(unit.1)\(count == 1 ? "" : "s")"
        return milliseconds > nowMilliseconds ? "in \(value)" : "\(value) ago"
    }
}
