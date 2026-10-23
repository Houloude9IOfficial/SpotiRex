import Foundation
import XCTest
@testable import SpotiRex

final class MockVeloraProtocol: URLProtocol {
    static var receivedRequest: URLRequest?
    static var responseCode = 200
    static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.receivedRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class MemoryTokenStore: VeloraTokenStorage {
    var token: String?
    init(_ token: String?) { self.token = token }
    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}

@MainActor
final class VeloraClientTests: XCTestCase {
    func testReadEndpointUsesBearerTokenAndMapsCollaborators() async {
        MockVeloraProtocol.receivedRequest = nil
        MockVeloraProtocol.responseCode = 200
        MockVeloraProtocol.responseBody = Data(#"{"track":{"id":"track_1","title":"Glass Garden","artist":"Mira Sol, Ren Aoki","album":"Glasshouse","cover_url":"https://example.com/cover.jpg","is_playing":true}}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockVeloraProtocol.self]
        let client = VeloraClient(session: URLSession(configuration: configuration), tokenStore: MemoryTokenStore("test-read-token"), eventsEnabled: false)

        let result = await client.read()

        XCTAssertEqual(MockVeloraProtocol.receivedRequest?.url?.path, "/current-track")
        XCTAssertEqual(MockVeloraProtocol.receivedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-read-token")
        XCTAssertEqual(result.track?.title, "Glass Garden")
        XCTAssertEqual(result.track?.artists, "Mira Sol, Ren Aoki")
        XCTAssertEqual(result.track?.source, .velora)
    }

    func testPausedVeloraTrackDoesNotDisplay() async {
        MockVeloraProtocol.responseCode = 200
        MockVeloraProtocol.responseBody = Data(#"{"track":{"id":"track_1","title":"Glass Garden","artist":"Mira Sol","is_playing":false}}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockVeloraProtocol.self]
        let client = VeloraClient(session: URLSession(configuration: configuration), tokenStore: MemoryTokenStore("test-read-token"), eventsEnabled: false)

        let result = await client.read()

        XCTAssertNil(result.track)
        XCTAssertEqual(result.status, "Not playing")
    }

    func testRevokedAccessClearsStoredToken() async {
        MockVeloraProtocol.responseCode = 403
        MockVeloraProtocol.responseBody = Data(#"{"error":"revoked"}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockVeloraProtocol.self]
        let storage = MemoryTokenStore("test-read-token")
        let client = VeloraClient(session: URLSession(configuration: configuration), tokenStore: storage, eventsEnabled: false)

        let result = await client.read()

        XCTAssertNil(result.track)
        XCTAssertNil(storage.token)
        XCTAssertEqual(result.status, "Access revoked — reconnect in Settings")
    }
}
