// Time.swift — local-date arithmetic. The server addresses puzzles by calendar date;
// the client decides which date is "today" in the user's zone and when it flips.
//
// CONTRACT FILE.

import Foundation

public enum LocalDay {
    /// `YYYY-MM-DD` of `now` in `tz` (Gregorian). Falls back to UTC if `tz` is unknown.
    public static func date(_ now: Date, tz: String) -> String {
        let calendar = calendar(for: tz)
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return formatDate(components)
    }

    /// Seconds until the next local midnight in `tz` (always > 0 and ≤ 86_400).
    public static func secondsUntilMidnight(_ now: Date, tz: String) -> Int {
        let calendar = calendar(for: tz)
        let midnight = DateComponents(hour: 0, minute: 0, second: 0)
        guard let next = calendar.nextDate(after: now, matching: midnight, matchingPolicy: .nextTime) else {
            return 86_400
        }
        let seconds = Int(next.timeIntervalSince(now).rounded(.up))
        return min(max(seconds, 1), 86_400)
    }

    /// "9h 12m" style countdown text for a number of seconds: hours and minutes when ≥ 1 h,
    /// "12m" when ≥ 1 min, "<1m" below that.
    public static func countdownText(seconds: Int) -> String {
        if seconds >= 3_600 {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            return "\(hours)h \(minutes)m"
        }
        if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "<1m"
    }

    /// The date `days` before (negative) or after `dateString`, as `YYYY-MM-DD`, computed in UTC.
    public static func shift(_ dateString: String, by days: Int) -> String {
        let calendar = utcCalendar()
        guard let date = parse(dateString, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            return dateString
        }
        return formatDate(calendar.dateComponents([.year, .month, .day], from: shifted))
    }

    /// Monday-based ISO week: the Monday on or before `dateString`.
    public static func weekStart(_ dateString: String) -> String {
        let calendar = utcCalendar()
        guard let date = parse(dateString, calendar: calendar) else { return dateString }
        // Calendar's `.weekday`: 1 = Sunday ... 7 = Saturday, regardless of `firstWeekday`.
        let weekday = calendar.component(.weekday, from: date)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: date) else {
            return dateString
        }
        return formatDate(calendar.dateComponents([.year, .month, .day], from: monday))
    }

    /// Weekday name for the header ("Thursday") in the given locale identifier (default "en_US").
    public static func weekdayName(_ dateString: String, locale: String = "en_US") -> String {
        let calendar = utcCalendar()
        guard let date = parse(dateString, calendar: calendar) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    // MARK: Helpers

    private static func calendar(for tz: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func parse(_ dateString: String, calendar: Calendar) -> Date? {
        let parts = dateString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private static func formatDate(_ components: DateComponents) -> String {
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
