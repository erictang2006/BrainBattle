import Foundation
import Observation

@MainActor @Observable final class MatchViewModel {
  private let api: any BrainAPI
  let id: String
  private(set) var match: BattleMatch?
  private(set) var clock: ServerClock?
  var selectedRound: Int?
  var answer = "0" {
    didSet {
      if let prefix = draftPrefix, let number = currentRound?.number {
        UserDefaults.standard.set(answer, forKey: "\(prefix).\(number)")
      }
    }
  }
  private var draftPrefix: String?
  private var draftRound: Int?
  var busy = false
  var error: String?
  private var requestVersion = 0
  private var submissionIDs: [Int: UUID] = [:]
  var currentRound: GameRound? {
    guard let match else { return nil }
    return match.rounds.first(where: { $0.number == selectedRound }) ?? match.rounds.first(where: {
      $0.state != .done
    }) ?? match.rounds.last
  }
  init(id: String, api: any BrainAPI) {
    self.id = id
    self.api = api
  }
  private func accept(_ result: BattleMatch) throws {
    guard result.supported else {
      throw APIError(
        status: 0, message: "This match uses a newer game version. Update Brain Battle to play.")
    }
    clock = ServerClock(serverMilliseconds: result.serverNow)
    if selectedRound == nil {
      selectedRound =
        result.rounds.first(where: { $0.state != .done })?.number
        ?? result.rounds.last?.number
    }
    match = result
    if let number = currentRound?.number, draftRound != number {
      draftRound = number
      let saved = draftPrefix.flatMap { UserDefaults.standard.string(forKey: "\($0).\(number)") }
      answer =
        saved.flatMap { Int($0) }.flatMap { (0...100).contains($0) ? String($0) : nil } ?? "0"
    }
    error = nil
  }
  func restoreDraft(scope: String) {
    draftPrefix = "countDraft.\(scope).\(id)"
  }
  func increment() { if let value = Int(answer), value < 100 { answer = String(value + 1) } }
  func decrement() { answer = String(max(0, (Int(answer) ?? 0) - 1)) }
  func clearAnswer() { answer = "0" }
  func deleteDigit() { answer = answer.count > 1 ? String(answer.dropLast()) : "0" }
  func refresh() async {
    guard !busy else { return }
    requestVersion += 1
    let version = requestVersion
    do {
      let result = try await api.match(id: id)
      guard version == requestVersion else { return }
      try accept(result)
    } catch is CancellationError {} catch {
      if (error as? URLError)?.code != .cancelled, version == requestVersion {
        self.error = error.localizedDescription
      }
    }
  }
  func poll() async {
    await refresh()
    while !Task.isCancelled {
      do { try await Task.sleep(for: .seconds(2)) } catch { return }
      await refresh()
    }
  }
  func start() async {
    guard !busy, let round = currentRound else { return }
    busy = true
    requestVersion += 1
    selectedRound = round.number
    answer = "0"
    defer { busy = false }
    do { try accept(await api.startRound(matchID: id, number: round.number)) } catch {
      self.error = error.localizedDescription
    }
  }
  func submit() async {
    guard !busy, let round = currentRound, let value = Int(answer), (0...100).contains(value) else {
      return
    }
    guard let clock, round.phase(at: clock.milliseconds()) == .answer,
      round.remaining(at: clock.milliseconds()) > 0
    else { return }
    busy = true
    requestVersion += 1
    selectedRound = round.number
    // A retry, even after an uncertain network response, reuses its submission ID.
    let key = submissionIDs[round.number] ?? UUID()
    submissionIDs[round.number] = key
    defer { busy = false }
    do {
      try accept(
        await api.submit(matchID: id, number: round.number, answer: value, submissionID: key))
    } catch { self.error = error.localizedDescription }
  }
  func nextRound() {
    if let round = currentRound {
      if let feedbackUntil = round.feedbackUntil, let clock,
        clock.milliseconds() < feedbackUntil
      {
        return
      }
      selectedRound = round.number + 1
      answer = "0"
    }
  }
  func digit(_ digit: String) {
    let candidate = answer == "0" ? digit : answer + digit
    if let value = Int(candidate), candidate.count <= 3, value <= 100 { answer = candidate }
  }
  func rematch() async -> BattleMatch? {
    guard !busy else { return nil }
    busy = true
    defer { busy = false }
    do { return try await api.rematch(id: id) } catch {
      self.error = error.localizedDescription
      return nil
    }
  }
}
