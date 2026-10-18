import XCTest
import Foundation
import ConnectCore
@testable import IrisConnect

private final class SyntheticProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))!
    static var attempts = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.attempts += 1
        let (status, headers, data) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ReadTransportTests: XCTestCase {
    let auth = VerifiedSession(token: "synthetic-not-a-real-token", expiresAt: Date().addingTimeInterval(1000), identity: "123-456")
    func transport() -> ReadTransport {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyntheticProtocol.self]
        SyntheticProtocol.attempts = 0
        return ReadTransport(configuration: config)
    }

    func testSelfOnlyURLAndNativeBearerWithNoErrorBodyExport() async throws {
        let transport = transport()
        SyntheticProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, ReadPolicy.peopleBase.path + "/people/findPerson")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-not-a-real-token")
            return (200, ["Content-Type": "application/json"], Data("{\"itemList\":[]}".utf8))
        }
        let result = try await transport.person(identity: "123-456", session: auth)
        XCTAssertNotNil(result["itemList"])
        XCTAssertEqual(SyntheticProtocol.attempts, 1)
    }

    func test401And403NeverRetryOrBroadenCommand() async throws {
        for status in [401, 403] {
            let transport = transport()
            SyntheticProtocol.handler = { _ in (status, [:], Data("synthetic private body must never escape".utf8)) }
            do { _ = try await transport.person(identity: "123-456", session: auth); XCTFail("Expected denial") }
            catch { XCTAssertEqual(error as? ReadFailure, status == 401 ? .loginRequired : .forbidden) }
            XCTAssertEqual(SyntheticProtocol.attempts, 1)
        }
    }

    func testUnexpectedMimeAndUnsupportedParameterWarningFailClosed() async throws {
        for (mime, body) in [("text/html", "<html>synthetic</html>"),
                             ("application/json", "{\"uuAppErrorMap\":{\"unsupportedKeys\":{\"type\":\"warning\"}}}")] {
            let transport = transport()
            SyntheticProtocol.handler = { _ in (200, ["Content-Type": mime], Data(body.utf8)) }
            do { _ = try await transport.person(identity: "123-456", session: auth); XCTFail("Expected schema failure") }
            catch { XCTAssertEqual(error as? ReadFailure, .schemaMismatch) }
        }
    }

    func testOversizedContentAndRetryAfterBeyondDeadline() async throws {
        let oversized = transport()
        SyntheticProtocol.handler = { _ in (200, ["Content-Type": "application/json", "Content-Length": "4194305"], Data()) }
        do { _ = try await oversized.person(identity: "123-456", session: auth); XCTFail("Expected byte limit") }
        catch { XCTAssertEqual(error as? ReadFailure, .responseTooLarge) }
        let limited = transport()
        SyntheticProtocol.handler = { _ in (429, ["Retry-After": "1000"], Data()) }
        do { _ = try await limited.person(identity: "123-456", session: auth); XCTFail("Expected deadline") }
        catch { XCTAssertEqual(error as? ReadFailure, .deadline) }
        XCTAssertEqual(SyntheticProtocol.attempts, 1)
    }
}
