import XCTest
import Darwin
@testable import ConnectCore

final class ReadPolicyTests: XCTestCase {
    let base = "https://uuapp.plus4u.net/uu-myterritory-dwg01/" + String(repeating: "a", count: 32)

    func testRequestsRejectEscapesAndUndocumentedParameters() throws {
        for value in [
            "{\"operation\":\"tasks.listActive\",\"url\":\"https://example.com\"}",
            "{\"operation\":\"tasks.listActive\",\"dateFrom\":\"2026-10-01\"}",
            "{\"operation\":\"tasks.listActive\",\"fresh\":1}",
            "{\"operation\":\"tasks.listActive\",\"fresh\":null}",
            "{\"operation\":\"uuDwRecord/delete\"}",
            "{\"operation\":\"status\",\"dateTo\":\"2026-10-01\"}"
        ] { XCTAssertThrowsError(try ReadRequest.parse(Data(value.utf8))) }
        XCTAssertEqual(try ReadRequest.parse(Data("{\"operation\":\"tasks.listActive\"}".utf8)).operation, "tasks.listActive")
    }

    func testBindingRejectsOtherOriginsAndAmbiguousIdentity() throws {
        XCTAssertNoThrow(try ReadPolicy.workspace(base))
        for value in [base + "?x=1", base + "#x", base + "/uuDwRecord/delete", base.replacingOccurrences(of: "https:", with: "http:"),
                      base.replacingOccurrences(of: "uuapp.plus4u.net", with: "user@uuapp.plus4u.net"),
                      base.replacingOccurrences(of: "uuapp.plus4u.net", with: "uuapp.plus4u.net:443"),
                      base.replacingOccurrences(of: "dwg01", with: "maing01"),
                      base.replacingOccurrences(of: "/uu-my", with: "/%75u-my")] {
            XCTAssertThrowsError(try ReadPolicy.workspace(value))
        }
        let selfPerson: [String: Any] = ["uuIdentity": "123-456", "mtDwBaseUri": base]
        XCTAssertNoThrow(try ReadPolicy.personWorkspace(["itemList": [selfPerson]], identity: "123-456"))
        XCTAssertThrowsError(try ReadPolicy.personWorkspace(["itemList": [selfPerson, selfPerson]], identity: "123-456"))
        XCTAssertThrowsError(try ReadPolicy.personWorkspace(["itemList": [selfPerson]], identity: "999-999"))
        XCTAssertThrowsError(try ReadPolicy.personWorkspace(["itemList": [["uuIdentity": "123-456", "dwUri": base]]], identity: "123-456"))
    }

    func testCalendarDatesAcrossDSTAndRangeLimit() throws {
        let r = ReadRequest(operation: "calendar.list", dateFrom: "2026-10-24", dateTo: "2026-10-26")
        XCTAssertEqual(try DateWindow(request: r).dateTo, "2026-10-26")
        for dates in [("2026-02-30", "2026-03-01"), ("2026-10-26", "2026-10-24"), ("2026-01-01", "2026-04-04")] {
            XCTAssertThrowsError(try DateWindow(request: .init(operation: "calendar.list", dateFrom: dates.0, dateTo: dates.1)))
        }
        XCTAssertNoThrow(try DateWindow(request: .init(operation: "calendar.list", dateFrom: "2026-01-01", dateTo: "2026-04-03")))
    }

    func testOnlyFixedGetDTOCanBeBuilt() throws {
        let url = try ReadPolicy.url(base: URL(string: base)!, operation: .active, window: nil, page: 1)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(Set(items.map(\.name)), ["pageInfo", "sorterList"])
        XCTAssertTrue(items.contains { $0.name == "pageInfo" && $0.value == "{\"pageIndex\":1,\"pageSize\":200}" })
        XCTAssertThrowsError(try ReadPolicy.url(base: URL(string: base)!, operation: .active, window: nil, page: 50))
        XCTAssertThrowsError(try ReadPolicy.url(base: URL(string: base)!, operation: .calendar, window: nil, page: 0))
        XCTAssertThrowsError(try ReadPolicy.peopleURL(identity: "other?name=x"))
    }

