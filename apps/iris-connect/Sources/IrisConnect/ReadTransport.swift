import Foundation
import ConnectCore

private final class NoReadRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Only this native component attaches the bearer. No response body is ever logged.
actor ReadTransport {
    private let delegate = NoReadRedirects()
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration }
    private lazy var session: URLSession = {
        let config = configuration
        config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    private var recent: [Date] = []
    private var tokens = 4.0
    private var lastRefill = Date()
    private var occupied = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if occupied < 2 { occupied += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    private func release() {
        if waiting.isEmpty { occupied -= 1 } else { waiting.removeFirst().resume() }
    }

    private func throttle(deadline: Date) async throws {
        while true {
            try Task.checkCancellation()
            let now = Date()
            guard now < deadline else { throw ReadFailure.deadline }
            tokens = min(4, tokens + now.timeIntervalSince(lastRefill) * 0.5); lastRefill = now
            recent.removeAll { now.timeIntervalSince($0) >= 60 }
            if recent.count < 30, tokens >= 1 { recent.append(now); tokens -= 1; return }
            let delay = recent.count >= 30 ? max(0.05, 60 - now.timeIntervalSince(recent[0])) : max(0.05, (1 - tokens) * 2)
            guard now.addingTimeInterval(delay) < deadline else { throw ReadFailure.rateLimited }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    func person(identity: String, session: VerifiedSession) async throws -> [String: Any] {
        let (object, _) = try await get(try ReadPolicy.peopleURL(identity: identity), session: session, deadline: Date().addingTimeInterval(180))
        return object
    }

    func page(base: URL, operation: ReadOperation, window: DateWindow?, index: Int,
              session: VerifiedSession, deadline: Date) async throws -> ([String: Any], Int) {
        try await get(ReadPolicy.url(base: base, operation: operation, window: window, page: index), session: session, deadline: deadline)
    }

    private func get(_ url: URL, session auth: VerifiedSession, deadline: Date) async throws -> ([String: Any], Int) {
        await acquire(); defer { release() }
        for attempt in 0...2 {
            guard auth.expiresAt > Date() else { throw ReadFailure.loginRequired }
            try await throttle(deadline: deadline)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"; request.timeoutInterval = min(20, max(0.01, deadline.timeIntervalSinceNow))
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer " + auth.token, forHTTPHeaderField: "Authorization")
            var retryDelay = Double(1 << attempt)
            do {
                let (bytes, response) = try await session.bytes(for: request)
                defer { bytes.task.cancel() }
                guard let http = response as? HTTPURLResponse else { throw ReadFailure.httpFailure }
                if http.statusCode != 200 {
                    if http.statusCode == 401 { throw ReadFailure.loginRequired }
                    if http.statusCode == 403 { throw ReadFailure.forbidden }
                    if [429, 502, 503, 504].contains(http.statusCode), attempt < 2 {
                        if let after = http.value(forHTTPHeaderField: "Retry-After") {
                            if let seconds = Double(after), seconds.isFinite, seconds >= 0 { retryDelay = max(retryDelay, seconds) }
                            else {
                                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                                formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                                if let date = formatter.date(from: after) { retryDelay = max(retryDelay, date.timeIntervalSinceNow) }
                            }
                        }
                    } else { throw ReadFailure.httpFailure }
                    // Do not read an error body: it may contain private diagnostics.
                }
                if http.statusCode == 200 {
                    guard (http.mimeType ?? "").lowercased() == "application/json" else { throw ReadFailure.schemaMismatch }
                    guard response.expectedContentLength <= 4_194_304 else { throw ReadFailure.responseTooLarge }
                    var data = Data()
                    for try await byte in bytes {
                        guard data.count < 4_194_304 else { throw ReadFailure.responseTooLarge }
                        if data.count % 4096 == 0 {
                            try Task.checkCancellation()
                            guard Date() < deadline else { throw ReadFailure.deadline }
                        }
                        data.append(byte)
                    }
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadFailure.schemaMismatch }
                    // Unknown server warnings can indicate an ignored parameter, so fail closed.
                    if let errors = object["uuAppErrorMap"] as? [String: Any], !errors.isEmpty { throw ReadFailure.schemaMismatch }
                    return (object, data.count)
                }
            } catch let failure as ReadFailure { throw failure }
            catch is CancellationError { throw ReadFailure.cancelled }
            catch {
                guard attempt < 2 else { throw ReadFailure.transport }
            }
            guard Date().addingTimeInterval(retryDelay) < deadline else { throw ReadFailure.deadline }
            try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
        }
        throw ReadFailure.transport
    }
}
