import XCTest
@testable import ConnectCore

final class CalendarIntervalTests: XCTestCase {
    func testUTCQueryPreservesApprovedCommandAndFixedDiagnosticHasNoArguments() throws {
        let window = try DateWindow(request: .init(operation: "calendar.list", dateFrom: "2026-10-19", dateTo: "2026-10-19"))
        let bounds = try CalendarInterval(window: window)
        let base = URL(string: "https://uuapp.plus4u.net/uu-myterritory-dwg01/" + String(repeating: "a", count: 32))!
        let url = try ReadPolicy.url(base: base, operation: .calendar, window: window, page: 0, calendarBounds: bounds)
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url.lastPathComponent, "listMyDiaryRecords")
        XCTAssertEqual(Set(values.map(\.name)), ["pageInfo", "dateFrom", "dateTo"])
        XCTAssertEqual(values.first { $0.name == "dateFrom" }?.value, "2026-10-18T22:00:00.000Z")
        XCTAssertEqual(values.first { $0.name == "dateTo" }?.value, "2026-10-19T22:00:00.000Z")
        XCTAssertNoThrow(try ReadRequest.parse(Data(#"{"operation":"diagnostics.calendarBoundaries"}"#.utf8)))
        XCTAssertThrowsError(try ReadRequest.parse(Data(#"{"operation":"diagnostics.calendarBoundaries","dateFrom":"2026-10-19"}"#.utf8)))
        XCTAssertThrowsError(try ReadPolicy.url(base: base, operation: .active, window: nil, page: 0, calendarBounds: bounds))
    }
    func testPragueMidnightsAndBothDSTChanges() throws {
        for (day, lower, upper, hours) in [
            ("2026-10-19", "2026-10-18T22:00:00.000Z", "2026-10-19T22:00:00.000Z", 24),
            ("2026-03-29", "2026-03-28T23:00:00.000Z", "2026-03-29T22:00:00.000Z", 23),
            ("2026-10-25", "2026-10-24T22:00:00.000Z", "2026-10-25T23:00:00.000Z", 25)
        ] {
            let range = try CalendarInterval(window: DateWindow(request: .init(operation: "calendar.list", dateFrom: day, dateTo: day)))
            XCTAssertEqual(CalendarInterval.wire(range.lower), lower)
            XCTAssertEqual(CalendarInterval.wire(range.upper), upper)
            XCTAssertEqual(range.upper.timeIntervalSince(range.lower), Double(hours * 3600))
        }
    }
    func testHalfOpenBoundariesOvernightAllDayAndPoints() throws {
        let range = try CalendarInterval(window: DateWindow(request: .init(operation: "calendar.list", dateFrom: "2026-10-19", dateTo: "2026-10-19")))
        func record(_ from: String, _ to: String) throws -> NormalizedRecord {
            try NormalizedRecord(["id": "synthetic", "startTime": from, "endTime": to, "showInDiary": "dayBlock"])
        }
        XCTAssertFalse(try range.includes(record("2026-10-18T21:00:00Z", "2026-10-18T22:00:00Z")))
        XCTAssertFalse(try range.includes(record("2026-10-19T22:00:00Z", "2026-10-19T23:00:00Z")))
        XCTAssertTrue(try range.includes(record("2026-10-18T21:00:00Z", "2026-10-18T23:00:00Z")))
        XCTAssertTrue(try range.includes(record("2026-10-17T21:00:00Z", "2026-10-20T23:00:00Z")))
        XCTAssertTrue(try range.includes(record("2026-10-18T22:00:00Z", "2026-10-19T22:00:00Z")))
        XCTAssertTrue(try range.includes(record("2026-10-18T22:00:00Z", "2026-10-18T22:00:00Z")))
        let atEnd = try record("2026-10-19T22:00:00Z", "2026-10-19T22:00:00Z")
        XCTAssertFalse(try range.includes(atEnd))
        XCTAssertTrue(try range.includes(atEnd, documentedPredicate: true))
        XCTAssertThrowsError(try range.includes(record("invalid", "2026-10-19T00:00:00Z")))
        XCTAssertThrowsError(try range.includes(record("2026-10-19T02:00:00Z", "2026-10-19T01:00:00Z")))
        XCTAssertThrowsError(try CalendarInterval.instant("2026-10-19T02:00:00"))
    }
}
