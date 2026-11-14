import Foundation

struct LivePlayer: Decodable, Identifiable, Sendable {
  let id: String
  let name: String
  let ready: Bool
  let connected: Bool
  let forfeited: Bool
}
struct LiveResult: Decodable, Identifiable, Sendable {
  var id: String { playerId }
  let playerId: String
  let score: Int
  let correct: Bool
  let timedOut: Bool
  let forfeited: Bool
  let placement: Int?
  let points: Int?
  var submittedAnswer: Int? = nil
}
struct LiveAnswerReveal: Decodable, Sendable {
  let puzzle: CubePuzzle
  let correctAnswer: Int
}
struct LiveRound: Decodable, Sendable {
  let number: Int
  let startsAt: Double
  let displayUntil: Double
  let deadline: Double?
  let rules: RoundRules
  let puzzle: CubePuzzle?
  let submitted: [String]
  let results: [LiveResult]?
  let winners: [String]?
  var reveal: LiveAnswerReveal? = nil
  func phase(at now: Double) -> String {
    if results != nil { return "result" }
    if now < startsAt { return "prepare" }
    if now < displayUntil { return "display" }
    if let deadline, now >= deadline { return "waiting" }
    return "answer"
  }
}
struct LiveStanding: Decodable, Identifiable, Sendable {
  var id: String { playerId }
  let playerId: String
  let points: Int
  let roundWins: Int
  let totalScore: Int
  let rank: Int
}
struct LiveLineup: Decodable, Identifiable, Sendable {
  var id: Int { number }
  let number: Int
  let gameId: String
  let rules: RoundRules
}
struct LiveSnapshot: Decodable, Sendable {
  var format: String? = nil
  var memory: MemoryGame? = nil
  var isVisualMemory: Bool { format == "visual-memory" }
  let id: String
  let code: String
  let revision: Int
  let rulesVersion: Int
  let status: String
  let hostId: String
  let mode: String
  let capacity: Int
  let lineup: [LiveLineup]
  let roundCount: Int
  let expiresAt: Double
  let serverNow: Double
  let players: [LivePlayer]
  let standings: [LiveStanding]
  let nextAt: Double?
  let rematchCode: String?
  let round: LiveRound?
}
struct LiveAck: Decodable, Sendable {
  let ok: Bool
  let state: LiveSnapshot?
  let serverNow: Double?
  let error: String?
  let status: Int?
}
enum LiveRoomCode {
  static func shareText(_ code: String) -> String {
    "Brain Battle live room\nRoom code: \(code)\nOpen Brain Battle → Play Live → Join Room. Enter this code, mark Ready, and wait for the host to start."
  }
  static func parse(_ input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let value: String
    if trimmed.hasPrefix("Brain Battle live room\n") {
      let codes = trimmed.split(separator: "\n").filter { $0.hasPrefix("Room code: ") }
      guard codes.count == 1 else { return nil }
      value = String(codes[0].dropFirst("Room code: ".count)).uppercased()
    } else if let url = URL(string: trimmed), url.scheme == "brainbattle", url.host == "room",
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.path.split(separator: "/").count == 1
    {
      value = String(url.path.dropFirst()).uppercased()
    } else {
      value = trimmed.uppercased()
    }
    return value.count == 6 && value.allSatisfy { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }
      ? value : nil
  }
}
