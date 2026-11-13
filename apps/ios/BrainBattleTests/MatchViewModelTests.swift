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

private actor SubmissionHarness: BrainAPI {
  enum Outcome: Equatable {
    case accepted, failBeforeCommit, failAfterCommit, rejected, held, timeout
  }
  var outcome = Outcome.accepted
  var now: Double = 2000
  var untimed = true
  var completed = 0
  var feedbackUntil: Double?
  var requests: [(UUID, Int)] = []
  var holdNextRead = false
  var readGate: CheckedContinuation<Void, Never>?
  var submitGate: CheckedContinuation<Void, Never>?
  func set(_ outcome: Outcome) { self.outcome = outcome }
  func configure(
    now: Double = 2000, untimed: Bool = true, completed: Int = 0, feedback: Double? = nil
  ) {
    self.now = now
    self.untimed = untimed
    self.completed = completed
    feedbackUntil = feedback
  }
  func holdRead() { holdNextRead = true }
  func readIsHeld() -> Bool { readGate != nil }
  func submitIsHeld() -> Bool { submitGate != nil }
  func releaseRead() {
    readGate?.resume()
    readGate = nil
  }
  func releaseSubmit() {
    submitGate?.resume()
    submitGate = nil
  }
  func captured() -> [(UUID, Int)] { requests }
  private func fixture() -> BattleMatch {
    let cubes = [
      Cube(x: 0, y: 0, z: 0), Cube(x: 0, y: 1, z: 0), Cube(x: 1, y: 0, z: 0),
      Cube(x: 1, y: 1, z: 0),
    ]
    return BattleMatch(
      id: "h", mode: .solo, gameId: "counting-boxes", rulesVersion: untimed ? 3 : 2,
      you: PlayerProfile(id: "p", name: "Player"), opponent: nil,
      rounds: (1...5).map { number in
        let done = number <= completed
        return GameRound(
          number: number, state: done ? .done : number == completed + 1 ? .answer : .locked,
          displayUntil: number <= completed + 1 ? 1000 : nil,
          deadline: untimed ? nil : 13000,
          puzzle: nil,
          attempt: done
            ? AttemptResult(
              score: outcome == .timeout ? 0 : 1234, correct: outcome != .timeout,
              timedOut: outcome == .timeout) : nil,
          opponent: nil, finalized: done,
          rules: RoundRules(
            difficulty: "easy", displayMs: 3000, answerMs: 6000,
            answerTimeLimit: untimed ? false : nil, feedbackMs: 1000, gridSize: 5),
          feedbackUntil: done ? feedbackUntil : nil,
          reveal: done
            ? AnswerReveal(
              puzzle: CubePuzzle(cubes: cubes, gridSize: 5), correctAnswer: 4,
              submittedAnswer: requests.last?.1) : nil)
      }, inviteUrl: nil, expiresAt: 9_999_999_999_999, complete: completed == 5,
      yoursComplete: completed == 5,
      total: completed * 1234, opponentTotal: nil, winner: nil, serverNow: now)
  }
  func match(id: String) async throws -> BattleMatch {
    let captured = fixture()
    if holdNextRead {
      holdNextRead = false
      await withCheckedContinuation { readGate = $0 }
    }
    return captured
  }
  func submit(matchID: String, number: Int, answer: Int, submissionID: UUID) async throws
    -> BattleMatch
  {
    requests.append((submissionID, answer))
    switch outcome {
    case .failBeforeCommit: throw URLError(.timedOut)
    case .rejected: throw APIError(status: 409, message: "Wait until the puzzle is hidden.")
    case .held: await withCheckedContinuation { submitGate = $0 }
    default: break
    }
    completed = number
    if outcome == .failAfterCommit { throw URLError(.networkConnectionLost) }
    return fixture()
  }
  func session() async throws -> PlayerProfile { PlayerProfile(id: "p", name: "Player") }
  func rename(_ name: String) async throws -> PlayerProfile { try await session() }
  func recentMatches() async throws -> [RecentMatch] { [] }
  func createMatch(mode: MatchMode) async throws -> BattleMatch { fixture() }
  func startRound(matchID: String, number: Int) async throws -> BattleMatch { fixture() }
  func invitation(token: String) async throws -> Invitation { throw URLError(.unsupportedURL) }
  func claim(token: String) async throws -> BattleMatch { fixture() }
  func rematch(id: String) async throws -> BattleMatch { fixture() }
}

