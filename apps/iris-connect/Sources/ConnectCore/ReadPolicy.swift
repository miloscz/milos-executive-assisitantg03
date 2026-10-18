import Foundation
import CryptoKit
import CoreFoundation

public enum ReadFailure: String, Error, Codable {
    case policyDenied, loginRequired, bindingRequired, pairingRequired, forbidden, transport, httpFailure
    case responseTooLarge, deadline, rateLimited, schemaMismatch, unstablePages, recordLimit, contractPending, cancelled
}

public enum ReadOperation: String, Codable, CaseIterable {
    case calendar = "calendar.list", active = "tasks.listActive", final = "tasks.listFinal"
    public var command: String {
        switch self {
        case .calendar: return "uuDwRecord/listMyDiaryRecords"
        case .active: return "uuDwRecord/listActiveRecords"
        case .final: return "uuDwRecord/listFinalRecords"
        }
    }
}

public struct ReadRequest: Codable {
    public let operation: String
    public let dateFrom: String?
    public let dateTo: String?
    public let fresh: Bool?

    public init(operation: String, dateFrom: String? = nil, dateTo: String? = nil, fresh: Bool? = nil) {
        self.operation = operation; self.dateFrom = dateFrom; self.dateTo = dateTo; self.fresh = fresh
    }

    public static func parse(_ data: Data) throws -> ReadRequest {
        guard data.count <= 4096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["operation", "dateFrom", "dateTo", "fresh"]),
              !object.values.contains(where: { $0 is NSNull }),
              let request = try? JSONDecoder().decode(Self.self, from: data) else { throw ReadFailure.policyDenied }
        if let op = ReadOperation(rawValue: request.operation) {
            if op == .active && (request.dateFrom != nil || request.dateTo != nil) { throw ReadFailure.policyDenied }
            if op != .active { _ = try DateWindow(request: request) }
        } else {
            guard ["status", "diagnostics.verifyReads", "diagnostics.calendarBoundaries"].contains(request.operation),
                  request.dateFrom == nil, request.dateTo == nil, request.fresh == nil else { throw ReadFailure.policyDenied }
        }
        return request
    }
}

public struct DateWindow: Codable, Equatable {
    public let dateFrom: String
    public let dateTo: String
    public let timezone: String

    public init(request: ReadRequest, now: Date = Date()) throws {
        timezone = "Europe/Prague"
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone)!
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        let today = calendar.startOfDay(for: now)
        let history = request.operation == ReadOperation.final.rawValue
        let fromText = request.dateFrom ?? formatter.string(from: calendar.date(byAdding: .day, value: history ? -29 : -7, to: today)!)
        let toText = request.dateTo ?? formatter.string(from: calendar.date(byAdding: .day, value: history ? 0 : 30, to: today)!)
        guard fromText.count == 10, toText.count == 10,
              let from = formatter.date(from: fromText), let to = formatter.date(from: toText),
              formatter.string(from: from) == fromText, formatter.string(from: to) == toText,
              let days = calendar.dateComponents([.day], from: from, to: to).day,
              days >= 0, days < 93 else { throw ReadFailure.policyDenied }
        dateFrom = fromText; dateTo = toText
    }
}

public enum ReadPolicy {
    public static let id = "iris-connect-read-v1"
    public static let approvedSHA256 = "6cf1ff32ab677fb78d5a7e840eb324b21bb237027e9a914f2bbb75bc4f6ef0db"
    public static let peopleBase = URL(string: "https://uuapp.plus4u.net/uu-plus4upeople-maing01/56ac93ddb0034de8b8e4f4b829ff7d0f")!

    public static func verifyApprovedSpecification(_ data: Data) -> Bool {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == approvedSHA256
    }

    public static func workspace(_ text: String) throws -> URL {
        let text = text.hasSuffix("/") ? String(text.dropLast()) : text
        guard let url = URL(string: text), let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "https", c.host == "uuapp.plus4u.net", c.port == nil,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.percentEncodedPath == c.path,
              c.path.range(of: "^/uu-myterritory-dwg01/(?:[0-9a-f]{32}-)?[0-9a-f]{32}$", options: .regularExpression) != nil,
              text == "https://uuapp.plus4u.net" + c.path else { throw ReadFailure.policyDenied }
        return url
    }

    public static func personWorkspace(_ object: [String: Any], identity: String) throws -> URL {
        guard let people = object["itemList"] as? [[String: Any]], people.count == 1,
              let person = people.first, person["uuIdentity"] as? String == identity,
              let value = person["mtDwBaseUri"] as? String else { throw ReadFailure.schemaMismatch }
        return try workspace(value)
    }

    public static func peopleURL(identity: String) throws -> URL {
        guard identity.range(of: "^[0-9]+-[0-9]+(?:-[0-9]+)?$", options: .regularExpression) != nil else { throw ReadFailure.loginRequired }
        var c = URLComponents(url: peopleBase.appendingPathComponent("people/findPerson"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "uuIdentity", value: identity)]
        return c.url!
    }

