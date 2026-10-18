import Foundation

public enum AuthControlFailure: String, Error {
    case invalidRequest, unavailable, noticeRequired, noticeExpired, locked, credentialsRequired, alreadyAuthenticated, rateLimited
}

/// No credentials, tokens, arbitrary text, URLs or scripts can enter this protocol.
public struct AuthControlRequest: Codable {
    public let operation: String
    public let noticeID: UUID?
    public let requestID: UUID?
    public let directUserCommand: Bool?
    public init(operation: String, noticeID: UUID? = nil, requestID: UUID? = nil, directUserCommand: Bool? = nil) {
        self.operation = operation; self.noticeID = noticeID; self.requestID = requestID; self.directUserCommand = directUserCommand
    }
    public static func parse(_ data: Data) throws -> Self {
        guard data.count <= 2048, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let operation = object["operation"] as? String else { throw AuthControlFailure.invalidRequest }
        let allowed: Set<String>
        switch operation {
        case "status", "prepare": allowed = ["operation"]
        case "noticeSent": allowed = ["operation", "noticeID"]
        case "start": allowed = ["operation", "noticeID", "requestID", "directUserCommand"]
        default: throw AuthControlFailure.invalidRequest
        }
        guard Set(object.keys) == allowed,
              let request = try? JSONDecoder().decode(Self.self, from: data),
              operation != "noticeSent" || request.noticeID != nil,
              operation != "start" || (request.noticeID != nil && request.requestID != nil && request.directUserCommand == true)
        else { throw AuthControlFailure.invalidRequest }
        return request
    }
}

public struct AuthControlState: Codable {
    public enum Phase: String, Codable { case idle, awaitingNotice, awaitingUser, authenticating, authenticated, failed, cancelled, interrupted }
    public private(set) var phase: Phase = .idle
    public private(set) var eventID = UUID()
    public private(set) var noticeID: UUID?
    public private(set) var noticeExpiresAt: Date?
    public private(set) var requestID: UUID?
    public private(set) var workPending = false
    public private(set) var lastStartedAt: Date?
    public init() {}
    private mutating func changed() { eventID = UUID() }
    /// Restart never restores a start permit and never retries an interrupted login.
    public mutating func recover() {
        noticeID = nil; noticeExpiresAt = nil
        if phase == .authenticating { phase = .interrupted }
        else if workPending { phase = .awaitingNotice }
        else { phase = .idle }
        changed()
    }
    public mutating func prepare(sessionValid: Bool, now: Date) {
        guard !sessionValid, phase != .authenticating else { return }
        workPending = true
        if noticeID == nil || (noticeExpiresAt.map { now >= $0 } ?? false) || phase == .authenticated {
            noticeID = UUID(); noticeExpiresAt = nil; phase = .awaitingNotice; changed()
        }
    }
    public mutating func markNotice(_ id: UUID, now: Date) throws {
        guard id == noticeID, phase == .awaitingNotice || phase == .awaitingUser else { throw AuthControlFailure.noticeRequired }
        // Repeated delivery acknowledgment must not extend the authorization window.
        if phase == .awaitingNotice { noticeExpiresAt = now.addingTimeInterval(600); phase = .awaitingUser; changed() }
    }
    /// Returns false for a retry of the same request. It must never generate another MFA challenge.
    public mutating func start(notice: UUID, request: UUID, now: Date) throws -> Bool {
        if request == requestID { return false }
        guard phase == .awaitingUser, notice == noticeID else { throw AuthControlFailure.noticeRequired }
        guard let deadline = noticeExpiresAt, now < deadline else { throw AuthControlFailure.noticeExpired }
        guard lastStartedAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { throw AuthControlFailure.rateLimited }
        lastStartedAt = now; requestID = request; phase = .authenticating; noticeID = nil; noticeExpiresAt = nil; changed()
        return true
    }
    public mutating func began() { phase = .authenticating; noticeID = nil; noticeExpiresAt = nil; changed() }
    public mutating func finish(_ next: Phase) {
        phase = next; noticeID = nil; noticeExpiresAt = nil
        if next == .authenticated || next == .idle { workPending = false }
        changed()
    }
    public mutating func invalidateNotice() {
        noticeID = nil; noticeExpiresAt = nil
        if phase == .awaitingUser || phase == .awaitingNotice { phase = .idle }
        changed()
    }
}
