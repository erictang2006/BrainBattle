import XCTest

@testable import BrainBattle

private actor MatchAPIStub: BrainAPI {
  var keys: [UUID] = []
  var finalized = false
  func finalize() { finalized = true }
  private func fixture(done: Bool = false) -> BattleMatch {
    BattleMatch(
      id: "m", mode: .solo, gameId: "counting-boxes", rulesVersion: 1,
      you: PlayerProfile(id: "a", name: "A"), opponent: nil,
      rounds: [
        GameRound(
          number: 1, state: done ? .done : .answer, displayUntil: 1000, deadline: 13000,
          puzzle: nil,
          attempt: done ? AttemptResult(score: 987, correct: false, timedOut: false) : nil,
          opponent: nil, finalized: done),
        GameRound(
          number: 2, state: done ? .ready : .locked, displayUntil: nil, deadline: nil,
          puzzle: nil, attempt: nil, opponent: nil, finalized: false),
      ],
      inviteUrl: nil, expiresAt: 20000, complete: false, yoursComplete: false,
      total: done ? 987 : 0,
      opponentTotal: nil, winner: nil, serverNow: 2000)
  }
  func match(id: String) async throws -> BattleMatch { fixture(done: finalized) }
  func submit(matchID: String, number: Int, answer: Int, submissionID: UUID) async throws
    -> BattleMatch
  {
    keys.append(submissionID)
    if keys.count == 1 { throw URLError(.timedOut) }
    return fixture(done: true)
  }
  func session() async throws -> PlayerProfile { throw URLError(.unsupportedURL) }
  func rename(_ name: String) async throws -> PlayerProfile { throw URLError(.unsupportedURL) }
  func recentMatches() async throws -> [RecentMatch] { [] }
  func createMatch(mode: MatchMode) async throws -> BattleMatch { fixture() }
  func startRound(matchID: String, number: Int) async throws -> BattleMatch { fixture() }
  func invitation(token: String) async throws -> Invitation { throw URLError(.unsupportedURL) }
  func claim(token: String) async throws -> BattleMatch { fixture() }
  func rematch(id: String) async throws -> BattleMatch { fixture() }
}

@MainActor final class MatchViewModelTests: XCTestCase {
  func testPollingKeepsFinalizedRoundVisibleUntilExplicitNextRound() async {
    let api = MatchAPIStub()
    let model = MatchViewModel(id: "m", api: api)
    await model.refresh()
    await api.finalize()
    await model.refresh()
    XCTAssertEqual(model.currentRound?.number, 1)
    XCTAssertEqual(model.currentRound?.state, .done)
    model.nextRound()
    XCTAssertEqual(model.currentRound?.number, 2)
    XCTAssertEqual(model.currentRound?.state, .ready)
  }
  func testRapidCountingAndTypingShareOneBoundedAnswerAndRestoreOnRelaunch() async {
    let api = MatchAPIStub()
    let scope = "test.\(UUID().uuidString)"
    defer { UserDefaults.standard.removeObject(forKey: "countDraft.\(scope).m.1") }
    let model = MatchViewModel(id: "m", api: api)
    model.restoreDraft(scope: scope)
    await model.refresh()
    XCTAssertEqual(model.answer, "0")
    for _ in 0..<120 { model.increment() }
    XCTAssertEqual(model.answer, "100")
    model.decrement()
    XCTAssertEqual(model.answer, "99")
    model.clearAnswer()
    model.decrement()
    XCTAssertEqual(model.answer, "0")
    model.digit("1")
    model.digit("2")
    model.increment()
    XCTAssertEqual(model.answer, "13")
    model.deleteDigit()
    XCTAssertEqual(model.answer, "1")
    let resumed = MatchViewModel(id: "m", api: api)
    resumed.restoreDraft(scope: scope)
    await resumed.refresh()
    XCTAssertEqual(resumed.answer, "1")
  }
  func testUncertainSubmissionReusesIdAndDisplaysOnlyServerScore() async {
    let api = MatchAPIStub()
    let tested = MatchViewModel(id: "m", api: api)
    await tested.refresh()
    tested.answer = "13"
    await tested.submit()
    XCTAssertNotNil(tested.error)
    XCTAssertFalse(tested.busy)
    await tested.submit()
    let keys = await api.keys
    XCTAssertEqual(keys.count, 2)
    XCTAssertEqual(keys[0], keys[1])
    XCTAssertEqual(tested.match?.total, 987)
    XCTAssertEqual(tested.currentRound?.attempt?.score, 987)
    XCTAssertNil(tested.error)
  }
}
