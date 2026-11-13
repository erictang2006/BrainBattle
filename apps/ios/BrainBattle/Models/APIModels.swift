import Foundation

struct PlayerProfile: Codable, Hashable, Sendable, Identifiable {
  let id: String
  let name: String
}

struct Cube: Codable, Hashable, Sendable {
  let x: Int
  let y: Int
  let z: Int
}

/// Public render coordinates only. Generation and answer keys remain on the server.
struct CubePuzzle: Codable, Hashable, Sendable {
  let cubes: [Cube]
  var gridSize: Int? = nil
  static let illustration = CubePuzzle(
    cubes: (0..<3).flatMap { x in
      (0..<3).flatMap { z in
        (0..<(1 + min(x, z))).map { y in Cube(x: x, y: y, z: z) }
      }
    })
}

struct AttemptResult: Codable, Hashable, Sendable {
  let score: Int
  let correct: Bool
  let timedOut: Bool
}

enum RoundState: String, Codable, Sendable {
  case locked, ready, display, answer, done
}

struct RoundRules: Codable, Hashable, Sendable {
  let difficulty: String
  let displayMs: Double
  let answerMs: Double
  var answerTimeLimit: Bool? = nil
  let feedbackMs: Double
  let gridSize: Int?
}

struct AnswerReveal: Codable, Hashable, Sendable {
  let puzzle: CubePuzzle
  let correctAnswer: Int
  let submittedAnswer: Int?
}

struct GameRound: Codable, Hashable, Sendable, Identifiable {
  let number: Int
  let state: RoundState
  let displayUntil: Double?
  let deadline: Double?
  let puzzle: CubePuzzle?
  let attempt: AttemptResult?
  let opponent: AttemptResult?
  let finalized: Bool
  var rules: RoundRules? = nil
  var feedbackUntil: Double? = nil
  var reveal: AnswerReveal? = nil
  var id: Int { number }

  func phase(at milliseconds: Double) -> RoundState {
    if state == .display, let displayUntil, milliseconds >= displayUntil { return .answer }
    return state
  }

  func remaining(at milliseconds: Double) -> Int {
    let end = phase(at: milliseconds) == .display ? displayUntil : deadline
    return max(0, Int(ceil(((end ?? milliseconds) - milliseconds) / 1000)))
  }

  func inputAvailable(at milliseconds: Double) -> Bool {
    let current = phase(at: milliseconds)
    guard current == .display || current == .answer else { return false }
    if current == .answer && rules?.answerTimeLimit == false { return true }
    return remaining(at: milliseconds) > 0
  }
  /// Server rule metadata controls presentation; stored deadlines remain authoritative.
  func timeProgress(at milliseconds: Double) -> Double {
    let phase = phase(at: milliseconds)
    guard phase == .display || phase == .answer else { return 0 }
    let end = phase == .display ? displayUntil : deadline
    let duration =
      phase == .display ? (rules?.displayMs ?? 8000) : (deadline ?? 0) - (displayUntil ?? 0)
    guard let end, duration > 0 else { return 0 }
    return min(1, max(0, (end - milliseconds) / duration))
  }
}

struct BattleMatch: Codable, Hashable, Sendable, Identifiable {
  let id: String
  let mode: MatchMode
  let gameId: String
  let rulesVersion: Int
  let you: PlayerProfile
  let opponent: PlayerProfile?
  let rounds: [GameRound]
  let inviteUrl: String?
  let expiresAt: Double
  let complete: Bool
  let yoursComplete: Bool
  let total: Int
  let opponentTotal: Int?
  let winner: String?
  let serverNow: Double
  var supported: Bool {
    gameId == "counting-boxes"
      && (rulesVersion == 1
        || ((rulesVersion == 2 || rulesVersion == 3)
          && rounds.allSatisfy {
            guard let rules = $0.rules else { return false }
            return rules.displayMs > 0 && rules.answerMs > 0 && rules.gridSize == 5
              && (rulesVersion != 3 || rules.answerTimeLimit == false)
          }))
  }
  /// The existing server URL carries a secret invitation token. Extract it locally;
  /// native sharing never opens or publishes the URL's website origin.
  var invitationToken: String? {
    guard let inviteUrl, let url = URL(string: inviteUrl), let scheme = url.scheme,
      ["http", "https"].contains(scheme), url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil,
      url.path.split(separator: "/").count == 2,
      url.path.split(separator: "/").first == "invite"
    else { return nil }
    return InvitationLink.validToken(String(url.lastPathComponent))
  }
  var challengeShareText: String? { invitationToken.map(InvitationLink.shareText) }
}

enum MatchMode: String, Codable, Sendable { case challenge, solo }

struct Invitation: Decodable, Sendable {
  let hostName: String
  let claimed: Bool
  let expired: Bool
  let rounds: Int
}

struct RecentMatch: Decodable, Identifiable, Sendable {
  let id: String
  let mode: MatchMode
  let opponent: String?
  let createdAt: Double
}

/// Uses monotonic uptime: changing the device wall clock cannot buy display time.
struct ServerClock: Sendable {
  let serverMilliseconds: Double
  let receivedUptime: TimeInterval
  init(serverMilliseconds: Double, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    self.serverMilliseconds = serverMilliseconds
    self.receivedUptime = uptime
  }
  func milliseconds(uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
    serverMilliseconds + max(0, uptime - receivedUptime) * 1000
  }
}

enum InvitationLink {
  static func validToken(_ value: String) -> String? {
    let token = value.lowercased()
    return token.count == 48 && token.allSatisfy { "0123456789abcdef".contains($0) } ? token : nil
  }
  static func shareText(_ token: String) -> String {
    "Brain Battle challenge\nChallenge code: \(token)\nOpen Brain Battle → Have a challenge code? Paste this code to preview and accept. Five rounds, your own clock. This invitation is for one challenger."
  }
  static func token(from input: String, webOrigin: URL) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let token = validToken(trimmed) { return token }
    if trimmed.hasPrefix("Brain Battle challenge\n") {
      let codes = trimmed.split(separator: "\n").filter { $0.hasPrefix("Challenge code: ") }
      guard codes.count == 1 else { return nil }
      return validToken(String(codes[0].dropFirst("Challenge code: ".count)))
    }
    guard let url = URL(string: trimmed),
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
    else { return nil }
    let parts = url.path.split(separator: "/").map(String.init)
    let candidate: String
    if url.scheme?.lowercased() == "brainbattle", url.host == "invite", parts.count == 1 {
      candidate = parts[0]
    } else if url.scheme?.lowercased() == webOrigin.scheme?.lowercased(),
      url.host?.lowercased() == webOrigin.host?.lowercased(),
      url.port == webOrigin.port, parts.count == 2, parts[0] == "invite"
    {
      candidate = parts[1]
    } else {
      return nil
    }
    return validToken(candidate)
  }
}
