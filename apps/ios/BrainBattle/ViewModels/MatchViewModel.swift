import Foundation
import Observation

@MainActor @Observable final class MatchViewModel {
  private let api: any BrainAPI
  let id: String
  private(set) var match: BattleMatch?
  private(set) var clock: ServerClock?
  var selectedRound: Int? {
    didSet {
      guard let prefix = draftPrefix, let selectedRound else { return }
      UserDefaults.standard.set(selectedRound, forKey: "\(prefix).selectedRound")
    }
  }
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
  private struct PendingAnswer: Codable {
    let id: UUID
    let value: Int
  }
  private var pendingAnswers: [Int: PendingAnswer] = [:]
  private var submissionFailure: String?
  var submissionUncertain: Bool {
    guard let number = currentRound?.number, currentRound?.state != .done else { return false }
    return pendingAnswers[number] != nil
  }
  var showsFinalResults: Bool {
    guard let match else { return false }
    return match.yoursComplete && (selectedRound ?? 0) > match.rounds.count
  }
  private func pendingKey(_ number: Int) -> String? {
    draftPrefix.map { "\($0).pending.\(number)" }
  }
  private func clearPending(_ number: Int) {
    pendingAnswers.removeValue(forKey: number)
    if let key = pendingKey(number) { UserDefaults.standard.removeObject(forKey: key) }
  }
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
    for round in result.rounds where round.state == .done { clearPending(round.number) }
    if currentRound?.state == .done { submissionFailure = nil }
    if let number = currentRound?.number, draftRound != number {
      draftRound = number
      let saved = draftPrefix.flatMap { UserDefaults.standard.string(forKey: "\($0).\(number)") }
      answer =
        pendingAnswers[number].map { String($0.value) }
        ?? saved.flatMap { Int($0) }.flatMap { (0...100).contains($0) ? String($0) : nil } ?? "0"
    }
    error = submissionFailure
  }
  func restoreDraft(scope: String) {
    let prefix = "countDraft.\(scope).\(id)"
    guard draftPrefix != prefix else { return }
    draftPrefix = prefix
    let saved = UserDefaults.standard.integer(forKey: "\(prefix).selectedRound")
    if (1...11).contains(saved) { selectedRound = saved }
    for number in 1...10 {
      if let data = UserDefaults.standard.data(forKey: "\(prefix).pending.\(number)"),
        let pending = try? JSONDecoder().decode(PendingAnswer.self, from: data)
      {
        pendingAnswers[number] = pending
      }
    }
  }
  func increment() {
    guard !busy, !submissionUncertain else { return }
    if let value = Int(answer), value < 100 { answer = String(value + 1) }
  }
  func decrement() {
    guard !busy, !submissionUncertain else { return }
    answer = String(max(0, (Int(answer) ?? 0) - 1))
  }
  func clearAnswer() {
    guard !busy, !submissionUncertain else { return }
    answer = "0"
  }
  func deleteDigit() {
    guard !busy, !submissionUncertain else { return }
    answer = answer.count > 1 ? String(answer.dropLast()) : "0"
  }
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
    submissionFailure = nil
    error = nil
    defer { busy = false }
    do { try accept(await api.startRound(matchID: id, number: round.number)) } catch {
      self.error = error.localizedDescription
    }
  }
  func submit() async {
    // The first tap owns the operation. Duplicate taps cannot issue a second request.
    guard !busy else { return }
    guard let round = currentRound else {
      error = "The round is still loading. Refresh and try again."
      return
    }
    guard round.state != .done else { return }
    guard let value = Int(answer), (0...100).contains(value) else {
      error = "Enter a whole number between 0 and 100."
      return
    }
    busy = true
    requestVersion += 1  // Supersede any poll that began before this operation.
    selectedRound = round.number
    let pending = pendingAnswers[round.number] ?? PendingAnswer(id: UUID(), value: value)
    pendingAnswers[round.number] = pending
    answer = String(pending.value)
    if let key = pendingKey(round.number), let data = try? JSONEncoder().encode(pending) {
      UserDefaults.standard.set(data, forKey: key)
    }
    submissionFailure = nil
    error = nil
    defer { busy = false }
    do {
      // No local countdown gate: the authoritative server accepts, rejects, or
      // finalizes an expired attempt, including rounds with no answer deadline.
      let result = try await api.submit(
        matchID: id, number: round.number,
        answer: pending.value, submissionID: pending.id)
      try accept(result)
      if currentRound?.state != .done {
        submissionFailure = "Your answer has not been finalized. Refresh or retry your submission."
        error = submissionFailure
      }
    } catch {
      let original = error
      // A definitive client rejection did not score this request. Unknown network
      // outcomes retain the exact UUID AND answer for safe retries and relaunches.
      if let problem = original as? APIError, (400..<500).contains(problem.status) {
        clearPending(round.number)
      }
      submissionFailure =
        original is CancellationError
        ? "Submission interrupted. Reconnect and retry the same answer."
        : "\(original.localizedDescription) Refresh or retry your submission."
      self.error = submissionFailure
      do {
        // The write may have committed even when its response was lost.
        try accept(await api.match(id: id))
      } catch { self.error = submissionFailure }
    }
  }
  func nextRound() {
    guard !busy, let round = currentRound else { return }
    guard round.state == .done else {
      error = "Submit your answer before moving to the next round."
      return
    }
    if let feedbackUntil = round.feedbackUntil,
      clock == nil || clock!.milliseconds() < feedbackUntil
    {
      error = "Please wait for the round feedback to finish."
      return
    }
    submissionFailure = nil
    error = nil
    selectedRound = round.number + 1
    answer = "0"
  }
  func digit(_ digit: String) {
    guard !busy, !submissionUncertain else { return }
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
