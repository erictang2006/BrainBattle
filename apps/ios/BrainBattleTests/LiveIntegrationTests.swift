import XCTest

@testable import BrainBattle

/// Creates fresh guests and rooms only. Debug uses the local API; Release verifies the configured beta API.
@MainActor final class LiveIntegrationTests: XCTestCase {
  func testTwoNativeSocketIOGuestsReconnectAndFinalizeSameRound() async throws {
    #if DEBUG
      let url = URL(string: "http://127.0.0.1:4000")!
    #else
      let url = AppConfiguration.current.apiURL
      XCTAssertEqual(url.scheme, "https")
      XCTAssertFalse(url.host?.hasSuffix(".invalid") ?? true)
    #endif
    let storeA = MemoryCredentials()
    let storeB = MemoryCredentials()
    let a = APIClient(baseURL: url, credentials: storeA)
    let b = APIClient(baseURL: url, credentials: storeB)
    let profileA: PlayerProfile
    do { profileA = try await a.session() } catch {
      #if DEBUG
        throw XCTSkip(
          "Start the local API for live Socket.IO integration: \(error.localizedDescription)")
      #else
        throw error
      #endif
    }
    let restored = try await a.session()
    XCTAssertEqual(restored.id, profileA.id)
    let profileB = try await b.session()
    XCTAssertNotEqual(profileA.id, profileB.id)
    let room = try await a.createLiveRoom(roundCount: 1)
    _ = try await b.joinLiveRoom(code: room.code)
    let socketA = LiveSocket()
    let socketB = LiveSocket()
    var stateA: LiveSnapshot?
    var stateB: LiveSnapshot?
    var readyA = false
    var readyB = false
    var handshakeError: Error?
    socketA.stateReceived = { stateA = $0 }
    socketB.stateReceived = { stateB = $0 }
    socketA.connected = {
      Task {
        do {
          let clock = try await socketA.ask("clock:sync", [String: String]())
          XCTAssertNotNil(clock.serverNow)
          let watched = try await socketA.ask("room:watch", ["code": room.code])
          stateA = watched.state
          if watched.state?.status == "lobby" {
            _ = try await socketA.ask(
              "room:command", Command(code: room.code, command: .init(action: "ready", ready: true))
            )
          }
          readyA = true
        } catch { handshakeError = error }
      }
    }
    socketB.connected = {
      Task {
        do {
          _ = try await socketB.ask("room:watch", ["code": room.code])
          _ = try await socketB.ask(
            "room:command", Command(code: room.code, command: .init(action: "ready", ready: true)))
          readyB = true
        } catch { handshakeError = error }
      }
    }
    let tokenA = try XCTUnwrap(storeA.read())
    let tokenB = try XCTUnwrap(storeB.read())
    var runA = Task { try await socketA.run(baseURL: url, credential: tokenA) }
    let runB = Task { try await socketB.run(baseURL: url, credential: tokenB) }
    defer {
      runA.cancel()
      runB.cancel()
      socketA.close()
      socketB.close()
    }
    try await wait { (readyA && readyB) || handshakeError != nil }
    if let handshakeError { throw handshakeError }
    let start = try await socketA.ask(
      "room:command", Command(code: room.code, command: .init(action: "start")))
    let round = try XCTUnwrap(start.state?.round)
    try await wait { stateB?.status == "running" }
    XCTAssertEqual(stateB?.round?.puzzle, round.puzzle)
    let answer = try XCTUnwrap(round.puzzle?.cubes.count)
    runA.cancel()
    socketA.close()
    readyA = false
    runA = Task { try await socketA.run(baseURL: url, credential: tokenA) }
    try await wait { readyA || handshakeError != nil }
    // Reconnect watches the existing schedule without starting or resetting the round.
    XCTAssertEqual(stateA?.round?.deadline, round.deadline)
    let delay = max(0, (round.displayUntil - Date().timeIntervalSince1970 * 1000 + 150) / 1000)
    try await Task.sleep(for: .seconds(delay))
    let commandA = Command(
      code: room.code,
      command: .init(action: "submit", round: 1, answer: answer, submissionId: UUID().uuidString))
    let first = try await socketA.ask("room:command", commandA)
    XCTAssertNil(first.state?.round?.results)
    _ = try await socketA.ask("room:command", commandA)
    _ = try await socketB.ask(
      "room:command",
      Command(
        code: room.code,
        command: .init(action: "submit", round: 1, answer: answer, submissionId: UUID().uuidString))
    )
    try await wait { stateA?.status == "completed" && stateB?.status == "completed" }
    XCTAssertEqual(stateA?.round?.deadline, round.deadline)
    XCTAssertEqual(stateA?.round?.results?.map(\.score), stateB?.round?.results?.map(\.score))
    XCTAssertTrue(stateA?.round?.results?.allSatisfy { $0.correct && $0.score > 0 } ?? false)
  }
  private struct Command: Encodable {
    let code: String
    let command: Body
    struct Body: Encodable {
      let action: String
      var ready: Bool? = nil
      var round: Int? = nil
      var answer: Int? = nil
      var submissionId: String? = nil
    }
  }
  private func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<150 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw APIError(status: 0, message: "Timed out waiting for native live state.")
  }
}
