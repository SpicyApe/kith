import XCTest
@testable import KithCore

final class TimeTests: XCTestCase {
    private func iso(_ s: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: s) else {
            fatalError("bad ISO8601 fixture: \(s)")
        }
        return date
    }

    // MARK: LocalDay.date

    func testDateInUTC() {
        // 2026-09-11T03:00:00Z is still 2026-09-11 in UTC itself.
        XCTAssertEqual(LocalDay.date(iso("2026-09-11T03:00:00Z"), tz: "UTC"), "2026-09-11")
    }

    func testDateInAmericaNewYork() {
        // EDT (UTC-4) in September: 03:00Z rolls back to the previous day locally.
        XCTAssertEqual(LocalDay.date(iso("2026-09-11T03:00:00Z"), tz: "America/New_York"), "2026-09-10")
    }

    func testDateInPacificAuckland() {
        // NZST (UTC+12) on Sept 11, 2026 — NZDT hasn't started yet (starts the last
        // Sunday of September). 03:00Z + 12h is still the same calendar day.
        XCTAssertEqual(LocalDay.date(iso("2026-09-11T03:00:00Z"), tz: "Pacific/Auckland"), "2026-09-11")
    }

    func testDateFallsBackToUTCForUnknownTimeZone() {
        XCTAssertEqual(LocalDay.date(iso("2026-09-11T03:00:00Z"), tz: "Not/AZone"), "2026-09-11")
    }

    // MARK: LocalDay.secondsUntilMidnight

    func testSecondsUntilMidnightThirtySecondsBefore() {
        XCTAssertEqual(LocalDay.secondsUntilMidnight(iso("2026-09-11T23:59:30Z"), tz: "UTC"), 30)
    }

    func testSecondsUntilMidnightAtExactMidnightIsAFullDay() {
        XCTAssertEqual(LocalDay.secondsUntilMidnight(iso("2026-09-11T00:00:00Z"), tz: "UTC"), 86_400)
    }

    // MARK: LocalDay.countdownText

    func testCountdownTextHoursAndMinutes() {
        XCTAssertEqual(LocalDay.countdownText(seconds: 33_120), "9h 12m")
    }

    func testCountdownTextMinutesOnly() {
        XCTAssertEqual(LocalDay.countdownText(seconds: 720), "12m")
    }

    func testCountdownTextUnderOneMinute() {
        XCTAssertEqual(LocalDay.countdownText(seconds: 30), "<1m")
    }

    func testCountdownTextExactlyOneHour() {
        XCTAssertEqual(LocalDay.countdownText(seconds: 3_600), "1h 0m")
    }

    // MARK: LocalDay.shift

    func testShiftAcrossAMonthBoundary() {
        XCTAssertEqual(LocalDay.shift("2026-01-31", by: 1), "2026-02-01")
    }

    func testShiftAcrossAYearBoundary() {
        XCTAssertEqual(LocalDay.shift("2026-12-31", by: 1), "2027-01-01")
    }

    func testShiftNegativeDaysAcrossAMonthBoundary() {
        // 2026 is not a leap year, so February has 28 days.
        XCTAssertEqual(LocalDay.shift("2026-03-01", by: -1), "2026-02-28")
    }

    func testShiftNegativeDaysWithinTheSameMonth() {
        XCTAssertEqual(LocalDay.shift("2026-09-11", by: -5), "2026-09-06")
    }

    // MARK: LocalDay.weekStart

    func testWeekStartOnAMondayReturnsItself() {
        XCTAssertEqual(LocalDay.weekStart("2026-09-07"), "2026-09-07") // Monday
    }

    func testWeekStartOnASundayReturnsThePreviousMonday() {
        XCTAssertEqual(LocalDay.weekStart("2026-09-13"), "2026-09-07") // Sunday
    }

    func testWeekStartOnAThursdayReturnsThatWeeksMonday() {
        XCTAssertEqual(LocalDay.weekStart("2026-09-10"), "2026-09-07") // Thursday
    }

    // MARK: LocalDay.weekdayName

    func testWeekdayName() {
        XCTAssertEqual(LocalDay.weekdayName("2026-09-11"), "Friday")
    }
}
