import UIKit
import XCTest

@testable import BrainBattle

final class RulesPresentationTests: XCTestCase {
  @MainActor func testCubeGroundNeverSharesDepthSortingAndBackFacesStayHidden() async throws {
    let puzzle = CubePuzzle(
      cubes: [
        Cube(x: 0, y: 0, z: 0), Cube(x: 1, y: 0, z: 0), Cube(x: 1, y: 1, z: 0),
        Cube(x: 3, y: 0, z: 3), Cube(x: 3, y: 1, z: 3), Cube(x: 3, y: 2, z: 3),
        Cube(x: 0, y: 0, z: 4),
      ], gridSize: 5)
    let controller = UIViewController()
    controller.view.backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.99, alpha: 1)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 320))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
    }
    let scene = CubeLayerView(frame: controller.view.bounds.insetBy(dx: 12, dy: 12))
    controller.view.addSubview(scene)
    for yaw: CGFloat in [0, -0.55, 0.55] {
      scene.configure(
        puzzle: puzzle, illustration: false, yaw: yaw, reduceMotion: true, revealCount: nil)
      scene.layoutIfNeeded()
      let layers = try XCTUnwrap(scene.layer.sublayers)
      XCTAssertEqual(layers.map(\.name), ["cube-ground", "cube-world"])
      XCTAssertEqual(layers[0].sublayers?.count, 25)
      XCTAssertEqual(layers[1].sublayers?.count, puzzle.cubes.count)
      XCTAssertTrue(CATransform3DEqualToTransform(layers[0].transform, layers[1].transform))
      for cube in layers[1].sublayers ?? [] {
        XCTAssertEqual(cube.sublayers?.map(\.isHidden), [true, false, false, true, false, true])
      }
      try await Task.sleep(for: .milliseconds(100))
      let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = "Cube depth and ground yaw \(yaw)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    // Reveal fading must not bring rear walls back into the normal camera view.
    scene.configure(puzzle: puzzle, illustration: false, yaw: 0, reduceMotion: true, revealCount: 1)
    for cube in scene.layer.sublayers?.last?.sublayers ?? [] {
      XCTAssertEqual(cube.sublayers?.map(\.isHidden), [true, false, false, true, false, true])
    }
  }
  func testV2MetadataDecodesAndUsesShortServerWindows() throws {
    let data = Data(
      """
      {"id":"v2","mode":"solo","gameId":"counting-boxes","rulesVersion":2,"you":{"id":"a","name":"A"},"opponent":null,"rounds":[{"number":5,"state":"display","displayUntil":102000,"deadline":107000,"finalized":false,"rules":{"difficulty":"hard","displayMs":2000,"answerMs":5000,"feedbackMs":1000,"gridSize":5},"puzzle":{"gridSize":5,"cubes":[{"x":4,"y":0,"z":4}]}}],"expiresAt":200000,"complete":false,"yoursComplete":false,"total":0,"serverNow":100000}
      """.utf8)
    let match = try JSONDecoder().decode(BattleMatch.self, from: data)
    XCTAssertTrue(match.supported)
    XCTAssertEqual(match.rounds[0].puzzle?.gridSize, 5)
    XCTAssertEqual(match.rounds[0].timeProgress(at: 101000), 0.5)
    XCTAssertEqual(match.rounds[0].phase(at: 102000), .answer)
    XCTAssertEqual(match.rounds[0].timeProgress(at: 104500), 0.5)
    XCTAssertEqual(match.rounds[0].remaining(at: 107000), 0)
  }
  func testCountdownProgressUsesPersistedWindowsWithoutExtendingThem() {
    let round = GameRound(
      number: 1, state: .display, displayUntil: 108_000, deadline: 120_000,
      puzzle: .illustration, attempt: nil, opponent: nil, finalized: false)
    XCTAssertEqual(round.timeProgress(at: 100_000), 1)
    XCTAssertEqual(round.timeProgress(at: 104_000), 0.5)
    XCTAssertEqual(round.phase(at: 108_000), .answer)
    XCTAssertEqual(round.timeProgress(at: 108_000), 1)
    XCTAssertEqual(round.timeProgress(at: 114_000), 0.5)
    XCTAssertEqual(round.timeProgress(at: 120_000), 0)
    XCTAssertEqual(round.timeProgress(at: 130_000), 0)
    XCTAssertEqual(round.displayUntil, 108_000)
    XCTAssertEqual(round.deadline, 120_000)
  }

  func testClockUsesElapsedUptimeRatherThanWallTime() {
    let clock = ServerClock(serverMilliseconds: 100_000, uptime: 50)
    XCTAssertEqual(clock.milliseconds(uptime: 52.5), 102_500)
    XCTAssertEqual(clock.milliseconds(uptime: 49), 100_000)
  }
  func testLocalDisplayAlwaysHidesAtServerDeadline() {
    let round = GameRound(
      number: 1, state: .display, displayUntil: 108_000, deadline: 120_000, puzzle: .illustration,
      attempt: nil, opponent: nil, finalized: false)
    XCTAssertEqual(round.phase(at: 107_999), .display)
    XCTAssertEqual(round.phase(at: 108_000), .answer)
    XCTAssertEqual(round.remaining(at: 119_999), 1)
    XCTAssertEqual(round.remaining(at: 120_000), 0)
  }
  func testInvitationParserAcceptsOnlyConfiguredOriginAndValidatedTokens() {
    let origin = URL(string: "https://brain.example")!
    let token = String(repeating: "a", count: 48)
    XCTAssertEqual(
      InvitationLink.token(from: "https://brain.example/invite/\(token)", webOrigin: origin), token)
    XCTAssertEqual(
      InvitationLink.token(from: "brainbattle://invite/\(token)", webOrigin: origin), token)
    for invalid in [
      "https://evil.example/invite/\(token)", "https://brain.example/invite/short",
      "https://brain.example/invite/\(token)?next=evil",
      "https://user@brain.example/invite/\(token)", "brainbattle://delete/\(token)",
      "https://brain.example/invite/\(String(repeating: "g", count: 48))",
    ] {
      XCTAssertNil(InvitationLink.token(from: invalid, webOrigin: origin), invalid)
    }
  }
  func testNativeChallengeCodesAndSharedMessagesNeedNoWebsite() throws {
    let origin = URL(string: "https://brain-battle-api.onrender.com")!
    let token = String(repeating: "a1", count: 24)
    for input in [
      token, " \(token.uppercased())\n", InvitationLink.shareText(token),
      "brainbattle://invite/\(token)",
    ] {
      XCTAssertEqual(InvitationLink.token(from: input, webOrigin: origin), token)
    }
    for input in [
      String(repeating: "a", count: 47), String(repeating: "a", count: 49),
      String(repeating: "g", count: 48), "Challenge code: \(token)",
      "Brain Battle challenge\nChallenge code: \(token)\nChallenge code: \(token)",
      "https://evil.example/invite/\(token)",
    ] {
      XCTAssertNil(InvitationLink.token(from: input, webOrigin: origin))
    }
    let data = Data(
      """
      {"id":"native","mode":"challenge","gameId":"counting-boxes","rulesVersion":1,"you":{"id":"a","name":"A"},"opponent":null,"rounds":[],"inviteUrl":"http://localhost:3000/invite/\(token)","expiresAt":200000,"complete":false,"yoursComplete":false,"total":0,"serverNow":100000}
      """.utf8)
    let match = try JSONDecoder().decode(BattleMatch.self, from: data)
    XCTAssertEqual(match.invitationToken, token)
    let text = try XCTUnwrap(match.challengeShareText)
    XCTAssertTrue(text.contains(token))
    XCTAssertFalse(text.contains("http"))
    XCTAssertFalse(text.contains("localhost"))
    XCTAssertEqual(InvitationLink.token(from: text, webOrigin: origin), token)
  }
  func testPublicMatchContractDecodesAbsentOpponentAndHiddenResults() throws {
    let data = Data(
      """
      {"id":"match","mode":"challenge","gameId":"counting-boxes","rulesVersion":1,"you":{"id":"a","name":"A"},"opponent":null,"rounds":[{"number":1,"state":"ready","finalized":false}],"expiresAt":200000,"complete":false,"yoursComplete":false,"total":0,"serverNow":100000}
      """.utf8)
    let match = try JSONDecoder().decode(BattleMatch.self, from: data)
    XCTAssertTrue(match.supported)
    XCTAssertNil(match.opponentTotal)
    XCTAssertNil(match.winner)
    XCTAssertNil(match.rounds[0].puzzle)
    let encoded = String(decoding: try JSONEncoder().encode(match), as: UTF8.self)
    XCTAssertFalse(encoded.contains("seed"))
    XCTAssertFalse(encoded.contains("correctAnswer"))
  }
}
