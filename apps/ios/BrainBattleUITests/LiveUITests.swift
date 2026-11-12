import XCTest

/// Run scripts/live-ui-fixture.ts beside the existing local API.
@MainActor final class LiveUITests: XCTestCase {
  func testNativeJoinReadyPlayAndResult() async throws { try await play(party: false) }
  func testEightPlayerPartyAndRematch() async throws { try await play(party: true) }
  private func play(party: Bool) async throws {
    continueAfterFailure = false
    let (data, _) = try await URLSession.shared.data(
      from: URL(string: party ? "http://127.0.0.1:4011/party" : "http://127.0.0.1:4011")!)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let code = try XCTUnwrap(object["code"] as? String)
    let app = XCUIApplication()
    app.launch()
    if app.textFields["onboardingName"].waitForExistence(timeout: 2) {
      app.textFields["onboardingName"].tap()
      app.textFields["onboardingName"].typeText("Live Rival")
      app.buttons["onboardingContinue"].tap()
    }
    for _ in 0..<4 {
      if app.buttons["playLive"].waitForExistence(timeout: 2) { break }
      if app.navigationBars.buttons.firstMatch.exists {
        app.navigationBars.buttons.firstMatch.tap()
      }
    }
    reveal(app.buttons["playLive"], app: app)
    app.buttons["playLive"].tap()
    let field = app.textFields["liveCode"]
    try require(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText(code)
    reveal(app.buttons["joinLiveRoom"], app: app)
    app.buttons["joinLiveRoom"].tap()
    let ready = app.buttons["liveReady"]
    try require(ready.waitForExistence(timeout: 10))
    reveal(ready, app: app)
    ready.tap()
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
