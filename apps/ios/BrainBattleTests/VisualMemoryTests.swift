import XCTest

@testable import BrainBattle

final class VisualMemoryTests: XCTestCase {
  private func player(
    phase: String = "prepare", lives: Int = 3,
    correct: [Int] = [], wrong: [Int] = []
  ) throws -> MemoryPlayer {
    let object: [String: Any] = [
      "playerId": "you", "level": 3, "attempt": 1, "lives": lives,
      "mistakes": wrong.count, "totalMistakes": wrong.count, "score": 2000,
      "gridSize": 4, "targetCount": 5, "phase": phase,
      "startsAt": 1000, "displayUntil": 2500, "correct": correct, "wrong": wrong,
    ]
    return try JSONDecoder().decode(
      MemoryPlayer.self,
      from: JSONSerialization.data(withJSONObject: object))
  }
  func testObservationAndRecallFollowOriginalServerDeadlines() throws {
    let p = try player()
    XCTAssertEqual(p.phase(at: 999), "prepare")
    XCTAssertEqual(p.phase(at: 1000), "display")
    XCTAssertEqual(p.phase(at: 2499), "display")
    XCTAssertEqual(p.phase(at: 2500), "recall")
    XCTAssertFalse(p.canSelect(0, at: 2499))
    XCTAssertTrue(p.canSelect(0, at: 2500))
    let clock = ServerClock(serverMilliseconds: 1000, uptime: 10)
    XCTAssertEqual(p.phase(at: clock.milliseconds(uptime: 11.5)), "recall")
  }
  func testDuplicateSelectionsAndEliminatedPlayersAreDisabled() throws {
    let p = try player(phase: "recall", correct: [0, 2], wrong: [4])
    XCTAssertFalse(p.canSelect(0, at: 5000))
    XCTAssertFalse(p.canSelect(4, at: 5000))
    XCTAssertFalse(p.canSelect(-1, at: 5000))
    XCTAssertFalse(p.canSelect(16, at: 5000))
    XCTAssertTrue(p.canSelect(15, at: 5000))
    XCTAssertFalse(try player(phase: "finished", lives: 0).canSelect(1, at: 5000))
    for phase in ["cleared", "lifeLost", "finished"] {
      XCTAssertFalse(try player(phase: phase).canSelect(1, at: 5000))
    }
  }
  func testLiveProjectionDecodesIndependentLifeCountersAndFinalResults() throws {
    let object: [String: Any] = [
      "startsAt": 1000, "endsAt": 121000,
      "players": [
        [
          "playerId": "a", "level": 4, "attempt": 2, "lives": 2, "mistakes": 1,
          "totalMistakes": 4, "score": 3016, "gridSize": 4, "targetCount": 6,
          "phase": "recall", "startsAt": 4000, "displayUntil": 5500, "correct": [2, 6],
          "wrong": [4],
        ],
        [
          "playerId": "b", "level": 2, "attempt": 3, "lives": 0, "mistakes": 0,
          "totalMistakes": 9, "score": 1001, "gridSize": 3, "targetCount": 4,
          "phase": "finished", "startsAt": 3000, "displayUntil": 4500, "correct": [], "wrong": [],
          "finishReason": "eliminated", "lifeLossReason": "mistakes",
        ],
      ],
    ]
    let game = try JSONDecoder().decode(
      MemoryGame.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(game.players.map(\.lives), [2, 0])
    XCTAssertEqual(game.players.map(\.level), [4, 2])
    XCTAssertNil(game.players[0].highlighted)
    XCTAssertEqual(game.players[1].finishReason, "eliminated")
    XCTAssertEqual(game.players[1].lifeLossReason, "mistakes")
  }
  func testTapCarriesTurnIdentityAndNoClientScore() throws {
    let data = try JSONEncoder().encode(
      MemoryCommand(action: "memory-tap", level: 5, attempt: 2, tile: 6))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(object["tile"] as? Int, 6)
    XCTAssertEqual(object["level"] as? Int, 5)
    XCTAssertEqual(object["attempt"] as? Int, 2)
    XCTAssertNil(object["score"])
    XCTAssertNil(object["lives"])
  }
}
