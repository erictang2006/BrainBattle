import SwiftUI

struct VisualMemoryMenuView: View {
  @Environment(AppModel.self) private var app
  @State private var history: MemoryHistory?
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Image(systemName: "square.grid.3x3.fill").font(.system(size: 48))
          .foregroundStyle(BattleTheme.orange).accessibilityHidden(true)
        Text("A moment to remember.").font(.system(.largeTitle, design: .rounded, weight: .bold))
        Text(
          "Memorize the white tiles, then tap their positions. Clear the pattern to level up. Bigger grids and more tiles await."
        )
        .foregroundStyle(BattleTheme.muted)
        VStack(alignment: .leading, spacing: 12) {
          Label("Three hearts. Make them count.", systemImage: "heart.fill").font(.headline)
          Text(
            "Each set of 3 different wrong tiles costs 1 heart. Correct taps never count as mistakes. A lost heart restarts the same level with a new pattern; a cleared level resets mistakes."
          )
          .font(.subheadline)
          Text(
            "Solo has no time limit. Live 1v1 and parties share a 2-minute clock, with the same patterns for every level and retry. Everyone advances at their own pace."
          )
          .font(.subheadline)
        }.padding(22).background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
        Button("Solo · Start Playing") { startSolo() }.buttonStyle(BattleButtonStyle())
          .disabled(busy).accessibilityIdentifier("memorySolo")
        Button("Play Live · 1v1 or Party") { app.path.append(.memoryLiveMenu) }
          .buttonStyle(BattleButtonStyle(secondary: true)).accessibilityIdentifier("memoryLive")
        if busy { ProgressView("Preparing your grid…") }
        if let history {
          Label("Personal best · Level \(history.bestLevel)", systemImage: "trophy")
            .font(.system(.title3, design: .rounded, weight: .bold))
            .accessibilityIdentifier("memoryPersonalBest")
          if !history.games.isEmpty {
            Text("Recent Visual Memory games").font(.headline)
            ForEach(history.games) { game in
              Button {
                app.path.append(.liveRoom(game.code))
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(game.mode == "solo" ? "Solo" : game.mode == "party" ? "Party" : "Live 1v1")
                      .font(.headline)
                    Text("Level \(game.level) · \(game.score) points")
                      .font(.subheadline).foregroundStyle(BattleTheme.muted)
                    Text(Date(timeIntervalSince1970: game.updatedAt / 1000), style: .date)
                      .font(.caption).foregroundStyle(BattleTheme.muted)
                  }
                  Spacer()
                  Text(
                    game.completed
                      ? (game.mode == "solo" ? "Results" : "Rank \(game.rank)") : "Resume"
                  )
                  .font(.caption.bold())
                  Image(systemName: "chevron.right").font(.caption)
                }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
              }.buttonStyle(.plain)
            }
          }
        }
        if let error { ErrorNotice(message: error) }
      }.padding(22).frame(maxWidth: 560)
    }.frame(maxWidth: .infinity).background(BattleTheme.paper).navigationTitle("Visual Memory")
      .task {
        do {
          history = try await APIClient(baseURL: app.configuration.apiURL).memoryHistory()
        } catch { self.error = error.localizedDescription }
      }
  }
  private func startSolo() {
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do {
        let room = try await APIClient(baseURL: app.configuration.apiURL).createMemorySolo()
        app.path.append(.liveRoom(room.code))
      } catch { self.error = error.localizedDescription }
    }
  }
}

