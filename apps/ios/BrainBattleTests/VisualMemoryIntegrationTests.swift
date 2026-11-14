import XCTest

@testable import BrainBattle

/// Actual Swift Socket.IO clients against the isolated in-memory test API on 4016.
@MainActor final class VisualMemoryIntegrationTests: XCTestCase {
  private struct Basic: Encodable {
    let action: String
    var ready: Bool? = nil
  }
  private struct Envelope<C: Encodable>: Encodable {
    let code: String
    let command: C
  }
  private func command<C: Encodable>(_ socket: LiveSocket, _ code: String, _ command: C)
    async throws -> LiveSnapshot
  {
    let ack = try await socket.ask("room:command", Envelope(code: code, command: command))
    return try XCTUnwrap(ack.state)
  }
  private func wait(_ predicate: @MainActor () -> Bool) async throws {
    for _ in 0..<150 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("Timed out waiting for authoritative Visual Memory state")
    throw APIError(status: 0, message: "Visual Memory test timed out")
  }
  func testNativeVisualMemoryDuel() async throws { try await play(players: 2) }
  func testNativeVisualMemoryParty() async throws { try await play(players: 3) }
  private func play(players count: Int) async throws {
    #if !DEBUG
      throw XCTSkip("Uses only the isolated Debug API on 4016.")
    #else
      let base = URL(string: "http://127.0.0.1:4016")!
      var clients: [APIClient] = []
      var profiles: [PlayerProfile] = []
      var stores: [MemoryCredentials] = []
      for _ in 0..<count {
        let store = MemoryCredentials()
        let api = APIClient(baseURL: base, credentials: store)
        do { profiles.append(try await api.session()) } catch {
          throw XCTSkip("Start scripts/visual-memory-fixture.ts: \(error.localizedDescription)")
        }
        stores.append(store)
        clients.append(api)
      }
      let created = try await clients[0].createLiveRoom(
        mode: count == 2 ? "duel" : "party",
        capacity: count, format: "visual-memory")
      for i in 1..<count { _ = try await clients[i].joinLiveRoom(code: created.code) }
      let sockets = (0..<count).map { _ in LiveSocket() }
      var states = [LiveSnapshot?](repeating: nil, count: count)
      var ready = Array(repeating: false, count: count)
      var handshakeError: Error?
      var runs: [Task<Void, Error>] = []
      defer {
        runs.forEach { $0.cancel() }
        for socket in sockets {
          socket.close()
          socket.connected = {}
          socket.stateReceived = { _ in }
        }
      }
      for i in 0..<count {
        let socket = sockets[i]
        socket.stateReceived = { states[i] = $0 }
        socket.connected = {
          Task {
            do {
              states[i] = try await socket.ask("room:watch", ["code": created.code]).state
              _ = try await self.command(socket, created.code, Basic(action: "ready", ready: true))
              ready[i] = true
            } catch { handshakeError = error }
          }
        }
        let credential = try XCTUnwrap(stores[i].read())
        runs.append(Task { try await socket.run(baseURL: base, credential: credential) })
      }
      try await wait { ready.allSatisfy { $0 } || handshakeError != nil }
      if let handshakeError { throw handshakeError }
      let started = try await command(sockets[0], created.code, Basic(action: "start"))
      XCTAssertNotNil(started.memory?.endsAt)
      var patterns: [[Int]] = []
      for i in 0..<count {
        let view = try await sockets[i].ask("room:watch", ["code": created.code])
        let own = try XCTUnwrap(view.state?.memory?.players.first { $0.playerId == profiles[i].id })
        patterns.append(try XCTUnwrap(own.highlighted))
        XCTAssertEqual(own.lives, 3)
        XCTAssertTrue(
          view.state!.memory!.players.filter { $0.playerId != profiles[i].id }.allSatisfy {
            $0.highlighted == nil
          })
      }
      XCTAssertTrue(patterns.allSatisfy { $0 == patterns[0] })
      try await wait { states.allSatisfy { $0?.memory?.players.first?.phase == "recall" } }
      for i in 0..<count {
        for tile in patterns[i] {
          _ = try await command(
            sockets[i], created.code,
            MemoryCommand(action: "memory-tap", level: 1, attempt: 1, tile: tile))
        }
      }
      try await wait { states[0]?.memory?.players.allSatisfy { $0.level == 2 } == true }
      for attempt in 1...3 {
        try await wait {
          states[0]?.memory?.players.first?.phase == "recall"
            && states[0]?.memory?.players.first?.attempt == attempt
        }
        let state = try await sockets[0].ask("room:watch", ["code": created.code])
        XCTAssertEqual(state.state?.memory?.players.first?.lives, 4 - attempt)
        // A confirmed retry is the interruption recovery path, with a server-owned heart cost.
        _ = try await command(
          sockets[0], created.code,
          MemoryCommand(action: "memory-retry", level: 2, attempt: attempt))
      }
      try await wait { states[0]?.memory?.players.first?.phase == "finished" }
      XCTAssertEqual(states[0]?.status, "running")
      for i in 1..<count { _ = try await command(sockets[i], created.code, Basic(action: "leave")) }
      try await wait { states[0]?.status == "completed" }
      let final = try XCTUnwrap(states[0])
      XCTAssertEqual(final.memory?.players.first?.lives, 0)
      XCTAssertEqual(final.memory?.players.first?.level, 2)
      XCTAssertEqual(final.memory?.players.first?.score, 1000)
      XCTAssertEqual(final.standings.first?.rank, 1)
      let rematchA = try await command(sockets[0], created.code, Basic(action: "rematch"))
      let rematchB = try await command(sockets[1], created.code, Basic(action: "rematch"))
      XCTAssertEqual(rematchA.rematchCode, rematchB.rematchCode)
      let rematch = try await clients[1].joinLiveRoom(code: XCTUnwrap(rematchA.rematchCode))
      XCTAssertEqual(rematch.format, "visual-memory")
      XCTAssertEqual(rematch.status, "lobby")
    #endif
  }
}
