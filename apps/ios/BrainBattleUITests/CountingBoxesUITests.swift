import UIKit
import XCTest

/// Requires the real local Fastify server. No clock overrides or puzzle-answer backdoors.
@MainActor final class CountingBoxesUITests: XCTestCase {
  func testQuickCountSwitchingAndDraftSurvivesDisplayAndRelaunch() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.textFields["onboardingName"].waitForExistence(timeout: 2) {
      app.textFields["onboardingName"].tap()
      app.textFields["onboardingName"].typeText("Quick Counter")
      app.buttons["onboardingContinue"].tap()
    }
    for _ in 0..<3 {
      if app.buttons["createChallenge"].waitForExistence(timeout: 2) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    let create = app.buttons["createChallenge"]
    reveal(create, in: app)
    create.tap()
    let start = app.buttons["startRound"]
    XCTAssertTrue(start.waitForExistence(timeout: 15))
    reveal(start, in: app)
    start.tap()
    let plus = app.buttons["incrementCount"]
    XCTAssertTrue(plus.waitForExistence(timeout: 5))
    XCTAssertLessThanOrEqual(
      plus.frame.maxY, app.buttons["submitAnswer"].frame.minY,
      "The whole +1 button must be above the pinned Done action.")
    let cubes = app.descendants(matching: .any).matching(identifier: "cubeScene").firstMatch
    XCTAssertTrue(cubes.exists)
    XCTAssertEqual(app.staticTexts["answerCount"].label, "Cube count: 0")
    for _ in 0..<3 { plus.tap() }
    XCTAssertEqual(app.staticTexts["answerCount"].label, "Cube count: 3")
    attach(app, name: "V2 sparse grid and quick counting")
    app.buttons["Type Answer"].tap()
    let count = app.staticTexts["answerCount"]
    XCTAssertEqual(count.label, "Cube count: 3")
    let typedDigit = app.buttons["digit.1"]
    reveal(typedDigit, in: app)
    typedDigit.tap()
    XCTAssertEqual(count.label, "Cube count: 31")
    app.buttons["Quick Count"].tap()
    app.buttons["incrementCount"].tap()
    XCTAssertEqual(count.label, "Cube count: 32")
    let done = app.buttons["submitAnswer"]
    waitEnabled(done)
    done.tap()
    XCTAssertTrue(app.staticTexts["A tricky little stack."].waitForExistence(timeout: 10))
    let next = app.buttons["nextRound"]
    waitEnabled(next)
    reveal(next, in: app)
    next.tap()
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    reveal(start, in: app)
    start.tap()
    app.buttons["incrementCount"].tap()
    app.terminate()
    app.launch()
    XCTAssertTrue(count.waitForExistence(timeout: 8))
    XCTAssertEqual(count.label, "Cube count: 1")

  }