struct VisualMemoryBoardView: View {
  let player: MemoryPlayer
  let clock: ServerClock
  let endsAt: Double?
  let enabled: Bool
  let pending: (Int) -> Bool
  let select: (Int) -> Void
  let retry: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var confirmRetry = false

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.05, paused: !enabled)) { _ in
      let now = clock.milliseconds()
      let phase = player.phase(at: now)
      let inTime = endsAt.map { now < $0 } ?? true
      VStack(spacing: 18) {
        VStack(spacing: 7) {
          Text(title(phase, inTime: inTime)).font(.system(.title2, design: .rounded, weight: .bold))
            .accessibilityIdentifier("memoryPhase")
          Text(subtitle(phase)).font(.subheadline).foregroundStyle(BattleTheme.muted)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 64)
        grid(phase: phase, now: now, inTime: inTime)
        HStack(spacing: 8) {
          ForEach(0..<3) { index in
            Circle().fill(
              index < player.mistakes ? BattleTheme.orange : BattleTheme.muted.opacity(0.18)
            )
            .frame(width: 9, height: 9)
          }
          Text("\(player.mistakes) of 3 mistakes").font(.caption.bold())
        }.accessibilityElement(children: .combine).accessibilityIdentifier("memoryMistakes")
        if phase == "recall" && inTime {
          Text("\(player.correct.count) / \(player.targetCount) tiles found")
            .font(.subheadline.bold()).monospacedDigit()
          Button("Forgot the pattern? Retry for 1 heart") { confirmRetry = true }
            .font(.footnote).frame(minHeight: 44).disabled(!enabled)
            .accessibilityIdentifier("memoryRetry")
        }
        if !enabled {
          Label("Reconnecting… Your progress is saved.", systemImage: "wifi.exclamationmark")
            .font(.footnote).foregroundStyle(BattleTheme.muted)
        }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: phase)
      .animation(reduceMotion ? nil : .spring(duration: 0.3), value: player.lives)
      .sensoryFeedback(.selection, trigger: player.correct.count)
      .sensoryFeedback(.error, trigger: player.totalMistakes)
      .sensoryFeedback(.decrease, trigger: player.lives)
    }.confirmationDialog(
      "Use one heart to retry this level?", isPresented: $confirmRetry,
      titleVisibility: .visible
    ) {
      Button("Retry · Lose 1 heart", role: .destructive, action: retry)
    } message: {
      Text("You’ll get a new pattern at the same level. This also resets your mistake counter.")
    }
  }
  private func grid(phase: String, now: Double, inTime: Bool) -> some View {
    let spacing: CGFloat = player.gridSize >= 6 ? 5 : 8
    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: player.gridSize),
      spacing: spacing
    ) {
      ForEach(0..<(player.gridSize * player.gridSize), id: \.self) { tile in
        let correct = player.correct.contains(tile)
        let wrong = player.wrong.contains(tile)
        let highlighted =
          enabled && (phase == "display" || phase == "lifeLost")
          && (player.highlighted?.contains(tile) ?? false)
        Button {
          select(tile)
        } label: {
          RoundedRectangle(cornerRadius: player.gridSize >= 6 ? 6 : 9)
            .fill(
              wrong
                ? BattleTheme.pink
                : correct || highlighted
                  ? Color.white
                  : pending(tile) ? BattleTheme.blue : Color(red: 0.66, green: 0.57, blue: 0.78)
            )
            .overlay {
              if wrong {
                Image(systemName: "xmark").font(.system(.body, design: .rounded, weight: .bold))
                  .foregroundStyle(BattleTheme.ink)
              } else if correct {
                Image(systemName: "checkmark").font(.system(.body, design: .rounded, weight: .bold))
                  .foregroundStyle(BattleTheme.ink)
              } else if pending(tile) {
                ProgressView().controlSize(.mini)
              }
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(wrong ? 0.91 : correct ? 0.96 : 1)
        }.buttonStyle(MemoryTileStyle())
          .disabled(!enabled || !inTime || !player.canSelect(tile, at: now) || pending(tile))
          .accessibilityLabel(
            "Row \(tile / player.gridSize + 1), column \(tile % player.gridSize + 1)"
          )
          .accessibilityValue(
            wrong ? "Incorrect" : correct ? "Correct" : highlighted ? "Memorize" : "Unselected"
          )
          .accessibilityIdentifier("memoryTile.\(tile)")
      }
    }.padding(player.gridSize >= 6 ? 12 : 16)
      .background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: player.correct)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: player.wrong)
      .id(player.turnID)
  }
  private func title(_ phase: String, inTime: Bool) -> String {
    if !inTime && phase != "finished" { return "Time’s up!" }
    switch phase {
    case "prepare": return "Ready for a little focus?"
    case "display": return "Look closely."
    case "recall":
      return player.mistakes > 0 ? "Keep going. You’ve got this." : "Where were the white tiles?"
    case "cleared": return "Picture perfect!"
    case "lifeLost":
      return player.lifeLossReason == "retry"
        ? "New pattern. One heart spent." : "Three mistakes. One heart lost."
    default: return "A good brain workout."
    }
  }
  private func subtitle(_ phase: String) -> String {
    switch phase {
    case "prepare":
      return "\(player.targetCount) tiles · \(player.gridSize) × \(player.gridSize) grid"
    case "display": return "Remember their positions."
    case "recall": return "Tap each remembered tile once. Three mistakes cost a heart."
    case "cleared": return "Level cleared. Next pattern coming up…"
    case "lifeLost":
      return
        "Mistakes reset. \(player.lives) \(player.lives == 1 ? "heart" : "hearts") left. Retrying level \(player.level)…"
    default: return "Level \(player.level) · \(player.score) points"
    }
  }
}

