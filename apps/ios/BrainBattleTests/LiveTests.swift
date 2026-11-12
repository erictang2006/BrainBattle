import XCTest

@testable import BrainBattle

final class LiveTests: XCTestCase {
  func testRoomCodeAndNativeLinks() {
    XCTAssertEqual(LiveRoomCode.parse(" abc234 \n"), "ABC234")
    XCTAssertEqual(LiveRoomCode.parse("brainbattle://room/ABC234"), "ABC234")
    for invalid in [
      "AAAAA", "ABC230", "https://evil.example/ABC234", "brainbattle://room/ABC234?token=secret",
      "brainbattle://room/ABC234/other",
    ] {
      XCTAssertNil(LiveRoomCode.parse(invalid))
    }
  }
  func testSocketIOFramesAndHeartbeat() throws {
    guard case .open = try SocketIOWire.decode("0{\"sid\":\"abc\",\"pingInterval\":25000}") else {
      return XCTFail("Engine.IO open")
    }
    guard case .connected = try SocketIOWire.decode("40{\"sid\":\"socket\"}") else {
      return XCTFail("Socket.IO connect")
    }
    guard case .ping(let value) = try SocketIOWire.decode("2probe") else {
      return XCTFail("Heartbeat")
    }
    XCTAssertEqual(value, "probe")
    guard
      case .ack(let id, let data) = try SocketIOWire.decode("4312[{\"ok\":true,\"serverNow\":123}]")
    else { return XCTFail("ACK") }
    XCTAssertEqual(id, 12)
    XCTAssertEqual(try JSONDecoder().decode(LiveAck.self, from: data).serverNow, 123)
    XCTAssertThrowsError(try SocketIOWire.decode("44{\"message\":\"Authentication required\"}"))
    let frame = try SocketIOWire.event(
      "room:watch", payload: Data(#"{"code":"ABC234"}"#.utf8), id: 7)
    XCTAssertTrue(frame.hasPrefix("427["))
    let decoded = try JSONSerialization.jsonObject(with: Data(frame.dropFirst(3).utf8)) as? [Any]
    XCTAssertEqual(decoded?.first as? String, "room:watch")
  }
  func testSharedRoundUsesAbsoluteServerDeadlines() throws {
    let data = Data(
      #"{"number":1,"startsAt":1000,"displayUntil":4000,"deadline":10000,"rules":{"difficulty":"easy","displayMs":3000,"answerMs":6000,"feedbackMs":1000,"gridSize":5},"submitted":[]}"#
        .utf8)
    let round = try JSONDecoder().decode(LiveRound.self, from: data)
    XCTAssertEqual(round.phase(at: 999), "prepare")
    XCTAssertEqual(round.phase(at: 1000), "display")
    XCTAssertEqual(round.phase(at: 4000), "answer")
    XCTAssertEqual(round.phase(at: 10000), "waiting")
    let clock = ServerClock(serverMilliseconds: 4000, uptime: 10)
    XCTAssertEqual(round.phase(at: clock.milliseconds(uptime: 16)), "waiting")
  }
}
