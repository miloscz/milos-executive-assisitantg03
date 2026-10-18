import Foundation

/// Local inclusive day selection is exposed as [local midnight, next local midnight).
/// Never add 86400 seconds: Prague days can have 23 or 25 hours.
public struct CalendarInterval: Codable, Equatable {
    public let lower: Date
    public let upper: Date
    public init(lower: Date, upper: Date) throws {
        guard lower < upper, upper.timeIntervalSince(lower) <= 93 * 26 * 3600 else { throw ReadFailure.policyDenied }
        self.lower = lower; self.upper = upper
    }
    public init(window: DateWindow) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let from = f.date(from: window.dateFrom), let through = f.date(from: window.dateTo),
              let end = calendar.date(byAdding: .day, value: 1, to: through) else { throw ReadFailure.policyDenied }
        try self.init(lower: from, upper: end)
    }
    public static func instant(_ text: String?) throws -> Date {
        guard let text, text.utf8.count <= 40,
              text.range(of: #"T.*(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { throw ReadFailure.schemaMismatch }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: text) else { throw ReadFailure.schemaMismatch }; return date
    }
    public static func wire(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0); return f.string(from: date)
    }
    /// The documented command accepts date(), not a timestamp. Enclose the
    /// requested instants in UTC dates; filter the overfetch locally afterwards.
    public var enclosingDates: (from: String, to: String) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = calendar.startOfDay(for: lower), last = calendar.startOfDay(for: upper)
        let ceiling = last == upper ? last : calendar.date(byAdding: .day, value: 1, to: last)!
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return (f.string(from: first), f.string(from: ceiling))
    }
    /// Finite hypotheses only: never guess a server time zone from a successful
    /// HTTP response. The live diagnostic reports every matching model.
    public static func dateModels(window: DateWindow) throws -> [(name: String, bounds: CalendarInterval)] {
        var result: [(String, CalendarInterval)] = []
        for (name, zone) in [("utc", "UTC"), ("prague", "Europe/Prague")] {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
            let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
            f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
            guard let lower = f.date(from: window.dateFrom), let to = f.date(from: window.dateTo),
                  let afterTo = cal.date(byAdding: .day, value: 1, to: to) else { throw ReadFailure.schemaMismatch }
            if lower < to { result.append((name + "Midnight", try .init(lower: lower, upper: to))) }
            result.append((name + "InclusiveDay", try .init(lower: lower, upper: afterTo.addingTimeInterval(-0.001))))
        }
        return result
    }
    public func includes(_ record: NormalizedRecord, documentedPredicate: Bool = false) throws -> Bool {
        let start = try Self.instant(record.startTime), end = try Self.instant(record.endTime)
        guard end >= start else { throw ReadFailure.schemaMismatch }
        if documentedPredicate {
            return (start < lower && end > lower) || (start < upper && end > upper) || (start >= lower && end <= upper)
        }
        // A point belongs only to its local day; touching intervals do not overlap.
        return start == end ? start >= lower && start < upper : start < upper && end > lower
    }
    public func ids(_ records: [NormalizedRecord], documentedPredicate: Bool = false) throws -> Set<String> {
        var ids = Set<String>()
        for record in records where try includes(record, documentedPredicate: documentedPredicate) { ids.insert(record.id) }
        return ids
    }
}