    private func page(_ index: Int, total: Int, ids: [Int]) throws -> RecordPage {
        try RecordPage(["uuDwRecordList": ids.map { ["id": "r\($0)", "name": "Synthetic"] },
                        "pageInfo": ["pageIndex": index, "pageSize": 200, "total": total]], operation: .active, page: index)
    }

    func testPaginationOver200AndUnstableOrMissingPage() throws {
        var accumulator = PageAccumulator()
        XCTAssertFalse(try accumulator.append(page(0, total: 201, ids: Array(0..<200))))
        XCTAssertTrue(try accumulator.append(page(1, total: 201, ids: [200])))
        XCTAssertEqual(accumulator.records.count, 201)
        var duplicate = PageAccumulator()
        _ = try duplicate.append(page(0, total: 201, ids: Array(0..<200)))
        XCTAssertThrowsError(try duplicate.append(page(1, total: 201, ids: [199])))
        var changed = PageAccumulator()
        _ = try changed.append(page(0, total: 201, ids: Array(0..<200)))
        XCTAssertThrowsError(try changed.append(page(1, total: 202, ids: [200, 201])))
        XCTAssertThrowsError(try page(1, total: 201, ids: []))
        XCTAssertThrowsError(try RecordPage(["uuDwRecordList": []], operation: .active, page: 0))
        XCTAssertNil(ReadPolicy.integer(true)); XCTAssertNil(ReadPolicy.integer(1.5))
    }

    func testDiaryHasTwoIndependentPageTotals() throws {
        let raw: [String: Any] = [
            "uuDwrActiveList": [["id": "active", "showInDiary": "dayBlock"]],
            "uuDwrFinalList": [["id": "final", "showInDiary": "timeBlock"]],
            "uuDwrActiveListPageInfo": ["pageIndex": 0, "pageSize": 200, "total": 1],
            "uuDwrFinalListPageInfo": ["pageIndex": 0, "pageSize": 200, "total": 1]
        ]
        var accumulator = PageAccumulator()
        XCTAssertTrue(try accumulator.append(RecordPage(raw, operation: .calendar, page: 0)))
        XCTAssertEqual(accumulator.records.map(\.showInDiary), ["dayBlock", "timeBlock"])
    }

    func testNormalizationDoesNotExportRawFieldsAndNeverInfersCompletion() throws {
        let record = try NormalizedRecord(["id": "synthetic", "name": "<b>Test</b>", "desc": String(repeating: "x", count: 33000),
                                           "tileProps": ["appUri": "https://example.com/?id=123&access_token=synthetic#secret"],
                                           "privateUnknown": "not exported"])
        XCTAssertTrue(record.contentTruncated); XCTAssertLessThanOrEqual(record.description.utf8.count, 32768)
        XCTAssertNil(record.ownElementaryState); XCTAssertEqual(record.kind, "unknown")
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertFalse(encoded.contains("privateUnknown")); XCTAssertFalse(encoded.contains("access_token"))
    }

    func testIPCFramingAndUnpairedProcessRejected() throws {
        var descriptors: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        defer { descriptors.forEach { close($0) } }
        LocalIPC.prepare(descriptors[0]); LocalIPC.prepare(descriptors[1])
        try LocalIPC.sendFrame(Data("synthetic".utf8), fd: descriptors[0])
        XCTAssertEqual(try LocalIPC.receiveFrame(fd: descriptors[1], maximum: 20), Data("synthetic".utf8))
        XCTAssertThrowsError(try LocalIPC.requirePeer(fd: descriptors[1], hash: String(repeating: "0", count: 40)))
        XCTAssertThrowsError(try LocalIPC.address(String(repeating: "a", count: 200)))
    }
}