    public static func url(base: URL, operation: ReadOperation, window: DateWindow?, page: Int, calendarBounds: CalendarInterval? = nil) throws -> URL {
        let bound = try workspace(base.absoluteString)
        guard (0..<50).contains(page), (operation == .active) == (window == nil) else { throw ReadFailure.policyDenied }
        var c = URLComponents(url: bound.appendingPathComponent(operation.command), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [.init(name: "pageInfo", value: "{\"pageIndex\":\(page),\"pageSize\":200}")]
        guard calendarBounds == nil || operation == .calendar else { throw ReadFailure.policyDenied }
        if let bounds = calendarBounds {
            items += [.init(name: "dateFrom", value: CalendarInterval.wire(bounds.lower)), .init(name: "dateTo", value: CalendarInterval.wire(bounds.upper))]
        } else if let window { items += [.init(name: "dateFrom", value: window.dateFrom), .init(name: "dateTo", value: window.dateTo)] }
        if operation == .active { items.append(.init(name: "sorterList", value: "[{\"key\":\"startTime\",\"ascending\":false}]")) }
        c.queryItems = items
        guard let url = c.url else { throw ReadFailure.policyDenied }; return url
    }

    public static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue >= 0, number.doubleValue <= 10_000_000 else { return nil }
        return number.intValue
    }
}

public struct NormalizedRecord: Codable {
    public let id: String
    public let name: String
    public let description: String
    public let contentTruncated: Bool
    public let kind: String
    public let startTime: String?
    public let endTime: String?
    public let showInDiary: String?
    public let activityState: String?
    public let ownElementaryState: String?
    public let activityType: String?
    public let sourceURL: String?
    public let rejected: Bool?
    public let cancelled: Bool

    public init(_ raw: [String: Any]) throws {
        guard let id = raw["id"] as? String, !id.isEmpty, id.utf8.count <= 256 else { throw ReadFailure.schemaMismatch }
        self.id = id
        func text(_ value: Any?, limit: Int) -> String {
            guard let value = value as? String else { return "" }
            let plain = value.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            return String(decoding: plain.utf8.prefix(limit), as: UTF8.self)
        }
        let tile = raw["tileProps"] as? [String: Any] ?? [:]
        name = text(raw["name"], limit: 4096)
        description = text(raw["desc"], limit: 32768)
        contentTruncated = (raw["desc"] as? String ?? "").utf8.count > 32768
        activityType = tile["activityTypeCode"] as? String
        showInDiary = raw["showInDiary"] as? String
        kind = activityType == "reserveTime" ? "reservationOrInvitation" : "unknown"
        startTime = raw["startTime"] as? String; endTime = raw["endTime"] as? String
        activityState = tile["activityStateCode"] as? String
        ownElementaryState = tile["elementaryActivityStateCode"] as? String
        rejected = raw["rejected"] as? Bool
        cancelled = tile["artifactStateCode"] as? String == "cancelled"
        let source = (tile["appUri"] as? String) ?? (raw["routeUri"] as? String)
        // A navigable source is data only; no credentials, fragment or unreviewed query is exported.
        if let source, var c = URLComponents(string: source), c.scheme == "https", c.user == nil, c.password == nil {
            c.fragment = nil
            c.queryItems = c.queryItems?.filter { ["id", "code", "oid", "bid"].contains($0.name) }
            sourceURL = c.url?.absoluteString
        } else { sourceURL = nil }
    }
}

public struct RecordPage {
    public let records: [NormalizedRecord]
    public let total: Int
    public init(_ object: [String: Any], operation: ReadOperation, page: Int) throws {
        func validate(_ info: Any?, count: Int) throws -> Int {
            guard let info = info as? [String: Any],
                  ReadPolicy.integer(info["pageIndex"]) == page, ReadPolicy.integer(info["pageSize"]) == 200,
                  let total = ReadPolicy.integer(info["total"] ?? info["recordsTotal"]),
                  count == min(200, max(0, total - page * 200)) else { throw ReadFailure.schemaMismatch }
            return total
        }
        let raw: [[String: Any]]
        let total: Int
        if operation == .calendar {
            guard let active = object["uuDwrActiveList"] as? [[String: Any]],
                  let final = object["uuDwrFinalList"] as? [[String: Any]] else { throw ReadFailure.schemaMismatch }
            raw = active + final
            total = try validate(object["uuDwrActiveListPageInfo"], count: active.count)
                + validate(object["uuDwrFinalListPageInfo"], count: final.count)
        } else {
            guard let values = object["uuDwRecordList"] as? [[String: Any]] else { throw ReadFailure.schemaMismatch }
            raw = values
            total = try validate(object["pageInfo"], count: values.count)
        }
        records = try raw.map(NormalizedRecord.init); self.total = total
    }
}

public struct PageAccumulator {
    public private(set) var records: [NormalizedRecord] = []
    public private(set) var pages = 0
    private var total: Int?
    private var ids = Set<String>()
    public init() {}
    public mutating func append(_ page: RecordPage) throws -> Bool {
        guard total == nil || total == page.total else { throw ReadFailure.unstablePages }
        guard records.count + page.records.count <= 10000 else { throw ReadFailure.recordLimit }
        total = page.total
        for record in page.records {
            guard ids.insert(record.id).inserted else { throw ReadFailure.unstablePages }
            records.append(record)
        }
        pages += 1
        guard records.count <= page.total else { throw ReadFailure.unstablePages }
        if records.count == page.total { return true }
        guard !page.records.isEmpty else { throw ReadFailure.unstablePages }
        guard pages < 50, records.count < 10000 else { throw ReadFailure.recordLimit }
        return false
    }
}
