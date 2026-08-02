import Foundation

/// Staleness copy per DESIGN.md — data age is never hidden. "sampled Tue",
/// "buoy reading 3h ago", never a bare number.
enum Staleness {

    /// "sampled Tue" within a week, "sampled Jul 2" beyond, hours if today.
    static func sampled(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let dayGap = calendar.dateComponents([.day],
                                             from: calendar.startOfDay(for: date),
                                             to: calendar.startOfDay(for: now)).day ?? 0
        if dayGap <= 0 {
            let hours = Int(now.timeIntervalSince(date) / 3600)
            if hours <= 0 { return "sampled just now" }
            return "sampled \(hours)h ago"
        }
        if dayGap == 1 { return "sampled yesterday" }
        if dayGap < 7 {
            return "sampled \(weekday(date, calendar: calendar))"
        }
        return "sampled \(monthDay(date, calendar: calendar))"
    }

    /// "3h ago" / "2d ago" — compact age for readings.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE"          // "Tue"
        return f.string(from: date)
    }

    private static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"        // "Jul 2"
        return f.string(from: date)
    }

    /// Short weekday for the day strip: "Sat".
    static func shortWeekday(_ date: Date, calendar: Calendar = .current) -> String {
        weekday(date, calendar: calendar)
    }
}

/// Straight-line distance copy. US units (WA app). Compact enough to sit inline
/// next to the lake name without ever wrapping.
enum Distance {
    /// "nearby" under 0.1 mi, "4.2 mi" under 10, "23 mi" beyond.
    static func short(meters: Double) -> String {
        let miles = meters / 1609.344
        if miles < 0.1 { return "nearby" }
        if miles < 10 { return String(format: "%.1f mi", miles) }
        return "\(Int(miles.rounded())) mi"
    }
}
