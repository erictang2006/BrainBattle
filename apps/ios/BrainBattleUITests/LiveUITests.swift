import XCTest

/// Run scripts/live-ui-fixture.ts. Set BRAIN_TEST_API to exercise hosted Release rooms.
@MainActor final class LiveUITests: XCTestCase {
  func testNativeJoinReadyPlayAndResult() async throws { try await play(party: false) }
  func testEightPlayerPartyAndRematch() async throws { try await play(party: true) }
  private func play(party: Bool) async throws {
    continueAfterFailure = false
    var code = ""
    if !party {
      let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:4011")!)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      code = try XCTUnwrap(object["code"] as? String)
    }
    let app = XCUIApplication()
    app.launch()
    if app.textFields["onboardingName"].waitForExistence(timeout: 2) {
      app.textFields["onboardingName"].tap()
      app.textFields["onboardingName"].typeText("Live Rival")
      app.buttons["onboardingContinue"].tap()
    }
    for _ in 0..<4 {
      if app.buttons["tab.home"].exists { app.buttons["tab.home"].tap() }
      if app.buttons["playLive"].waitForExistence(timeout: 2) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    reveal(app.buttons["playLive"], app: app)
    app.buttons["playLive"].tap()
    try require(app.buttons["createLiveRoom"].waitForExistence(timeout: 15))
    if party {
      app.segmentedControls.buttons["Party Mode"].tap()
      app.buttons["createLiveRoom"].tap()
      try require(app.buttons["liveReady"].waitForExistence(timeout: 20))
      code = app.staticTexts["liveRoomCode"].label
      let (_, response) = try await URLSession.shared.data(
        from: URL(string: "http://127.0.0.1:4011/join/\(code)/party")!)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    } else {
      let field =
        app.textFields["liveCode"].exists ? app.textFields["liveCode"] : app.textViews["liveCode"]
      try require(field.waitForExistence(timeout: 10))
      field.tap()
      field.typeText(code)
      reveal(app.buttons["joinLiveRoom"], app: app)
      app.buttons["joinLiveRoom"].tap()
    }
    let ready = app.buttons["liveReady"]
    try require(ready.waitForExistence(timeout: 20))
    reveal(ready, app: app)
    ready.tap()
    if party {
      let start = app.buttons["liveStart"]
      try require(start.waitForExistence(timeout: 10))
      for _ in 0..<50 {
        if start.isEnabled { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      try require(start.isEnabled)
      reveal(start, app: app)
      start.tap()
    }
    for number in 1...5 {
      try require(app.staticTexts["Round \(number) · Counting Boxes"].waitForExistence(timeout: 15))
      let done = app.buttons["liveSubmit"]
      try require(done.waitForExistence(timeout: 12))
      reveal(done, app: app)
      done.tap()
      if number < 5 {
        try require(app.staticTexts["Round \(number) complete"].waitForExistence(timeout: 10))
      }
    }
    try require(app.buttons["Back to Home"].waitForExistence(timeout: 12))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Native live final result"
    attachment.lifetime = .keepAlways
    add(attachment)
    reveal(app.buttons["Rematch"], app: app)
    app.buttons["Rematch"].tap()
    try require(app.buttons["liveReady"].waitForExistence(timeout: 10))
    XCTAssertNotEqual(app.staticTexts["liveRoomCode"].label, code)
  }
  private func require(_ condition: Bool) throws {
    guard condition else { throw NSError(domain: "Live UI condition timed out", code: 1) }
  }
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<5 {
      if element.isHittable { return }
      app.swipeUp()
    }
  }
}
