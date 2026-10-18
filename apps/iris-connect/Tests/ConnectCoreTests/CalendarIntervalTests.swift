import XCTest
@testable import ConnectCore

final class CalendarIntervalTests: XCTestCase {
    func testEmptyWeekendDoesNotBlockWeekdayCalibration() throws {
        let record=try NormalizedRecord(["id":"synthetic","startTime":"2026-10-23T08:00:00Z","endTime":"2026-10-23T09:00:00Z"])
        let friday=try CalendarInterval.instant("2026-10-23T07:00:00Z")
        XCTAssertEqual(try CalendarInterval.calibrationOffset(wide:[record],active:[record],now:friday),0)
        XCTAssertThrowsError(try CalendarInterval.calibrationOffset(wide:[],active:[],now:friday))
    }
    func testDateOnlyQueryEnclosesPragueDayAndPreservesApprovedCommand() throws {
        let window = try DateWindow(request: .init(operation: "calendar.list", dateFrom: "2026-10-19", dateTo: "2026-10-19"))
        let bounds = try CalendarInterval(window: window)
        let base = URL(string: "https://uuapp.plus4u.net/uu-myterritory-dwg01/" + String(repeating: "a", count: 32))!
        let url = try ReadPolicy.url(base: base, operation: .calendar, window: window, page: 0, calendarBounds: bounds)
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url.lastPathComponent, "listMyDiaryRecords")
        XCTAssertEqual(Set(values.map(\.name)), ["pageInfo", "dateFrom", "dateTo"])
        XCTAssertEqual(values.first { $0.name == "dateFrom" }?.value, "2026-10-18")
        XCTAssertEqual(values.first { $0.name == "dateTo" }?.value, "2026-10-20")
        XCTAssertNoThrow(try ReadRequest.parse(Data(#"{"operation":"diagnostics.calendarBoundaries"}"#.utf8)))
        XCTAssertThrowsError(try ReadRequest.parse(Data(#"{"operation":"diagnostics.calendarBoundaries","dateFrom":"2026-10-19"}"#.utf8)))
        XCTAssertThrowsError(try ReadPolicy.url(base: base, operation: .active, window: nil, page: 0, calendarBounds: bounds))
        let longWindow = try DateWindow(request: .init(operation: "calendar.list", dateFrom: "2026-01-01", dateTo: "2026-04-03"))
        XCTAssertThrowsError(try ReadPolicy.url(base: base, operation: .calendar, window: longWindow, page: 0,
                                               calendarBounds: CalendarInterval(window: longWindow)))
    }
    func testDateEnclosureAcrossDSTAndExactUTCMidnight() throws {
        for (day, from, to) in [("2026-03-29", "2026-03-28", "2026-03-30"), ("2026-10-25", "2026-10-24", "2026-10-26")] {
            let range = try CalendarInterval(window: DateWindow(request: .init(operation: "calendar.list", dateFrom: day, dateTo: day)))
            XCTAssertEqual(range.enclosingDates.from, from); XCTAssertEqual(range.enclosingDates.to, to)
        }
        let range = try CalendarInterval(lower: CalendarInterval.instant("2026-10-19T00:00:00Z"), upper: CalendarInterval.instant("2026-10-20T00:00:00Z"))
        XCTAssertEqual(range.enclosingDates.from, "2026-10-19"); XCTAssertEqual(range.enclosingDates.to, "2026-10-20")
    }
    func testDateModelsDistinguishInclusiveEndAndDoNotGuessTimezone() throws {
        let window = try DateWindow(request: .init(operation: "calendar.list", dateFrom: "2026-10-19", dateTo: "2026-10-20"))
        let models = try CalendarInterval.dateModels(window: window)
        XCTAssertEqual(models.map(\.name), ["utcMidnight", "utcInclusiveDay", "pragueMidnight", "pragueInclusiveDay"])
        let onLastDay = try NormalizedRecord(["id":"onLastDay", "startTime":"2026-10-20T12:00:00Z", "endTime":"2026-10-20T13:00:00Z"])
        XCTAssertFalse(try models[0].bounds.includes(onLastDay, documentedPredicate:true))
        XCTAssertTrue(try models[1].bounds.includes(onLastDay, documentedPredicate:true))
        XCTAssertEqual(CalendarInterval.wire(models[2].bounds.lower), "2026-10-18T22:00:00.000Z")
        let dst = try CalendarInterval.dateModels(window: DateWindow(request: .init(operation: "calendar.list", dateFrom: "2026-10-25", dateTo: "2026-10-25")))
        let prague = dst.first { $0.name == "pragueInclusiveDay" }!.bounds
        XCTAssertEqual(prague.upper.timeIntervalSince(prague.lower), 25*3600-0.001, accuracy:0.00001)
        // Every supported server model must contain the requested local day,
        // including both DST transitions; ambiguous matches are safe to report.
        for day in ["2026-03-29", "2026-10-19", "2026-10-25"] {
            let local = try CalendarInterval(window: DateWindow(request: .init(operation: "calendar.list", dateFrom: day, dateTo: day)))
            let dates = local.enclosingDates
            let wire = try DateWindow(request: .init(operation: "calendar.list", dateFrom: dates.from, dateTo: dates.to))
            for model in try CalendarInterval.dateModels(window: wire) {
                XCTAssertLessThanOrEqual(model.bounds.lower, local.lower)
                XCTAssertGreaterThanOrEqual(model.bounds.upper, local.upper)
            }
        }
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
