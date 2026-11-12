import XCTest

@testable import BrainBattle

final class HomeHistoryTests: XCTestCase {
  @MainActor func testDismissalPersistsLocallyAndKeepsCompletedResults() throws {
    let suite = "brain.dismissal.tests.\(UUID().uuidString)"
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let configuration = AppConfiguration(
      apiURL: URL(string: "https://api.example")!, webURL: URL(string: "https://web.example")!)
    let history = HomeHistory(battles: [
      HomeBattle(
        match(id: "open", opponentID: nil, complete: false, yoursComplete: false, winner: nil)),
      HomeBattle(match(id: "waiting", complete: false, winner: nil)),
      HomeBattle(match(id: "completed")),
    ])
    let app = AppModel(configuration: configuration, dismissalPreferences: preferences)
    app.profile = PlayerProfile(id: "you", name: "You")
    app.homeHistory = history
    app.dismissBattle(id: "open")
    app.dismissBattle(id: "completed")
    XCTAssertEqual(app.visibleOpenBattles.map(\.id), ["waiting"])
    XCTAssertEqual(app.homeHistory.completed.map(\.id), ["completed"])
    XCTAssertEqual(app.homeHistory.rivalry?.wins, 1)
    XCTAssertEqual(app.homeHistory.battles.count, 3)
    XCTAssertEqual(app.dismissedBattleIDs, ["open"])

    let relaunched = AppModel(configuration: configuration, dismissalPreferences: preferences)
    relaunched.profile = app.profile
    relaunched.homeHistory = history
    XCTAssertEqual(relaunched.visibleOpenBattles.map(\.id), ["waiting"])
    // A later claim should not resurrect a dismissed battle in Your Turn.
    relaunched.homeHistory = HomeHistory(battles: [
      HomeBattle(match(id: "open", complete: false, yoursComplete: false, winner: nil))
    ])
    XCTAssertTrue(relaunched.visiblePendingBattles.isEmpty)
    relaunched.restoreBattle(id: "open")
    XCTAssertEqual(relaunched.visiblePendingBattles.map(\.id), ["open"])
    relaunched.homeHistory = history
    XCTAssertEqual(relaunched.visibleOpenBattles.map(\.id), ["open", "waiting"])
  }

  @MainActor func testDismissalIsIsolatedByPlayerAndServer() throws {
    let suite = "brain.dismissal.scope.tests.\(UUID().uuidString)"
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let configuration = AppConfiguration(
      apiURL: URL(string: "https://api.example")!, webURL: URL(string: "https://web.example")!)
    let app = AppModel(configuration: configuration, dismissalPreferences: preferences)
    app.homeHistory = HomeHistory(battles: [
      HomeBattle(
        match(id: "open", opponentID: nil, complete: false, yoursComplete: false, winner: nil))
    ])
    app.profile = PlayerProfile(id: "you", name: "You")
    app.dismissBattle(id: "open")
    app.profile = PlayerProfile(id: "other", name: "Other")
    XCTAssertTrue(app.dismissedBattleIDs.isEmpty)
    app.profile = PlayerProfile(id: "you", name: "Renamed")
    XCTAssertEqual(app.dismissedBattleIDs, ["open"])
    let otherServer = AppModel(
      configuration: AppConfiguration(
        apiURL: URL(string: "https://other.example")!, webURL: configuration.webURL),
      dismissalPreferences: preferences)
    otherServer.profile = app.profile
    XCTAssertTrue(otherServer.dismissedBattleIDs.isEmpty)
  }

  private func match(
    id: String = "match", opponentID: String? = "rival", complete: Bool = true,
    yoursComplete: Bool = true, winner: String? = "you", mode: MatchMode = .challenge,
    expired: Bool = false
  ) -> BattleMatch {
    BattleMatch(
      id: id, mode: mode, gameId: "counting-boxes", rulesVersion: 1,
      you: PlayerProfile(id: "you", name: "You"),
      opponent: opponentID.map { PlayerProfile(id: $0, name: "Same Name") },
      rounds: (1...5).map {
        GameRound(
          number: $0, state: yoursComplete ? .done : .ready,
          displayUntil: nil, deadline: nil, puzzle: nil, attempt: nil, opponent: nil,
          finalized: complete)
      }, inviteUrl: nil, expiresAt: expired ? 500 : 2000,
      complete: complete, yoursComplete: yoursComplete, total: 7500,
      opponentTotal: complete ? 0 : nil, winner: winner, serverNow: 1000)
  }

  func testRivalryUsesOnlyFinalizedServerWinnersAndPlayerIDs() throws {
    let history = HomeHistory(battles: [
      HomeBattle(match(id: "latest", winner: "draw")),
      HomeBattle(match(id: "win")),
      HomeBattle(match(id: "loss", winner: "rival")),
      HomeBattle(match(id: "same-name-different-person", opponentID: "other")),
      HomeBattle(match(id: "unfinished", complete: false, winner: nil)),
      HomeBattle(match(id: "unrecognized-winner", winner: "stranger")),
    ])
    let rivalry = try XCTUnwrap(history.rivalry)
    XCTAssertEqual(rivalry.opponent.id, "rival")
    XCTAssertEqual(rivalry.lastMatchID, "latest")
    XCTAssertEqual(rivalry.wins, 1)
    XCTAssertEqual(rivalry.losses, 1)
    XCTAssertEqual(rivalry.draws, 1)
    XCTAssertEqual(history.completed.count, 4)
  }

  func testPendingExcludesExpiredUnclaimedAndAlreadyPlayedChallenges() {
    let history = HomeHistory(battles: [
      HomeBattle(match(id: "turn", complete: false, yoursComplete: false, winner: nil)),
      HomeBattle(
        match(id: "expired", complete: false, yoursComplete: false, winner: nil, expired: true)),
      HomeBattle(
        match(id: "unclaimed", opponentID: nil, complete: false, yoursComplete: false, winner: nil)),
      HomeBattle(match(id: "waiting", complete: false, winner: nil)),
      HomeBattle(
        match(
          id: "solo", opponentID: nil, complete: false, yoursComplete: false, winner: nil,
          mode: .solo)),
    ])
    XCTAssertEqual(history.pending.map(\.id), ["turn"])
    XCTAssertEqual(history.otherPlayable.map(\.id), ["unclaimed", "solo"])
    XCTAssertEqual(history.waiting.map(\.id), ["waiting"])
  }

  func testEmptyOrSoloHistoryDoesNotInventARivalry() {
    XCTAssertNil(HomeHistory.empty.rivalry)
    let history = HomeHistory(battles: [HomeBattle(match(opponentID: nil, mode: .solo))])
    XCTAssertNil(history.rivalry)
    XCTAssertEqual(history.completed.first?.outcome, .practice)
  }

  func testOutcomeNeverInfersVictoryFromVisibleTotals() {
    // These fixtures all have a high own total. Only the server winner determines the badge.
    XCTAssertNil(HomeBattle(match(complete: false, winner: nil)).outcome)
    XCTAssertNil(HomeBattle(match(winner: nil)).outcome)
    XCTAssertEqual(HomeBattle(match(winner: "rival")).outcome, .defeat)
    XCTAssertEqual(HomeBattle(match(winner: "draw")).outcome, .draw)
  }
}
