import Foundation

protocol BrainAPI: Sendable {
  func session() async throws -> PlayerProfile
  func rename(_ name: String) async throws -> PlayerProfile
  func recentMatches() async throws -> [RecentMatch]
  func createMatch(mode: MatchMode) async throws -> BattleMatch
  func match(id: String) async throws -> BattleMatch
  func startRound(matchID: String, number: Int) async throws -> BattleMatch
  func submit(matchID: String, number: Int, answer: Int, submissionID: UUID) async throws
    -> BattleMatch
  func invitation(token: String) async throws -> Invitation
  func claim(token: String) async throws -> BattleMatch
  func rematch(id: String) async throws -> BattleMatch
}

struct APIError: LocalizedError, Sendable {
  let status: Int
  let message: String
  var errorDescription: String? { message }
}

/// Refuse redirects so credentials cannot follow a server redirect to another origin.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

actor APIClient: BrainAPI {
  private struct ErrorBody: Decodable { let error: String }
  let baseURL: URL
  private let transport: URLSession
  private let credentials: any SessionStoring

  init(baseURL: URL, credentials: (any SessionStoring)? = nil, transport: URLSession? = nil) {
    self.baseURL = baseURL
    self.credentials = credentials ?? KeychainSessionStore(account: baseURL.absoluteString)
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 25
    self.transport =
      transport
      ?? URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
  }

  private func request<T: Decodable & Sendable>(
    _ path: String, method: String = "GET", body: Data? = nil
  ) async throws -> T {
    let url = baseURL.appendingPathComponent("api").appendingPathComponent(path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    let token = try credentials.read()
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await transport.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw APIError(status: 0, message: "The server returned an invalid response.")
    }
    if let rotated = http.value(forHTTPHeaderField: "X-Brain-Session") {
      try credentials.write(rotated)
    }
    guard (200..<300).contains(http.statusCode) else {
      let message =
        (try? JSONDecoder().decode(ErrorBody.self, from: data).error)
        ?? "The server could not complete this request (\(http.statusCode))."
      throw APIError(status: http.statusCode, message: message)
    }
    if path == "native/session", token == nil,
      http.value(forHTTPHeaderField: "X-Brain-Session") == nil
    {
      throw APIError(
        status: 0,
        message: "This backend does not support native sessions yet. Update the Fastify server.")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func encode<T: Encodable>(_ body: T) throws -> Data { try JSONEncoder().encode(body) }
  func session() async throws -> PlayerProfile {
    try await request("native/session", method: "POST")
  }
  func rename(_ name: String) async throws -> PlayerProfile {
    try await request("profile", method: "PATCH", body: encode(["name": name]))
  }
  func recentMatches() async throws -> [RecentMatch] { try await request("matches") }
  func createMatch(mode: MatchMode) async throws -> BattleMatch {
    try await request("matches", method: "POST", body: encode(["mode": mode.rawValue]))
  }
  func match(id: String) async throws -> BattleMatch { try await request("matches/\(id)") }
  func startRound(matchID: String, number: Int) async throws -> BattleMatch {
    try await request("matches/\(matchID)/rounds/\(number)/start", method: "POST")
  }
  func submit(matchID: String, number: Int, answer: Int, submissionID: UUID) async throws
    -> BattleMatch
  {
    struct Body: Encodable {
      let answer: Int
      let submissionId: String
    }
    return try await request(
      "matches/\(matchID)/rounds/\(number)/attempt", method: "POST",
      body: encode(Body(answer: answer, submissionId: submissionID.uuidString)))
  }
  func invitation(token: String) async throws -> Invitation {
    try await request("invitations/\(token)")
  }
  func claim(token: String) async throws -> BattleMatch {
    try await request("invitations/\(token)/claim", method: "POST")
  }
  func rematch(id: String) async throws -> BattleMatch {
    try await request("matches/\(id)/rematch", method: "POST")
  }
}

// Live HTTP bootstrapping reuses the existing authenticated URLSession and Keychain.
extension APIClient {
  func createLiveRoom(roundCount: Int = 5, mode: String = "duel", capacity: Int = 2) async throws
    -> LiveSnapshot
  {
    struct Body: Encodable {
      let roundCount: Int
      let mode: String
      let capacity: Int
    }
    return try await request(
      "live/rooms", method: "POST",
      body: encode(Body(roundCount: roundCount, mode: mode, capacity: capacity)))
  }
  func joinLiveRoom(code: String) async throws -> LiveSnapshot {
    guard let code = LiveRoomCode.parse(code) else {
      throw APIError(status: 400, message: "Enter a six-character room code.")
    }
    return try await request(
      "live/rooms/\(code)/join", method: "POST", body: encode([String: String]()))
  }
  func liveCredential() throws -> String {
    guard let token = try credentials.read() else {
      throw APIError(status: 401, message: "Restore your guest session first.")
    }
    return token
  }
}
