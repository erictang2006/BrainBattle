import XCTest

/// Explicit Release-only smoke against the hosted beta. No public website is accessed.
@MainActor final class NativeBetaUITests: XCTestCase {
  func testLocalTenRoundOptions() throws {
    #if !DEBUG
      throw XCTSkip("Use Debug with the isolated in-memory API on 4014.")
    #else
      let app = XCUIApplication()
      app.launchArguments = [
        "-debug.apiOrigin", "http://127.0.0.1:4014",
        "-debug.webOrigin", "http://127.0.0.1:4014",
      ]
      app.launch()
      if app.textFields["onboardingName"].waitForExistence(timeout: 10) {
        app.textFields["onboardingName"].tap()
        app.textFields["onboardingName"].typeText("Ten Round Tester")
        app.buttons["onboardingContinue"].tap()
      }
      try home(app)
      app.segmentedControls["matchRoundCount"].buttons["10 rounds"].tap()
      app.buttons["tab.games"].tap()
      app.buttons["soloPractice"].tap()
      try require(app.buttons["startRound"].waitForExistence(timeout: 15))
      XCTAssertTrue(app.staticTexts["10"].exists)
      app.navigationBars.buttons.firstMatch.tap()
      try home(app)
      reveal(app.buttons["playLive"], app: app)
      app.buttons["playLive"].tap()
      try require(app.buttons["createLiveRoom"].waitForExistence(timeout: 10))
      app.segmentedControls["liveRoundCount"].buttons["10 rounds"].tap()
      app.segmentedControls.buttons["Party Mode"].tap()
      app.buttons["createLiveRoom"].tap()
      try require(app.buttons["liveReady"].waitForExistence(timeout: 15))
      XCTAssertTrue(app.staticTexts["Round 10"].exists)
    #endif
  }
  /// Uses an isolated, in-memory local API on port 4012; never the hosted beta.
  func testLocalDoneRevealAndFiveRoundResults() async throws {
    #if !DEBUG
      throw XCTSkip("Run this local regression with configuration Debug.")
    #else
      let app = XCUIApplication()
      app.launchArguments = [
        "-debug.apiOrigin", "http://127.0.0.1:4012",
        "-debug.webOrigin", "http://127.0.0.1:4012",
      ]
      app.launch()
      if app.textFields["onboardingName"].waitForExistence(timeout: 3) {
        app.textFields["onboardingName"].tap()
        app.textFields["onboardingName"].typeText("Reveal Tester")
        app.buttons["onboardingContinue"].tap()
      }
      try home(app)
      app.buttons["tab.games"].tap()
      try require(app.buttons["soloPractice"].waitForExistence(timeout: 10))
      app.buttons["soloPractice"].tap()
      for number in 1...5 {
        let start = app.buttons["startRound"]
        try require(start.waitForExistence(timeout: 15))
        reveal(start, app: app)
        start.tap()
        let done = app.buttons["submitAnswer"]
        try require(done.waitForExistence(timeout: 10))
        // Input remains locked until the server's viewing window ends.
        for _ in 0..<80 {
          if done.isEnabled { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        try require(done.isEnabled)
        app.buttons["incrementCount"].tap()
        app.buttons["Type Answer"].tap()
        app.buttons["digit.4"].tap()
        app.buttons["Quick Count"].tap()
        XCTAssertEqual(app.staticTexts["answerCount"].label, "Cube count: 14")
        done.tap()
        let skip = app.buttons["skipReveal"]
        if number == 1 {
          // Let the first reveal play through to exercise the full animation.
          try require(app.staticTexts["correctAnswer"].waitForExistence(timeout: 10))
          app.terminate()
          app.launch()
          try require(app.buttons["nextRound"].waitForExistence(timeout: 15))
        } else {
          // A three-cube reveal may finish before XCTest's idle wait returns.
          if skip.exists { reveal(skip, app: app) }
          if skip.exists { skip.tap() }
          try require(app.staticTexts["correctAnswer"].waitForExistence(timeout: 10))
        }
        let next = app.buttons["nextRound"]
        try require(next.waitForExistence(timeout: 10))
        reveal(next, app: app)
        for _ in 0..<20 {
          if next.isEnabled { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        try require(next.isEnabled)
        next.tap()
      }
      try require(app.staticTexts["resultTitle"].waitForExistence(timeout: 15))
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "Five-round submission and reveal results"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    #endif
  }
  func testHostedReleaseGuestRedeemsAsyncCodeAndSharesNativeCodes() async throws {
    #if DEBUG
      throw XCTSkip("Run this hosted beta UI check with configuration Release.")
    #else
      let api = URL(string: "https://brain-battle-api.onrender.com/api/")!
      let config = URLSessionConfiguration.ephemeral
      config.httpCookieStorage = nil
      let session = URLSession(configuration: config)
      var request = URLRequest(url: api.appendingPathComponent("native/session"))
      request.httpMethod = "POST"
      let (_, response) = try await session.data(for: request)
      let token = try XCTUnwrap(
        (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Brain-Session"))
      request = URLRequest(url: api.appendingPathComponent("matches"))
      request.httpMethod = "POST"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = Data(#"{"mode":"challenge"}"#.utf8)
      let (data, createdResponse) = try await session.data(for: request)
      XCTAssertEqual((createdResponse as? HTTPURLResponse)?.statusCode, 200)
      let created = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      let matchID = try XCTUnwrap(created["id"] as? String)
      let legacyURL = try XCTUnwrap(created["inviteUrl"] as? String)
      let code = try XCTUnwrap(URL(string: legacyURL)?.lastPathComponent)
      XCTAssertEqual(code.count, 48)
      // The host finishes first; async players retain independent clocks.
      for number in 1...5 {
        request = URLRequest(
          url: api.appendingPathComponent("matches/\(matchID)/rounds/\(number)/start"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (roundData, _) = try await session.data(for: request)
        let view = try XCTUnwrap(JSONSerialization.jsonObject(with: roundData) as? [String: Any])
        let rounds = try XCTUnwrap(view["rounds"] as? [[String: Any]])
        let round = rounds[number - 1]
        let puzzle = try XCTUnwrap(round["puzzle"] as? [String: Any])
        let cubes = try XCTUnwrap(puzzle["cubes"] as? [[String: Any]])
        let displayUntil = try XCTUnwrap(round["displayUntil"] as? Double)
        let serverNow = try XCTUnwrap(view["serverNow"] as? Double)
        try await Task.sleep(for: .milliseconds(max(0, displayUntil - serverNow + 200)))
        request = URLRequest(
          url: api.appendingPathComponent("matches/\(matchID)/rounds/\(number)/attempt"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
          "answer": cubes.count, "submissionId": UUID().uuidString,
        ])
        let (_, submitted) = try await session.data(for: request)
        XCTAssertEqual((submitted as? HTTPURLResponse)?.statusCode, 200)
      }
      let app = XCUIApplication()
      app.launch()
      if app.textFields["onboardingName"].waitForExistence(timeout: 3) {
        app.textFields["onboardingName"].tap()
        app.textFields["onboardingName"].typeText("Beta Friend")
        app.buttons["onboardingContinue"].tap()
      }
      try home(app)
      reveal(app.buttons["openInvitation"], app: app)
      app.buttons["openInvitation"].tap()
      let field =
        app.textFields["invitationLink"].exists
        ? app.textFields["invitationLink"] : app.textViews["invitationLink"]
      try require(field.waitForExistence(timeout: 10))
      field.tap()
      field.typeText(code)
      app.buttons["previewInvitation"].tap()
      let accept = app.buttons["acceptInvitation"]
      try require(accept.waitForExistence(timeout: 20))
      reveal(accept, app: app)
      accept.tap()
      try await playFiveRounds(app)
      let title = app.staticTexts["resultTitle"]
      try require(title.waitForExistence(timeout: 20))
      XCTAssertNotEqual(title.label, "Your score is set.")
      try home(app)
      reveal(app.buttons["createChallenge"], app: app)
      app.buttons["createChallenge"].tap()
      let share = app.buttons["shareChallenge"]
      try require(share.waitForExistence(timeout: 20))
      reveal(share, app: app)
      XCTAssertTrue(app.staticTexts["challengeCode"].exists)
      share.tap()
      let copy = app.cells.matching(NSPredicate(format: "label == 'Copy'")).firstMatch
      try require(copy.waitForExistence(timeout: 10))
      copy.tap()
      try home(app)
      reveal(app.buttons["playLive"], app: app)
      app.buttons["playLive"].tap()
      let createLive = app.buttons["createLiveRoom"]
      try require(createLive.waitForExistence(timeout: 15))
      createLive.tap()
      try require(app.buttons["liveReady"].waitForExistence(timeout: 20))
      let roomCode = app.staticTexts["liveRoomCode"]
      XCTAssertEqual(roomCode.label.count, 6)
      app.buttons["Share room code"].tap()
      try require(copy.waitForExistence(timeout: 10))
      copy.tap()
      let originalCode = roomCode.label
      XCUIDevice.shared.press(.home)
      try await Task.sleep(for: .seconds(2))
      app.activate()
      try require(app.buttons["liveReady"].waitForExistence(timeout: 20))
      XCTAssertEqual(app.staticTexts["liveRoomCode"].label, originalCode)
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "Hosted Release native-only room lobby"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    #endif
  }
  func testHostedReleaseSoloFiveRoundsAndRelaunch() async throws {
    #if DEBUG
      throw XCTSkip("Run this hosted beta UI check with configuration Release.")
    #else
      let app = XCUIApplication()
      app.launch()
      if app.textFields["onboardingName"].waitForExistence(timeout: 3) {
        app.textFields["onboardingName"].tap()
        app.textFields["onboardingName"].typeText("Beta Friend")
        app.buttons["onboardingContinue"].tap()
      }
      try home(app)
      app.buttons["tab.games"].tap()
      try require(app.buttons["soloPractice"].waitForExistence(timeout: 10))
      app.buttons["soloPractice"].tap()
      try await playFiveRounds(app)
      let title = app.staticTexts["resultTitle"]
      try require(title.waitForExistence(timeout: 20))
      let saved = title.label
      app.terminate()
      app.launch()
      try require(title.waitForExistence(timeout: 20))
      XCTAssertEqual(title.label, saved)
      XCTAssertFalse(app.textFields["onboardingName"].exists)
    #endif
  }
  private func playFiveRounds(_ app: XCUIApplication) async throws {
    for number in 1...5 {
      let start = app.buttons["startRound"]
      try require(start.waitForExistence(timeout: 20))
      reveal(start, app: app)
      start.tap()
      try require(app.buttons["incrementCount"].waitForExistence(timeout: 15))
      let done = app.buttons["submitAnswer"]
      for _ in 0..<80 {
        if done.isEnabled { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      try require(done.isEnabled)
      done.tap()
      if number < 5 {
        let next = app.buttons["nextRound"]
        try require(next.waitForExistence(timeout: 20))
        reveal(next, app: app)
        for _ in 0..<20 {
          if next.isEnabled { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        try require(next.isEnabled)
        next.tap()
      }
    }
  }
  private func home(_ app: XCUIApplication) throws {
    for _ in 0..<5 {
      if app.buttons["tab.home"].exists { app.buttons["tab.home"].tap() }
      if app.buttons["createChallenge"].waitForExistence(timeout: 3) { return }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    try require(app.buttons["createChallenge"].waitForExistence(timeout: 20))
  }
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<6 {
      if element.isHittable { return }
      app.swipeUp()
    }
  }
  private func require(_ condition: Bool) throws {
    guard condition else { throw NSError(domain: "Native beta UI check timed out", code: 1) }
  }
}
