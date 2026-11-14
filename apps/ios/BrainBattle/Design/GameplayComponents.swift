import SwiftUI

struct RoundProgressStrip: View {
  let rounds: [GameRound]
  let current: Int
  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible()), count: min(5, max(1, rounds.count))),
      spacing: 8
    ) {
      ForEach(rounds) { round in
        VStack(spacing: 7) {
          HStack(spacing: 4) {
            if round.state == .done {
              Image(systemName: round.attempt?.correct == true ? "checkmark" : "minus")
            } else {
              Text("\(round.number)").monospacedDigit()
            }
          }.font(.system(.caption, design: .rounded, weight: .bold))
            .frame(height: 23)
          Capsule().fill(color(round)).frame(height: 4)
        }.frame(maxWidth: .infinity)
          .foregroundStyle(round.number == current ? BattleTheme.ink : BattleTheme.muted)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "Round \(round.number), \(round.state == .done ? "complete" : round.number == current ? "current" : "up next")"
          )
      }
    }.accessibilityIdentifier("roundProgress")
  }
  private func color(_ round: GameRound) -> Color {
    if round.state == .done {
      return round.attempt?.correct == true ? BattleTheme.mint : BattleTheme.peach
    }
    return round.number == current ? BattleTheme.ink : BattleTheme.lavender
  }
}

/// Only this small view ticks. Cube geometry never lives inside TimelineView.
struct RoundCountdown: View {
  let round: GameRound
  let clock: ServerClock
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
      let now = clock.milliseconds()
      let remaining = round.remaining(at: now)
      let urgent = remaining <= 3
      HStack(spacing: 10) {
        ZStack {
          Circle().stroke(BattleTheme.ink.opacity(0.08), lineWidth: 3)
          Circle().trim(from: 0, to: round.timeProgress(at: now))
            .stroke(
              urgent ? BattleTheme.orange : BattleTheme.ink,
              style: StrokeStyle(lineWidth: 3, lineCap: .round)
            ).rotationEffect(.degrees(-90))
          Image(systemName: "timer").font(.caption.weight(.semibold))
        }.frame(width: 28, height: 28)
        Text("\(remaining)s").font(.system(.title3, design: .rounded, weight: .bold))
          .monospacedDigit()
      }.padding(.horizontal, 13).padding(.vertical, 10)
        .background(urgent ? BattleTheme.peach : .white, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remaining) seconds remaining")
        .accessibilityIdentifier("roundCountdown")
        .sensoryFeedback(trigger: remaining) { old, new in
          scenePhase == .active && new < old && (1...3).contains(new)
            ? .impact(weight: .light) : nil
        }
    }
  }
}

struct NumberKeyStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(BattleTheme.ink)
      .background(
        configuration.isPressed ? BattleTheme.lavender : .white,
        in: RoundedRectangle(cornerRadius: 16)
      )
      .overlay { RoundedRectangle(cornerRadius: 16).stroke(BattleTheme.ink.opacity(0.035)) }
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .opacity(enabled ? 1 : 0.4)
  }
}
