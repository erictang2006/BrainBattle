import Security
import XCTest

@testable import BrainBattle

final class MemoryCredentials: SessionStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var value: String?
  func read() throws -> String? { lock.withLock { value } }
  func write(_ token: String) throws { lock.withLock { value = token } }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (response, data) = try Self.handler!(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

final class NetworkingTests: XCTestCase {
  private func client(store: MemoryCredentials) -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return APIClient(
      baseURL: URL(string: "https://api.example")!, credentials: store,
      transport: URLSession(configuration: config))
  }
  override func tearDown() {
    StubProtocol.handler = nil
    super.tearDown()
  }
  func testNativeSessionPersistsAndRotatesBearerCredential() async throws {
    let store = MemoryCredentials()
    let tested = client(store: store)
    StubProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/api/native/session")
      XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
      return (
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil,
          headerFields: ["X-Brain-Session": "signed-session-1"])!,
        Data(#"{"id":"a","name":"Guest"}"#.utf8)
      )
    }
    _ = try await tested.session()
    XCTAssertEqual(try store.read(), "signed-session-1")
    StubProtocol.handler = { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer signed-session-1")
      return (
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil,
          headerFields: ["X-Brain-Session": "signed-session-2"])!, Data("[]".utf8)
      )
    }
    _ = try await tested.recentMatches()
    XCTAssertEqual(try store.read(), "signed-session-2")
  }
  func testServerErrorsDoNotEraseExistingGuest() async throws {
    let store = MemoryCredentials()
    try store.write("existing")
    StubProtocol.handler = { request in
      (
        HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
        Data(#"{"error":"Session unavailable"}"#.utf8)
      )
    }
    do {
      _ = try await client(store: store).session()
      XCTFail("Expected 401")
    } catch let error as APIError { XCTAssertEqual(error.status, 401) }
    XCTAssertEqual(try store.read(), "existing")
  }
  func testKeychainRoundTrip() throws {
    let account = "unit-test-\(UUID().uuidString)"
    defer {
      SecItemDelete(
        [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.brainbattle.native-session",
          kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
    let store = KeychainSessionStore(account: account)
    XCTAssertNil(try store.read())
    try store.write("one")
    XCTAssertEqual(try store.read(), "one")
    try store.write("two")
    XCTAssertEqual(try store.read(), "two")
  }
}
