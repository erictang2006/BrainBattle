import Foundation

struct MemoryPlayer: Decodable, Identifiable, Sendable {
  var id: String { playerId }
  let playerId: String
  let level: Int
  let attempt: Int
  let lives: Int
  let mistakes: Int
  let totalMistakes: Int
  let score: Int
  let gridSize: Int
  let targetCount: Int
  let phase: String
  let startsAt: Double
  let displayUntil: Double
  let nextAt: Double?
  let correct: [Int]
  let wrong: [Int]
  let highlighted: [Int]?
  let finishReason: String?
  let lifeLossReason: String?
  var turnID: String { "\(level).\(attempt)" }
  func phase(at now: Double) -> String {
    guard phase == "prepare" || phase == "display" else { return phase }
    if now < startsAt { return "prepare" }
    return now < displayUntil ? "display" : "recall"
  }
  func canSelect(_ tile: Int, at now: Double) -> Bool {
    phase(at: now) == "recall" && lives > 0 && tile >= 0 && tile < gridSize * gridSize
      && !correct.contains(tile) && !wrong.contains(tile)
  }
}
struct MemoryGame: Decodable, Sendable {
  let startsAt: Double
  let endsAt: Double?
  let players: [MemoryPlayer]
}
struct MemoryHistory: Decodable, Sendable {
  let bestLevel: Int
  let games: [MemoryHistoryEntry]
}
struct MemoryHistoryEntry: Decodable, Identifiable, Sendable {
  var id: String { code }
  let code: String
  let mode: String
  let updatedAt: Double
  let completed: Bool
  let level: Int
  let score: Int
  let lives: Int
  let rank: Int
}
struct MemoryCommand: Encodable, Sendable {
  let action: String
  let level: Int
  let attempt: Int
  var tile: Int? = nil
}