extension MatchViewModelTests {
  func testUntimedDoneSubmitsAndShowsAuthorizedReveal() async {
    let api = SubmissionHarness()
    let tested = MatchViewModel(id: "h", api: api)
    await tested.refresh()
    tested.answer = "4"
    XCTAssertNil(tested.currentRound?.deadline)
    await tested.submit()
    XCTAssertEqual(tested.currentRound?.state, .done)
    XCTAssertEqual(tested.currentRound?.reveal?.correctAnswer, 4)
    XCTAssertEqual(tested.currentRound?.attempt?.score, 1234)
    XCTAssertFalse(tested.busy)
    XCTAssertNil(tested.error)
  }
  func testNearDeadlineAndExpiredDoneAreAdjudicatedByServer() async {
    for now in [12999.0, 13001.0] {
      let api = SubmissionHarness()
      await api.configure(now: now, untimed: false)
      if now > 13000 { await api.set(.timeout) }
      let model = MatchViewModel(id: "h", api: api)
      await model.refresh()
      await model.submit()
      let captured = await api.captured()
      XCTAssertEqual(captured.count, 1)
      XCTAssertEqual(model.currentRound?.state, .done)
      XCTAssertEqual(model.currentRound?.attempt?.timedOut, now > 13000)
      XCTAssertFalse(model.busy)
    }
  }
  func testRepeatedDoneWhileRequestIsSlowProducesOneWrite() async {
    let api = SubmissionHarness()
    await api.set(.held)
    let model = MatchViewModel(id: "h", api: api)
    await model.refresh()
    let first = Task { await model.submit() }
    for _ in 0..<1000 {
      if await api.submitIsHeld() { break }
      await Task.yield()
    }
    XCTAssertTrue(model.busy)
    await model.submit()
    let captured = await api.captured()
    XCTAssertEqual(captured.count, 1)
    await api.releaseSubmit()
    await first.value
    XCTAssertFalse(model.busy)
    XCTAssertEqual(model.currentRound?.state, .done)
  }
  func testPollThatStartedBeforeSubmitCannotReplaceAcceptedFeedback() async {
    let api = SubmissionHarness()
    let tested = MatchViewModel(id: "h", api: api)
    await tested.refresh()
    await api.holdRead()
    let poll = Task { await tested.refresh() }
    for _ in 0..<1000 {
      if await api.readIsHeld() { break }
      await Task.yield()
    }
    await tested.submit()
    await api.releaseRead()
    await poll.value
    XCTAssertEqual(tested.currentRound?.state, .done)
    XCTAssertEqual(tested.currentRound?.attempt?.score, 1234)
  }
  func testLostResponseReconcilesCommittedAttemptWithoutResubmitting() async {
    let api = SubmissionHarness()
    await api.set(.failAfterCommit)
    let model = MatchViewModel(id: "h", api: api)
    await model.refresh()
    await model.submit()
    XCTAssertEqual(model.currentRound?.state, .done)
    XCTAssertNil(model.error)
    XCTAssertFalse(model.submissionUncertain)
    let calls = await api.captured()
    XCTAssertEqual(calls.count, 1)
  }
  func testFailedSubmissionSurvivesPollingAndRelaunchWithExactAnswerAndID() async {
    let api = SubmissionHarness()
    await api.set(.failBeforeCommit)
    let scope = "submission.\(UUID().uuidString)"
    defer {
      for suffix in ["1", "selectedRound", "pending.1"] {
        UserDefaults.standard.removeObject(forKey: "countDraft.\(scope).h.\(suffix)")
      }
    }
    let model = MatchViewModel(id: "h", api: api)
    model.restoreDraft(scope: scope)
    await model.refresh()
    model.answer = "4"
    await model.submit()
    XCTAssertNotNil(model.error)
    XCTAssertFalse(model.busy)
    await model.refresh()
    XCTAssertNotNil(model.error)
    model.increment()
    XCTAssertEqual(model.answer, "4")
    let resumed = MatchViewModel(id: "h", api: api)
    resumed.restoreDraft(scope: scope)
    await resumed.refresh()
    XCTAssertEqual(resumed.answer, "4")
    await api.set(.accepted)
    await resumed.submit()
    let calls = await api.captured()
    XCTAssertEqual(calls.count, 2)
    XCTAssertEqual(calls[0].0, calls[1].0)
    XCTAssertEqual(calls[0].1, calls[1].1)
    XCTAssertEqual(resumed.currentRound?.state, .done)
  }
  func testRejectedDoneHasVisiblePersistentErrorAndCanRecover() async {
    let api = SubmissionHarness()
    await api.set(.rejected)
    let model = MatchViewModel(id: "h", api: api)
    await model.refresh()
    await model.submit()
    XCTAssertTrue(model.error?.contains("Wait until") == true)
    XCTAssertFalse(model.busy)
    XCTAssertFalse(model.submissionUncertain)
    await model.refresh()
    XCTAssertNotNil(model.error)
    await api.set(.accepted)
    await model.submit()
    XCTAssertEqual(model.currentRound?.state, .done)
    XCTAssertNil(model.error)
  }
  func testFeedbackGateAndFifthRoundBeforeFinalResults() async {
    let api = SubmissionHarness()
    await api.configure(completed: 4, feedback: 10_000)
    let model = MatchViewModel(id: "h", api: api)
    await model.refresh()
    await model.submit()
    XCTAssertTrue(model.match?.yoursComplete == true)
    XCTAssertEqual(model.currentRound?.number, 5)
    XCTAssertFalse(model.showsFinalResults)
    model.nextRound()
    XCTAssertEqual(model.selectedRound, 5)
    await api.configure(now: 10_001, completed: 5, feedback: 10_000)
    await model.refresh()
    model.nextRound()
    XCTAssertTrue(model.showsFinalResults)
  }
  func testRevealCountsUniqueSupportingCubesAndReducedMotionImmediatelyFinishes() {
    let cubes = (0..<3).flatMap { x in
      (0..<3).flatMap { z in (0..<3).map { y in Cube(x: x, y: y, z: z) } }
    }
    let reveal = AnswerReveal(
      puzzle: CubePuzzle(cubes: cubes, gridSize: 5), correctAnswer: 27, submittedAnswer: 26)
    let plan = CubeRevealPlan(reveal)!
    XCTAssertEqual(plan.puzzle.cubes.count, 27)
    XCTAssertEqual(Set(plan.puzzle.cubes), Set(cubes))
    XCTAssertTrue(plan.puzzle.cubes.prefix(9).allSatisfy { $0.y == 0 })
    XCTAssertLessThanOrEqual(plan.interval * Double(plan.answer), 5.001)
    XCTAssertEqual(plan.initialCount(reduceMotion: true), 27)
    XCTAssertEqual(plan.initialCount(reduceMotion: false), 0)
    XCTAssertNil(
      CubeRevealPlan(
        AnswerReveal(
          puzzle: CubePuzzle(cubes: [cubes[0], cubes[0]]), correctAnswer: 2, submittedAnswer: nil)))
  }
}