  func testDismissOpenBattleUndoAndRelaunch() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.textFields["onboardingName"].waitForExistence(timeout: 2) {
      app.textFields["onboardingName"].tap()
      app.textFields["onboardingName"].typeText("Native Ace")
      app.buttons["onboardingContinue"].tap()
    }
    for _ in 0..<3 {
      if app.buttons["createChallenge"].waitForExistence(timeout: 2) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    let featured = app.descendants(matching: .any).matching(identifier: "featuredRivalry")
      .firstMatch
    XCTAssertTrue(featured.waitForExistence(timeout: 15))
    let prefix = NSPredicate(format: "identifier BEGINSWITH %@", "dismissBattle.")
    let previous = app.buttons.matching(prefix).allElementsBoundByIndex.map(\.identifier)
    let create = app.buttons["createChallenge"]
    reveal(create, in: app)
    create.tap()
    XCTAssertTrue(app.buttons["startRound"].waitForExistence(timeout: 15))
    app.navigationBars.buttons.firstMatch.tap()
    // Only dismiss the fresh challenge created by this test, never an existing battle.
    let fresh = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND NOT (identifier IN %@)",
        "dismissBattle.", previous as NSArray)
    ).firstMatch
    XCTAssertTrue(fresh.waitForExistence(timeout: 15))
    let identifier = fresh.identifier
    reveal(fresh, in: app)
    attach(app, name: "Open battle dismiss action")
    fresh.tap()
    XCTAssertFalse(app.buttons[identifier].exists)
    let undo = app.buttons["undoDismissBattle"]
    XCTAssertTrue(undo.waitForExistence(timeout: 3))
    reveal(undo, in: app)
    undo.tap()
    XCTAssertTrue(app.buttons[identifier].exists)
    reveal(app.buttons[identifier], in: app)
    app.buttons[identifier].tap()
    app.terminate()
    app.launch()
    XCTAssertTrue(featured.waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons[identifier].exists)
  }

  func testCorrectAnswerFeedbackFromSharedPublicPuzzle() async throws {
    continueAfterFailure = false
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    let session = URLSession(configuration: config)
    let (_, response) = try await send(session, "native/session", method: "POST")
    let credential = try XCTUnwrap(
      (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Brain-Session"))
    let (created, _) = try await send(
      session, "matches", method: "POST", credential: credential, body: ["mode": "challenge"])
    let match = try XCTUnwrap(JSONSerialization.jsonObject(with: created) as? [String: Any])
    let id = try XCTUnwrap(match["id"] as? String)
    let link = try XCTUnwrap(match["inviteUrl"] as? String)
    let (started, _) = try await send(
      session, "matches/\(id)/rounds/1/start", method: "POST", credential: credential)
    // Count only public render coordinates during the fixture host's display window.
    // The guest receives the same puzzle; no private seed or answer endpoint is used.
    let projection = try XCTUnwrap(JSONSerialization.jsonObject(with: started) as? [String: Any])
    let rounds = try XCTUnwrap(projection["rounds"] as? [[String: Any]])
    let puzzle = try XCTUnwrap(rounds.first?["puzzle"] as? [String: Any])
    let cubes = try XCTUnwrap(puzzle["cubes"] as? [[String: Any]])
    let app = XCUIApplication()
    app.launch()
    for _ in 0..<3 {
      if app.buttons["openInvitation"].waitForExistence(timeout: 2) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    let open = app.buttons["openInvitation"]
    reveal(open, in: app)
    open.tap()
    let field = app.textFields["invitationLink"]
    field.tap()
    field.typeText(link)
    app.buttons["previewInvitation"].tap()
    let accept = app.buttons["acceptInvitation"]
    XCTAssertTrue(accept.waitForExistence(timeout: 15))
    reveal(accept, in: app)
    accept.tap()
    let start = app.buttons["startRound"]
    XCTAssertTrue(start.waitForExistence(timeout: 15))
    reveal(start, in: app)
    start.tap()
    selectTypeAnswer(in: app)
    XCTAssertTrue(app.buttons["digit.0"].waitForExistence(timeout: 15))
    for digit in String(cubes.count) {
      let key = app.buttons["digit.\(digit)"]
      reveal(key, in: app)
      key.tap()
    }
    attach(app, name: "Native focused answer entry")
    waitEnabled(app.buttons["submitAnswer"])
    app.buttons["submitAnswer"].tap()
    XCTAssertTrue(app.staticTexts["Spot on!"].waitForExistence(timeout: 12))
    attach(app, name: "Native correct answer feedback")
    let next = app.buttons["nextRound"]
    reveal(next, in: app)
    waitEnabled(next)
    next.tap()
    XCTAssertTrue(app.buttons["startRound"].waitForExistence(timeout: 10))
  }

  func testSocialHomeTabsAndLargeText() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.textFields["onboardingName"].waitForExistence(timeout: 2) {
      app.textFields["onboardingName"].tap()
      app.textFields["onboardingName"].typeText("Native Ace")
      app.buttons["onboardingContinue"].tap()
    }
    for _ in 0..<3 {
      if app.buttons["tab.home"].waitForExistence(timeout: 2) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    XCTAssertTrue(app.staticTexts["Your next rival awaits."].waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 2)
    attach(app, name: "Social Rivalry home")
    let live = app.buttons["playLive"]
    reveal(live, in: app)
    live.tap()
    XCTAssertTrue(app.alerts["A little more time for live"].waitForExistence(timeout: 3))
    app.alerts.buttons["Got it"].tap()
    app.buttons["tab.games"].tap()
    XCTAssertTrue(app.buttons["soloPractice"].waitForExistence(timeout: 3))
    app.buttons["tab.friends"].tap()
    XCTAssertTrue(app.staticTexts["Good friends. Great rivals."].waitForExistence(timeout: 3))
    let invite = app.buttons["openInvitation"]
    reveal(invite, in: app)
    invite.tap()
    XCTAssertTrue(app.buttons["previewInvitation"].waitForExistence(timeout: 3))
    app.buttons["Cancel"].tap()
    app.buttons["tab.profile"].tap()
    XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 3))
    app.buttons["editProfile"].tap()
    XCTAssertTrue(app.navigationBars["Your player"].waitForExistence(timeout: 3))
    app.buttons["Done"].tap()
    app.buttons["tab.home"].tap()
    app.terminate()
    app.launchArguments = [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["tab.profile"].isHittable)
    XCTAssertLessThan(app.buttons["tab.profile"].frame.height, 120)
    let challenge = app.buttons["createChallenge"]
    reveal(challenge, in: app)
    XCTAssertTrue(challenge.isHittable)
    XCTAssertLessThanOrEqual(challenge.frame.maxX, app.frame.maxX)
    XCTAssertGreaterThanOrEqual(challenge.frame.minX, app.frame.minX)
    attach(app, name: "Social Rivalry accessibility text")
  }

  func testRenderedPuzzleFrame() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    if app.textFields["onboardingName"].waitForExistence(timeout: 2) {
      app.textFields["onboardingName"].tap()
      app.textFields["onboardingName"].typeText("Cube Counter")
      app.buttons["onboardingContinue"].tap()
    }
    // Create a fresh test challenge instead of consuming a player's existing round.
    for _ in 0..<3 {
      if app.buttons["createChallenge"].waitForExistence(timeout: 2) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    let create = app.buttons["createChallenge"]
    XCTAssertTrue(create.waitForExistence(timeout: 15))
    reveal(create, in: app)
    create.tap()
    let start = app.buttons["startRound"]
    XCTAssertTrue(start.waitForExistence(timeout: 15))
    reveal(start, in: app)
    start.tap()
    Thread.sleep(forTimeInterval: 0.35)
    attach(app, name: "Native rendered puzzle frame")
    assertRenderedCubes(in: app)
    XCTAssertFalse(app.buttons["Reset view"].exists)
    let hidden = app.descendants(matching: .any).matching(identifier: "cubeScene").firstMatch
    wait(
      for: [
        XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hidden)
      ], timeout: 6)
    XCTAssertFalse(hidden.exists)
    let submit = app.buttons["submitAnswer"]
    XCTAssertTrue(submit.isHittable, "The answer action stays reachable above the safe area.")
    reveal(submit, in: app)
    waitEnabled(submit)
    submit.tap()
    let next = app.buttons["nextRound"]
    XCTAssertTrue(next.waitForExistence(timeout: 12))
    reveal(next, in: app)
    waitEnabled(next)
    next.tap()
    app.terminate()
    app.launch()
    XCTAssertTrue(start.waitForExistence(timeout: 15))
    reveal(start, in: app)
    start.tap()
    Thread.sleep(forTimeInterval: 0.35)
    assertRenderedCubes(in: app)
    attach(app, name: "Native second round after relaunch")
  }
  func testAcceptChallengeAndReceiveFinalResults() async throws {
    continueAfterFailure = false
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    let session = URLSession(configuration: config)
    let (profileData, response) = try await send(session, "native/session", method: "POST")
    _ = profileData
    let credential = try XCTUnwrap(
      (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Brain-Session"))
    let (created, _) = try await send(
      session, "matches", method: "POST", credential: credential, body: ["mode": "challenge"])
    let match = try XCTUnwrap(JSONSerialization.jsonObject(with: created) as? [String: Any])
    let id = try XCTUnwrap(match["id"] as? String)
    let invitation = try XCTUnwrap(match["inviteUrl"] as? String)
    // The fixture host plays through the public API. No seed or answer is read.
    for number in 1...5 {
      let (data, _) = try await send(
        session, "matches/\(id)/rounds/\(number)/start", method: "POST", credential: credential)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      let roundList = try XCTUnwrap(state["rounds"] as? [[String: Any]])
      let rules = try XCTUnwrap(roundList[number - 1]["rules"] as? [String: Any])
      let display = try XCTUnwrap(rules["displayMs"] as? Double)
      try await Task.sleep(for: .milliseconds(display + 120))
      let (_, _) = try await send(
        session, "matches/\(id)/rounds/\(number)/attempt", method: "POST", credential: credential,
        body: ["answer": 0, "submissionId": UUID().uuidString])
      if number < 5 { try await Task.sleep(for: .milliseconds(1050)) }
    }
    let app = XCUIApplication()
    app.launch()
    if app.textFields["onboardingName"].waitForExistence(timeout: 3) {
      app.textFields["onboardingName"].tap()
      app.textFields["onboardingName"].typeText("Native Ace")
      app.buttons["onboardingContinue"].tap()
    }
    for _ in 0..<3 {
      if app.buttons["openInvitation"].waitForExistence(timeout: 3) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    let open = app.buttons["openInvitation"]
    reveal(open, in: app)
    open.tap()
    let field = app.textViews["invitationLink"]
    if field.exists {
      field.tap()
      field.typeText(invitation)
    } else {
      let field = app.textFields["invitationLink"]
      field.tap()
      field.typeText(invitation)
    }
    app.buttons["previewInvitation"].tap()
    XCTAssertTrue(app.buttons["acceptInvitation"].waitForExistence(timeout: 15))
    reveal(app.buttons["acceptInvitation"], in: app)
    app.buttons["acceptInvitation"].tap()
    for number in 1...5 {
      let start = app.buttons["startRound"]
      XCTAssertTrue(start.waitForExistence(timeout: 15))
      reveal(start, in: app)
      start.tap()
      selectTypeAnswer(in: app)
      let digit = app.buttons["digit.0"]
      XCTAssertTrue(digit.waitForExistence(timeout: 15))
      reveal(digit, in: app)
      digit.tap()
      let submit = app.buttons["submitAnswer"]
      reveal(submit, in: app)
      waitEnabled(submit)
      submit.tap()
      if number < 5 {
        let next = app.buttons["nextRound"]
        XCTAssertTrue(next.waitForExistence(timeout: 12))
        reveal(next, in: app)
        waitEnabled(next)
        next.tap()
      }
    }
    let title = app.staticTexts["resultTitle"]
    XCTAssertTrue(title.waitForExistence(timeout: 15))
    XCTAssertEqual(title.label, "Great minds. It’s a draw!")
    attach(app, name: "Native final comparison")
    let (final, _) = try await send(session, "matches/\(id)", credential: credential)
    let hostResult = try XCTUnwrap(JSONSerialization.jsonObject(with: final) as? [String: Any])
    XCTAssertEqual(hostResult["complete"] as? Bool, true)
    XCTAssertEqual(hostResult["winner"] as? String, "draw")
    // The real completed match must appear on Home with its server-provided draw.
    app.navigationBars.buttons.firstMatch.tap()
    let recent = app.buttons["recentBattle.\(id)"]
    XCTAssertTrue(recent.waitForExistence(timeout: 15))
    reveal(recent, in: app)
    recent.tap()
    XCTAssertTrue(app.staticTexts["resultTitle"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.staticTexts["resultTitle"].label, "Great minds. It’s a draw!")
    app.navigationBars.buttons.firstMatch.tap()
    let rivalry = app.buttons["rivalryRematch"]
    XCTAssertTrue(rivalry.waitForExistence(timeout: 15))
    for _ in 0..<8 where !rivalry.isHittable { app.swipeDown() }
    attach(app, name: "Social Rivalry real completed history")
    rivalry.tap()
    XCTAssertTrue(app.buttons["startRound"].waitForExistence(timeout: 15))
  }
  func testHomeIllustration() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    if springboard.buttons["Open"].exists { springboard.buttons["Open"].tap() }
    let app = XCUIApplication()
    app.launch()
    for _ in 0..<3 {
      if app.buttons["createChallenge"].waitForExistence(timeout: 3) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    XCTAssertTrue(app.buttons["createChallenge"].exists)
    Thread.sleep(forTimeInterval: 2)
    attach(app, name: "Native home illustration")
  }
  func testNativeChallengePlayShareAndRematch() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let name = app.textFields["onboardingName"]
    if name.waitForExistence(timeout: 15) {
      name.tap()
      name.typeText("Native Ace")
      app.buttons["onboardingContinue"].tap()
    }
    // An earlier run may restore a match. Return to the home screen if needed.
    for _ in 0..<3 where !app.buttons["createChallenge"].exists {
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    let create = app.buttons["createChallenge"]
    XCTAssertTrue(create.waitForExistence(timeout: 20))
    reveal(create, in: app)
    create.tap()
    for number in 1...5 {
      let start = app.buttons["startRound"]
      XCTAssertTrue(start.waitForExistence(timeout: 15))
      reveal(start, in: app)
      start.tap()
      if number == 1 { attach(app, name: "Native cube puzzle") }
      let submit = app.buttons["submitAnswer"]
      reveal(submit, in: app)
      waitEnabled(submit)
      submit.tap()
      if number < 5 {
        let next = app.buttons["nextRound"]
        XCTAssertTrue(next.waitForExistence(timeout: 12))
        reveal(next, in: app)
        waitEnabled(next)
        next.tap()
      }
    }
    XCTAssertTrue(app.staticTexts["resultTitle"].waitForExistence(timeout: 15))
    attach(app, name: "Native results")
    let share = app.buttons["shareChallenge"]
    reveal(share, in: app)
    share.tap()
    let copy = app.cells.matching(NSPredicate(format: "label == 'Copy'")).firstMatch
    XCTAssertTrue(copy.waitForExistence(timeout: 10))
    attach(app, name: "Native share sheet")
    copy.tap()
    let rematch = app.buttons["createRematch"]
    for _ in 0..<8 where !rematch.isHittable { app.swipeDown() }
    XCTAssertTrue(rematch.waitForExistence(timeout: 10))
    rematch.tap()
    XCTAssertTrue(app.buttons["startRound"].waitForExistence(timeout: 15))
  }

  private func waitEnabled(_ element: XCUIElement) {
    if element.exists && element.isEnabled { return }
    wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "enabled == true"), object: element)
      ], timeout: 8)
  }
  private func selectTypeAnswer(in app: XCUIApplication) {
    let button = app.buttons["Type Answer"]
    XCTAssertTrue(button.waitForExistence(timeout: 12))
    reveal(button, in: app)
    button.tap()
  }
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<10 {
      let bottom = app.frame.maxY - (app.buttons["tab.home"].exists ? 110 : 20)
      if element.isHittable
        && (element.identifier == "submitAnswer"
          || (element.frame.midY > app.frame.minY + 100 && element.frame.midY < bottom))
      {
        return
      }
      if element.exists && element.frame.midY < app.frame.minY + 100 {
        app.swipeDown()
      } else {
        app.swipeUp()
      }
    }
  }
  private func send(
    _ session: URLSession, _ path: String, method: String = "GET", credential: String? = nil,
    body: [String: Any]? = nil
  ) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: URL(string: "http://localhost:4000/api/\(path)")!)
    request.httpMethod = method
    if let credential {
      request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let result = try await session.data(for: request)
    XCTAssertEqual((result.1 as? HTTPURLResponse)?.statusCode, 200)
    return result
  }
  private func attach(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func assertRenderedCubes(in app: XCUIApplication) {
    let viewport = app.descendants(matching: .any).matching(identifier: "cubeScene").firstMatch
    XCTAssertTrue(viewport.exists)
    guard viewport.exists, let image = app.screenshot().image.cgImage else { return }
    let scale = CGFloat(image.width) / app.frame.width
    let frame = viewport.frame
    let rect = CGRect(
      x: frame.minX * scale, y: frame.minY * scale,
      width: frame.width * scale, height: frame.height * scale)
    guard let cropped = image.cropping(to: rect) else {
      XCTFail("Missing renderer viewport")
      return
    }
    let width = cropped.width
    let height = cropped.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let purplePixels = pixels.withUnsafeMutableBytes { bytes -> Int in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue)
      else { return 0 }
      context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
      let data = bytes.bindMemory(to: UInt8.self)
      var count = 0
      for i in stride(from: 0, to: data.count, by: 4) {
        let red = Int(data[i])
        let green = Int(data[i + 1])
        let blue = Int(data[i + 2])
        // Cube faces are shaded purple, unlike the pale lavender backdrop.
        if red < 210 && green < 205 && blue > red + 12 { count += 1 }
      }
      return count
    }
    XCTAssertGreaterThan(
      purplePixels, 500, "The native renderer must draw cube faces, not just an empty viewport.")
  }
}
