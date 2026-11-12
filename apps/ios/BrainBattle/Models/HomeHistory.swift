import Foundation

/// Home projections contain no puzzle geometry and never infer a winner from scores.
enum BattleOutcome: String, Sendable {
  case victory, defeat, draw, practice
  var title: String {
    switch self {
    case .victory: "Victory"
    case .defeat: "Defeat"
    case .draw: "Draw"
    case .practice: "Practice"
    }
  }
}

struct HomeBattle: Identifiable, Sendable {
  let id: String
  let mode: MatchMode
  let opponent: PlayerProfile?
  let complete: Bool
  let yoursComplete: Bool
  let roundCount: Int
  let playable: Bool
  let outcome: BattleOutcome?

  init(_ match: BattleMatch) {
    id = match.id
    mode = match.mode
    opponent = match.opponent
    complete = match.complete
    yoursComplete = match.yoursComplete
    roundCount = match.rounds.count
    playable = !match.yoursComplete && match.expiresAt > match.serverNow && match.supported
    if !match.complete {
      outcome = nil
    } else if match.mode == .solo {
      outcome = .practice
    } else if match.winner == "draw" {
      outcome = .draw
    } else if match.winner == match.you.id {
      outcome = .victory
    } else if let opponent = match.opponent, match.winner == opponent.id {
      outcome = .defeat
    } else {
      outcome = nil
    }
  }
}

struct FeaturedRivalry: Sendable {
  let opponent: PlayerProfile
  let lastMatchID: String
  let wins: Int
  let losses: Int
  let draws: Int

  var message: String {
    if wins > losses {
      let lead = wins - losses
      return "You’re leading by \(lead) \(lead == 1 ? "win" : "wins")!"
    }
    if losses > wins { return "Your next comeback starts here." }
    return "All square. Time for a tiebreaker?"
  }
}

struct HomeHistory: Sendable {
  /// Ordered by the backend's newest-first match summary, limited to eight matches.
  let battles: [HomeBattle]
  static let empty = HomeHistory(battles: [])

  var completed: [HomeBattle] { battles.filter { $0.complete && $0.outcome != nil } }
  var pending: [HomeBattle] {
    battles.filter { $0.mode == .challenge && $0.opponent != nil && $0.playable }
  }
  var otherPlayable: [HomeBattle] {
    battles.filter { $0.playable && ($0.mode == .solo || $0.opponent == nil) }
  }
  var waiting: [HomeBattle] {
    battles.filter { $0.mode == .challenge && $0.yoursComplete && !$0.complete }
  }
  var rivalry: FeaturedRivalry? {
    guard let latest = completed.first(where: { $0.mode == .challenge }),
      let opponent = latest.opponent
    else { return nil }
    let headToHead = completed.filter {
      $0.mode == .challenge && $0.opponent?.id == opponent.id
    }
    return FeaturedRivalry(
      opponent: opponent, lastMatchID: latest.id,
      wins: headToHead.filter { $0.outcome == .victory }.count,
      losses: headToHead.filter { $0.outcome == .defeat }.count,
      draws: headToHead.filter { $0.outcome == .draw }.count)
  }
}
