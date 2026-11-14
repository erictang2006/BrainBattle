import SwiftUI

struct ResultsView: View {
  let match: BattleMatch
  let busy: Bool
  let rematch: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  private var title: String {
    if match.mode == .solo { return "Nicely done, brain." }
    if !match.complete { return "Your score is set." }
    if match.winner == "draw" { return "Great minds. It’s a draw!" }
    return match.winner == match.you.id
      ? "You won this one!" : "\(match.opponent?.name ?? "Your friend") takes it!"
  }
  private var won: Bool { match.complete && match.winner == match.you.id }
  private var accent: Color {
    if match.mode == .solo { return BattleTheme.peach }
    if !match.complete || match.winner == "draw" { return BattleTheme.lavender }
    return won ? BattleTheme.mint : BattleTheme.pink
  }
  private var symbol: String {
    if match.mode == .solo { return "sparkles" }
    if !match.complete { return "hourglass" }
    return match.winner == "draw" ? "equal" : won ? "trophy" : "flag.checkered"
  }
  var body: some View {
    VStack(spacing: 22) {
      VStack(spacing: 16) {
        Image(systemName: symbol).font(.system(size: 34, weight: .medium))
          .frame(width: 84, height: 84).background(accent, in: RoundedRectangle(cornerRadius: 28))
        Eyebrow(
          text: match.mode == .solo
            ? "Practice complete" : match.complete ? "Battle complete" : "Over to your rival")
        Text(title).font(.system(.largeTitle, design: .rounded, weight: .heavy)).tracking(-1)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("resultTitle")
        Text(
          match.complete
            ? "A little competition looks good on you."
            : "\(match.rounds.count) rounds down. Your friend’s score unlocks when they finish."
        )
        .font(.subheadline).foregroundStyle(BattleTheme.muted).multilineTextAlignment(.center)
      }.padding(.top, 10)
      let scoresLayout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(spacing: 12))
        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
      scoresLayout {
        score(name: match.you.name, value: match.total, detail: "You", color: accent)
        if match.mode == .challenge {
          score(
            name: match.opponent?.name ?? "Your friend",
            value: match.complete ? match.opponentTotal : nil,
            detail: "Your rival", color: BattleTheme.blue)
        }
      }
      HStack(spacing: 7) {
        Image(systemName: "checkmark.circle")
        Text(
          "\(match.rounds.filter { $0.attempt?.correct == true }.count) of \(match.rounds.count) correct"
        )
        Text("· Counting Boxes")
      }.font(.caption).foregroundStyle(BattleTheme.muted)
        .accessibilityElement(children: .combine)
      VStack(alignment: .leading, spacing: 14) {
        Text("The round-up").font(.system(.title3, design: .rounded, weight: .bold))
        ForEach(match.rounds) { round in
          let rowLayout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
          rowLayout {
            HStack(spacing: 10) {
              Image(systemName: round.attempt?.correct == true ? "checkmark" : "minus")
                .font(.caption.bold()).frame(width: 28, height: 28)
                .background(
                  round.attempt?.correct == true ? BattleTheme.mint : BattleTheme.peach,
                  in: Circle()
                )
                .accessibilityLabel(round.attempt?.correct == true ? "Correct" : "No points")
              Text("Round \(round.number)").font(.subheadline).foregroundStyle(BattleTheme.muted)
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
              Text((round.attempt?.score ?? 0).formatted()).font(
                .system(.subheadline, design: .rounded, weight: .bold)
              )
              .accessibilityLabel("You, \(round.attempt?.score ?? 0) points")
              if match.mode == .challenge {
                if round.finalized, let opponent = round.opponent {
                  Text(opponent.score.formatted()).font(.subheadline).foregroundStyle(
                    BattleTheme.muted
                  )
                  .frame(minWidth: 48, alignment: .trailing).accessibilityLabel(
                    "Friend, \(opponent.score) points")
                } else {
                  Image(systemName: "lock.fill").font(.caption).foregroundStyle(BattleTheme.muted)
                    .frame(minWidth: 48, alignment: .trailing).accessibilityLabel(
                      "Friend’s result hidden")
                }
              }
            }
          }.padding(.vertical, 4)
          if round.number != match.rounds.last?.number { Divider() }
        }
        if match.mode == .challenge {
          Text("Your points first · Your rival’s points second").font(.caption2).foregroundStyle(
            BattleTheme.muted)
        }
      }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
      Button(action: rematch) {
        Label(
          busy ? "Creating…" : match.mode == .solo ? "Practice again" : "Create a rematch",
          systemImage: "arrow.counterclockwise")
      }.buttonStyle(BattleButtonStyle()).disabled(busy).accessibilityIdentifier("createRematch")
      if match.mode == .challenge {
        Text("Fresh puzzles. Fresh bragging rights.").font(.caption).foregroundStyle(
          BattleTheme.muted)
      }
    }.frame(maxWidth: .infinity)
  }
  private func score(name: String, value: Int?, detail: String, color: Color) -> some View {
    VStack(spacing: 10) {
      PlayerAvatar(name: name, color: .white.opacity(0.7), size: 38)
      Text(name).font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(2)
      Text(detail).font(.caption).foregroundStyle(BattleTheme.muted)
      Text(value?.formatted() ?? "—").font(.system(.largeTitle, design: .rounded, weight: .heavy))
        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
      Label(
        value == nil ? "Still hidden" : "points", systemImage: value == nil ? "lock" : "sparkle"
      )
      .font(.caption2).foregroundStyle(BattleTheme.muted)
    }.padding(18).frame(maxWidth: .infinity).background(
      color, in: RoundedRectangle(cornerRadius: 24))
  }
}
