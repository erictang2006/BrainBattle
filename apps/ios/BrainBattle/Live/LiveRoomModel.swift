import Foundation
import Observation

@MainActor @Observable final class LiveRoomModel {
  let code: String
  let playerID: String
  let api: APIClient
  var room: LiveSnapshot?
  var connection = "Connecting…"
  var error: String?
  var busy = false
  var clock: ServerClock?
  var uncertainty: Double?
  var count = 0 { didSet { saveDraft() } }
  private var submissionID = UUID()
  private let socket = LiveSocket()
  private var handshake: Task<Void, Never>?
  private var draftPrefix: String
  private var draftKey: String
  private struct Draft: Codable {
    let count: Int
    let submissionID: UUID
  }
  var connected: Bool { connection == "Connected" }

  init(code: String, playerID: String, apiURL: URL) {
    self.code = code
    self.playerID = playerID
    self.api = APIClient(baseURL: apiURL)
    let prefix = "liveDraft.\(apiURL.absoluteString).\(playerID).\(code)"
    draftPrefix = prefix
    draftKey = prefix + ".1"
    if let data = UserDefaults.standard.data(forKey: draftKey),
      let draft = try? JSONDecoder().decode(Draft.self, from: data)
    {
      count = draft.count
      submissionID = draft.submissionID
    }
    socket.stateReceived = { [weak self] in self?.reconcile($0) }
    socket.connected = { [weak self] in
      self?.handshake?.cancel()
      self?.handshake = Task { await self?.subscribe() }
    }
  }
  private func saveDraft() {
    if let data = try? JSONEncoder().encode(Draft(count: count, submissionID: submissionID)) {
      UserDefaults.standard.set(data, forKey: draftKey)
    }
  }
  private func reconcile(_ state: LiveSnapshot) {
    guard state.code == code, state.revision >= (room?.revision ?? -1) else { return }
    if let number = state.round?.number, draftKey != draftPrefix + ".\(number)" {
      draftKey = draftPrefix + ".\(number)"
      if let data = UserDefaults.standard.data(forKey: draftKey),
        let draft = try? JSONDecoder().decode(Draft.self, from: data)
      {
        submissionID = draft.submissionID
        count = draft.count
      } else {
        submissionID = UUID()
        count = 0
      }
    }
    room = state
  }
  private func subscribe() async {
    do {
      var bestRTT = Double.infinity
      for _ in 0..<3 {
        let start = ProcessInfo.processInfo.systemUptime
        let ack = try await socket.ask("clock:sync", [String: String]())
        let end = ProcessInfo.processInfo.systemUptime
        guard let serverNow = ack.serverNow else { continue }
        let rtt = (end - start) * 1000
        if rtt < bestRTT {
          bestRTT = rtt
          clock = ServerClock(serverMilliseconds: serverNow + rtt / 2, uptime: end)
          uncertainty = rtt / 2
        }
      }
      guard clock != nil else {
        throw APIError(status: 0, message: "Could not synchronize the clock.")
      }
      let ack = try await socket.ask("room:watch", ["code": code])
      if let state = ack.state { reconcile(state) }
      connection = "Connected"
      error = nil
    } catch {
      if !Task.isCancelled {
        self.error = error.localizedDescription
        socket.close()
      }
    }
  }
  func run() async {
    var delay = 1
    while !Task.isCancelled {
      connection = room == nil ? "Connecting…" : "Reconnecting…"
      do {
        let profile = try await api.session()
        guard profile.id == playerID else {
          throw APIError(status: 401, message: "Guest identity changed. Return home to sign in.")
        }
        _ = try await api.joinLiveRoom(code: code)
        try await socket.run(baseURL: api.baseURL, credential: api.liveCredential())
      } catch let problem as APIError where [401, 403, 404, 409, 410].contains(problem.status) {
        self.error = problem.message
        break
      } catch {
        if Task.isCancelled { break }
        self.error = "Connection interrupted. Your deadline and attempt are preserved."
      }
      handshake?.cancel()
      guard !Task.isCancelled else { break }
      try? await Task.sleep(for: .seconds(delay))
      delay = min(delay * 2, 8)
    }
    stop()
  }
  func stop() {
    handshake?.cancel()
    socket.close()
    connection = "Offline"
  }
  func command(action: String, ready: Bool? = nil) async -> Bool {
    guard !busy, connected else { return false }
    busy = true
    defer { busy = false }
    struct Command: Encodable {
      let action: String
      var ready: Bool?
      var round: Int?
      var answer: Int?
      var submissionId: String?
    }
    struct Envelope: Encodable {
      let code: String
      let command: Command
    }
    var command = Command(action: action, ready: ready)
    if action == "submit" {
      command.round = room?.round?.number
      command.answer = count
      command.submissionId = submissionID.uuidString
      saveDraft()
    }
    do {
      let ack = try await socket.ask("room:command", Envelope(code: code, command: command))
      if let state = ack.state { reconcile(state) }
      error = nil
      return true
    } catch {
      self.error = error.localizedDescription
      // Refresh through the existing HTTP session endpoint; keep the same guest and submission UUID.
      if let problem = error as? APIError, problem.status == 401 { socket.close() }
      return false
    }
  }
}
