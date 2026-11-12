import Foundation

/// Engine.IO v4 + Socket.IO v5, default namespace, JSON-only WebSocket transport.
/// This explicitly implements framing, namespace connect, heartbeat and acknowledgements.
/// No binary payloads, other namespaces, or transport upgrade are used by Brain Battle.
enum SocketIOWire {
  enum Packet {
    case open, connected, ping(String), event(String, Data), ack(Int, Data), ignored
  }
  static func decode(_ text: String) throws -> Packet {
    if text.hasPrefix("0{") { return .open }
    if text.hasPrefix("2") { return .ping(String(text.dropFirst())) }
    if text == "40" || text.hasPrefix("40{") { return .connected }
    if text == "1" || text.hasPrefix("41") || text.hasPrefix("44") {
      throw APIError(status: 0, message: "The live connection closed. Reconnecting…")
    }
    if text.hasPrefix("42[") {
      let array = try JSONSerialization.jsonObject(with: Data(text.dropFirst(2).utf8)) as? [Any]
      guard let array, array.count == 2, let event = array[0] as? String else {
        throw APIError(status: 0, message: "Invalid live event.")
      }
      return .event(event, try JSONSerialization.data(withJSONObject: array[1]))
    }
    if text.hasPrefix("43"), let bracket = text.firstIndex(of: "["),
      let id = Int(text[text.index(text.startIndex, offsetBy: 2)..<bracket]),
      let array = try JSONSerialization.jsonObject(with: Data(text[bracket...].utf8)) as? [Any],
      array.count == 1
    {
      return .ack(id, try JSONSerialization.data(withJSONObject: array[0]))
    }
    return .ignored
  }
  static func event(_ name: String, payload: Data, id: Int) throws -> String {
    let value = try JSONSerialization.jsonObject(with: payload)
    let data = try JSONSerialization.data(withJSONObject: [name, value])
    return "42\(id)" + String(decoding: data, as: UTF8.self)
  }
}

@MainActor final class LiveSocket {
  private let session: URLSession
  private var task: URLSessionWebSocketTask?
  private var lastPacket = ProcessInfo.processInfo.systemUptime
  private var sequence = 0
  private var pending: [Int: CheckedContinuation<LiveAck, Error>] = [:]
  private var timeouts: [Int: Task<Void, Never>] = [:]
  var stateReceived: (LiveSnapshot) -> Void = { _ in }
  var connected: () -> Void = {}

  init() {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.timeoutIntervalForRequest = 15
    session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
  }
  func run(baseURL: URL, credential: String) async throws {
    var url = URLComponents(
      url: baseURL.appendingPathComponent("socket.io/"), resolvingAgainstBaseURL: false)!
    url.scheme = baseURL.scheme == "https" ? "wss" : "ws"
    url.queryItems = [
      URLQueryItem(name: "EIO", value: "4"), URLQueryItem(name: "transport", value: "websocket"),
    ]
    var request = URLRequest(url: url.url!)
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    let socket = session.webSocketTask(with: request)
    task = socket
    socket.resume()
    defer { if task === socket { close() } }
    lastPacket = ProcessInfo.processInfo.systemUptime
    // Detect silent stalls too; Socket.IO's server heartbeat is every 25 seconds.
    let watchdog = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        if let self, ProcessInfo.processInfo.systemUptime - self.lastPacket > 50 {
          self.close()
          return
        }
      }
    }
    defer { watchdog.cancel() }
    while !Task.isCancelled {
      let message = try await socket.receive()
      lastPacket = ProcessInfo.processInfo.systemUptime
      guard case .string(let text) = message else { continue }
      switch try SocketIOWire.decode(text) {
      case .open: try await socket.send(.string("40"))
      case .connected: connected()
      case .ping(let payload): try await socket.send(.string("3" + payload))
      case .event(let name, let data):
        if name == "room:state" {
          stateReceived(try JSONDecoder().decode(LiveSnapshot.self, from: data))
        }
      case .ack(let id, let data):
        let ack = try JSONDecoder().decode(LiveAck.self, from: data)
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(returning: ack)
      case .ignored: break
      }
    }
  }
  func ask<T: Encodable>(_ event: String, _ value: T) async throws -> LiveAck {
    guard let socket = task else { throw APIError(status: 0, message: "Reconnecting…") }
    sequence += 1
    let id = sequence
    let packet = try SocketIOWire.event(event, payload: JSONEncoder().encode(value), id: id)
    let ack: LiveAck = try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      timeouts[id] = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(8)) } catch { return }
        self?.fail(id, error: APIError(status: 0, message: "No reply yet. Please retry."))
      }
      Task { [weak self] in
        do { try await socket.send(.string(packet)) } catch { self?.fail(id, error: error) }
      }
    }
    guard ack.ok else {
      throw APIError(
        status: ack.status ?? 409, message: ack.error ?? "The room could not be updated.")
    }
    return ack
  }
  private func fail(_ id: Int, error: Error) {
    timeouts.removeValue(forKey: id)?.cancel()
    pending.removeValue(forKey: id)?.resume(throwing: error)
  }
  func close() {
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    for id in Array(pending.keys) { fail(id, error: CancellationError()) }
  }
}
