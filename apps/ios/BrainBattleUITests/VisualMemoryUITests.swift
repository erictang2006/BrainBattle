import XCTest

/// Start scripts/visual-memory-fixture.ts; uses only its isolated in-memory API on 4016.
@MainActor final class VisualMemoryUITests: XCTestCase {
  func testSoloHeartsGameOverAndPlayAgain() async throws {
    #if !DEBUG
      throw XCTSkip("Use Debug and the isolated Visual Memory API on 4016.")
    #else
      continueAfterFailure = false
      let app = XCUIApplication()
      app.launchArguments = [
        "-debug.apiOrigin", "http://127.0.0.1:4016",
        "-debug.webOrigin", "http://127.0.0.1:4016",
      ]
      app.launch()
      if app.textFields["onboardingName"].waitForExistence(timeout: 8) {
        app.textFields["onboardingName"].tap()
        app.textFields["onboardingName"].typeText("Memory Tester")
        app.buttons["onboardingContinue"].tap()
      }
      for _ in 0..<6 {
        if app.buttons["tab.games"].exists { break }
        if app.navigationBars.buttons.firstMatch.exists {
          app.navigationBars.buttons.firstMatch.tap()
        }
      }
      XCTAssertTrue(app.buttons["tab.games"].waitForExistence(timeout: 10))
      app.buttons["tab.games"].tap()
      reveal(app.buttons["playVisualMemory"], app: app)
      app.buttons["playVisualMemory"].tap()
      reveal(app.buttons["memorySolo"], app: app)
      app.buttons["memorySolo"].tap()
      XCTAssertTrue(app.staticTexts["memoryLevel"].waitForExistence(timeout: 15))
      XCTAssertEqual(app.staticTexts["memoryLevel"].label, "Level 1")
      for remaining in stride(from: 2, through: 0, by: -1) {
        let retry = app.buttons["memoryRetry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        reveal(retry, app: app)
        XCTAssertTrue(
          app.descendants(matching: .any).matching(identifier: "memoryLives").firstMatch.isHittable)
        if remaining == 2 {
          let capture = XCTAttachment(screenshot: app.screenshot())
          capture.name = "Visual Memory recall grid"
          capture.lifetime = .keepAlways
          add(capture)
        }
        retry.tap()
        app.buttons["Retry · Lose 1 heart"].tap()
        if remaining > 0 {
          let hearts = app.descendants(matching: .any).matching(identifier: "memoryLives")
            .firstMatch
          XCTAssertTrue(hearts.waitForExistence(timeout: 5))
          XCTAssertEqual(hearts.label, "\(remaining) lives remaining")
          // Relaunch while the second pattern is scheduled; the same heart count must survive.
          if remaining == 1 {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.staticTexts["memoryLevel"].waitForExistence(timeout: 15))
            XCTAssertEqual(
              app.descendants(matching: .any).matching(identifier: "memoryLives").firstMatch.label,
              "1 lives remaining")
          }
        }
      }
      XCTAssertTrue(app.staticTexts["memoryGameOver"].waitForExistence(timeout: 12))
      XCTAssertTrue(app.staticTexts["memoryFinalScore"].label.contains("0 hearts remaining"))
      let results = XCTAttachment(screenshot: app.screenshot())
      results.name = "Visual Memory results"
      results.lifetime = .keepAlways
      add(results)
      reveal(app.buttons["memoryPlayAgain"], app: app)
      app.buttons["memoryPlayAgain"].tap()
      XCTAssertTrue(app.staticTexts["memoryLevel"].waitForExistence(timeout: 15))
      XCTAssertEqual(app.staticTexts["memoryLevel"].label, "Level 1")
      XCTAssertEqual(
        app.descendants(matching: .any).matching(identifier: "memoryLives").firstMatch.label,
        "3 lives remaining")
    #endif
  }
  func testVisualMemoryInBothLiveModeSelectors() throws {
    #if !DEBUG
      throw XCTSkip("Use Debug and the isolated Visual Memory API on 4016.")
    #else
      let app = XCUIApplication()
      app.launchArguments = [
        "-debug.apiOrigin", "http://127.0.0.1:4016", "-debug.webOrigin", "http://127.0.0.1:4016",
      ]
      app.launch()
      if app.textFields["onboardingName"].waitForExistence(timeout: 5) {
        app.textFields["onboardingName"].tap()
        app.textFields["onboardingName"].typeText("Memory Tester")
        app.buttons["onboardingContinue"].tap()
      }
      for _ in 0..<6 {
        if app.buttons["tab.games"].exists { break }
        if app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 3) {
          app.navigationBars.buttons.firstMatch.tap()
        }
      }
      XCTAssertTrue(app.buttons["tab.games"].waitForExistence(timeout: 10))
      app.buttons["tab.games"].tap()
      reveal(app.buttons["playVisualMemory"], app: app)
      app.buttons["playVisualMemory"].tap()
      reveal(app.buttons["memoryLive"], app: app)
      app.buttons["memoryLive"].tap()
      XCTAssertTrue(app.segmentedControls["liveGameSelection"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.segmentedControls["liveGameSelection"].buttons["Visual Memory"].isSelected)
      app.segmentedControls.buttons["Party Mode"].tap()
      reveal(app.buttons["createLiveRoom"], app: app)
      app.buttons["createLiveRoom"].tap()
      XCTAssertTrue(app.buttons["liveReady"].waitForExistence(timeout: 15))
      XCTAssertTrue(app.staticTexts["Visual Memory · 2 minutes · 3 hearts"].exists)
    #endif
  }
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
  }
}