/// Pinned outside the scrolling grid so lives and level stay visible on compact iPhones.
struct VisualMemoryStatusHeader: View {
  let player: MemoryPlayer
  let clock: ServerClock
  let endsAt: Double?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
      VStack(spacing: 8) {
        HStack {
          Text("Level \(player.level)").font(.system(.title, design: .rounded, weight: .bold))
            .accessibilityIdentifier("memoryLevel")
          Spacer(minLength: 8)
          HStack(spacing: 5) {
            ForEach(0..<3) { heart in
              Image(systemName: heart < player.lives ? "heart.fill" : "heart")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(
                  heart < player.lives ? BattleTheme.orange : BattleTheme.muted.opacity(0.5)
                )
                .scaleEffect(heart < player.lives ? 1 : 0.85)
            }
          }.accessibilityElement(children: .ignore).accessibilityLabel(
            "\(player.lives) lives remaining"
          )
          .accessibilityIdentifier("memoryLives")
        }
        HStack {
          Text("\(player.score) points").monospacedDigit()
          Spacer()
          if let endsAt {
            Label(
              "\(max(0, Int(ceil((endsAt - clock.milliseconds()) / 1000))))s", systemImage: "timer"
            )
            .monospacedDigit().accessibilityIdentifier("memoryTimer")
          } else {
            Text("Your pace. Your best.")
          }
        }.font(.caption.bold()).foregroundStyle(BattleTheme.muted)
      }.padding(.horizontal, 22).padding(.vertical, 10).frame(maxWidth: 560)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: player.lives)
    }.frame(maxWidth: .infinity).background(BattleTheme.paper)
  }
}

private struct MemoryTileStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

