import XCTest
@testable import NeoBili

final class NetworkingStartupTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    func testWBIMixinKeyIsReusedForTheWholeCalendarDay() throws {
        let savedAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 0, minute: 1))
        )
        let laterThatDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 23, minute: 59))
        )

        XCTAssertTrue(
            WBISigner.isCacheFresh(savedAt: savedAt, now: laterThatDay, calendar: calendar)
        )
    }

    func testWBIMixinKeyExpiresAcrossCalendarDayBoundary() throws {
        let savedAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 23, minute: 59))
        )
        let nextDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 0, minute: 1))
        )

        XCTAssertFalse(
            WBISigner.isCacheFresh(savedAt: savedAt, now: nextDay, calendar: calendar)
        )
    }
}