struct VisualMemoryRoomContent: View {
  @Environment(AppModel.self) private var app
  @Bindable var model: LiveRoomModel
  let room: LiveSnapshot
  let active: Bool
  @State private var bestLevel: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      if let p = model.memoryPlayer {
        if room.status == "completed" {
          finalResults(p)
        } else if p.phase == "finished" {
          VStack(alignment: .leading, spacing: 14) {
            Label("Your run is complete.", systemImage: "flag.checkered").font(.title2.bold())
            Text("Level \(p.level) · \(p.score) points · \(p.lives) hearts remaining").font(
              .headline)
            Text(
              p.finishReason == "eliminated"
                ? "All three hearts used. Three wrong tiles or a confirmed retry cost one heart. Your score is saved while the others finish."
                : "Your progress is saved. The final rankings will appear when everyone finishes."
            )
            .foregroundStyle(BattleTheme.muted)
            if let end = room.memory?.endsAt, let clock = model.clock {
              TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text("Up to \(max(0, Int(ceil((end - clock.milliseconds()) / 1000))))s remaining")
                  .font(.caption.bold()).monospacedDigit()
              }
            }
            Text("You can leave this screen and return to the saved game for results.").font(
              .footnote)
          }.padding(22).background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
          rankings
        } else if let clock = model.clock {
          VisualMemoryBoardView(
            player: p, clock: clock, endsAt: room.memory?.endsAt,
            enabled: model.connected && active, pending: model.memoryTilePending,
            select: { tile in Task { await model.memorySelection(tile: tile) } },
            retry: { Task { await model.memorySelection() } })
          if room.mode != "solo" { rankings }
        } else {
          ProgressView("Synchronizing your grid…")
        }
      }
    }.task(id: room.status) {
      if room.status == "completed" {
        bestLevel = try? await model.api.memoryHistory().bestLevel
      }
    }
  }
  private func finalResults(_ p: MemoryPlayer) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Image(systemName: room.mode == "solo" ? "heart.slash.fill" : "trophy.fill")
        .font(.system(size: 46)).foregroundStyle(BattleTheme.orange).accessibilityHidden(true)
      Text(resultTitle).font(.system(.largeTitle, design: .rounded, weight: .bold))
        .accessibilityIdentifier("memoryGameOver")
      Text(
        p.finishReason == "eliminated"
          ? "All three hearts used. Each set of three wrong tiles, or a confirmed retry, costs one heart."
          : p.finishReason == "time"
            ? "Two minutes of focus. Here’s how it went." : "Your run is saved."
      )
      .font(.subheadline).foregroundStyle(BattleTheme.muted)
      Text("Highest level reached · \(p.level)").font(.title2.bold())
      Text("\(p.score) points · \(p.lives) hearts remaining · \(p.totalMistakes) mistakes")
        .font(.subheadline).accessibilityIdentifier("memoryFinalScore")
      if let bestLevel {
        Label("Personal best · Level \(bestLevel)", systemImage: "star.fill").font(.headline)
      }
      if room.mode != "solo" { rankings }
      Button(room.mode == "solo" ? "Play Again" : "Rematch") { rematch() }
        .buttonStyle(BattleButtonStyle()).disabled(!model.connected || model.busy)
        .accessibilityIdentifier("memoryPlayAgain")
      Button("Back to Games") { app.path = [.visualMemory] }
        .buttonStyle(BattleButtonStyle(secondary: true))
      ShareLink(
        item:
          "Brain Battle · Visual Memory\nLevel \(p.level) · \(p.score) points\nCan you remember more?"
      ) {
        Label("Share Result", systemImage: "square.and.arrow.up")
      }
    }.padding(22).background(BattleTheme.peach, in: RoundedRectangle(cornerRadius: 26))
  }
  private var resultTitle: String {
    if room.mode == "solo" { return "Game over. Nicely remembered." }
    let winners = room.standings.filter { standing in
      standing.rank == 1
        && room.players.first(where: { $0.id == standing.playerId })?.forfeited != true
    }
    if winners.isEmpty { return "A battle well played." }
    if winners.count > 1 { return "A shared victory!" }
    let winner = winners[0].playerId
    if winner == model.playerID { return "You take the win!" }
    return "\(room.players.first { $0.id == winner }?.name ?? "Your rival") wins!"
  }
  private var rankings: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(room.status == "completed" ? "Final rankings" : "Live scores").font(.headline)
      ForEach(
        room.standings.sorted { $0.rank == $1.rank ? $0.playerId < $1.playerId : $0.rank < $1.rank }
      ) { s in
        HStack(spacing: 12) {
          Text("\(s.rank)").font(.title2.bold()).frame(width: 28)
          VStack(alignment: .leading, spacing: 4) {
            Text(room.players.first { $0.id == s.playerId }?.name ?? "Player").font(.headline)
            if let p = room.memory?.players.first(where: { $0.playerId == s.playerId }) {
              Text(
                "Level \(p.level) · \(p.lives) hearts\(p.finishReason == "left" ? " · Forfeited" : p.phase == "finished" ? " · Finished" : "")"
              )
              .font(.caption).foregroundStyle(BattleTheme.muted)
            }
          }
          Spacer(minLength: 4)
          Text("\(s.totalScore)").font(.headline).monospacedDigit()
        }
      }
    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22))
  }
  private func rematch() {
    Task {
      if await model.command(action: "rematch"), let code = model.room?.rematchCode {
        do {
          _ = try await model.api.joinLiveRoom(code: code)
          app.path = [.liveRoom(code)]
        } catch { model.error = error.localizedDescription }
      }
    }
  }
}
