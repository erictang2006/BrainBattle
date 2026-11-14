import SwiftUI

struct LiveMenuView: View {
  @Environment(AppModel.self) private var app
  @State private var mode = "duel"
  @State private var capacity = 8
  @State private var roundCount = 5
  @State private var format: String
  @State private var code = ""
  @State private var busy = false
  @State private var error: String?
  init(initialFormat: String = "counting-boxes") {
    _format = State(initialValue: initialFormat)
  }
  private var savedRoomKey: String {
    "liveRoom.\(app.configuration.apiURL.absoluteString).\(app.profile?.id ?? "")"
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Better together.").font(.system(.largeTitle, design: .rounded, weight: .bold))
        Picker("Mode", selection: $mode) {
          Text("1v1 Battle").tag("duel")
          Text("Party Mode").tag("party")
        }.pickerStyle(.segmented)
        if mode == "party" { Stepper("Player limit: \(capacity)", value: $capacity, in: 3...8) }
        Picker("Game", selection: $format) {
          Text("Counting Boxes").tag("counting-boxes")
          Text("Visual Memory").tag("visual-memory")
        }.pickerStyle(.segmented).accessibilityIdentifier("liveGameSelection")
        if format == "visual-memory" {
          Text("Visual Memory · 2-minute battle").font(.headline)
          Text(
            "Same patterns. Three hearts each. Clear levels at your own pace. Highest score wins; equal scores share a rank."
          )
          .font(.subheadline).foregroundStyle(BattleTheme.muted)
        } else {
          Text("\(roundCount) rounds · Counting Boxes").font(.headline)
          Picker("Rounds", selection: $roundCount) {
            Text("5 rounds").tag(5)
            Text("10 rounds").tag(10)
          }.pickerStyle(.segmented).accessibilityIdentifier("liveRoundCount")
          if roundCount == 10 {
            Text("3 Easy · 4 Medium · 3 Hard").font(.caption).foregroundStyle(BattleTheme.muted)
          }
          Text(
            mode == "party"
              ? "3–8 friends. Placement points. One winner."
              : "Two rivals. Most round wins takes the match."
          )
          .font(.subheadline).foregroundStyle(BattleTheme.muted)
          Text("Count the same cubes, on the same clock. Everyone readies up in the lobby.")
            .foregroundStyle(BattleTheme.muted)
        }
        Button(mode == "party" ? "Create Party Room" : "Create 1v1 Room") { launch(create: true) }
          .buttonStyle(BattleButtonStyle()).disabled(busy).accessibilityIdentifier("createLiveRoom")
        VStack(alignment: .leading, spacing: 14) {
          Text("Got a room code?").font(.headline)
          TextField("ABC234 or shared room code", text: $code, axis: .vertical)
            .lineLimit(1...3).textInputAutocapitalization(
              .characters
            )
            .autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier(
              "liveCode")
          Button("Join Room") { launch(create: false) }.buttonStyle(
            BattleButtonStyle(secondary: true)
          )
          .disabled(busy || LiveRoomCode.parse(code) == nil).accessibilityIdentifier("joinLiveRoom")
        }.padding(22).background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
        if let saved = UserDefaults.standard.string(forKey: savedRoomKey) {
          Button("Return to room \(saved)") { app.path.append(.liveRoom(saved)) }
            .buttonStyle(BattleButtonStyle(secondary: true))
        }
        if busy { ProgressView("Opening your room…") }
        if let error { ErrorNotice(message: error) }
      }.padding(24).frame(maxWidth: 560)
    }.frame(maxWidth: .infinity).background(BattleTheme.paper).navigationTitle("Play Live")
  }
  private func launch(create: Bool) {
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do {
        let api = APIClient(baseURL: app.configuration.apiURL)
        _ = try await api.session()
        let state: LiveSnapshot
        if create {
          state = try await api.createLiveRoom(
            roundCount: format == "visual-memory" ? 1 : roundCount, mode: mode,
            capacity: mode == "party" ? capacity : 2, format: format)
        } else {
          state = try await api.joinLiveRoom(code: code)
        }
        UserDefaults.standard.set(state.code, forKey: savedRoomKey)
        app.path.append(.liveRoom(state.code))
      } catch { self.error = error.localizedDescription }
    }
  }
}

struct LiveRoomView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.scenePhase) private var scenePhase
  @State private var model: LiveRoomModel
  @State private var confirmLeave = false
  @State private var completedReveals: Set<Int> = []
  @State private var showFinalResults = false
  init(code: String, playerID: String, apiURL: URL) {
    _model = State(initialValue: LiveRoomModel(code: code, playerID: playerID, apiURL: apiURL))
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if model.room?.mode != "solo" {
          HStack {
            Label(
              model.connection,
              systemImage: model.connected ? "circle.fill" : "arrow.triangle.2.circlepath"
            )
            .font(.caption).foregroundStyle(model.connected ? .green : BattleTheme.muted)
            Spacer()
            ShareLink(item: LiveRoomCode.shareText(model.code)) {
              Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Share room code")
          }
        }
        if let room = model.room {
          if room.status == "lobby" {
            lobby(room)
          } else if room.isVisualMemory, room.memory != nil {
            VisualMemoryRoomContent(model: model, room: room, active: scenePhase == .active)
          } else if let round = room.round {
            if room.status == "completed", round.reveal == nil || showFinalResults {
              results(room, round: round)
            } else if round.results != nil {
              VStack(alignment: .leading, spacing: 16) {
                Text("Round \(round.number) complete").font(
                  .system(.title, design: .rounded, weight: .bold))
                if let reveal = round.reveal {
                  let revealNow = model.clock?.milliseconds() ?? room.serverNow
                  CubeAnswerRevealView(
                    reveal: AnswerReveal(
                      puzzle: reveal.puzzle, correctAnswer: reveal.correctAnswer,
                      submittedAnswer: round.results?.first { $0.playerId == model.playerID }?
                        .submittedAnswer),
                    animationDurationLimit: min(
                      3,
                      max(
                        0,
                        ((room.nextAt ?? (revealNow + 3100)) - revealNow) / 1000 - 0.1)),
                    missingAnswerText: "No submitted answer is available for this round."
                  ) { completedReveals.insert(round.number) }
                  .id(round.number)
                }
                if round.reveal == nil || completedReveals.contains(round.number) {
                  if let mine = round.results?.first(where: { $0.playerId == model.playerID }) {
                    Text(
                      mine.correct
                        ? "Spot on!" : mine.timedOut ? "Time’s up." : "A tricky little stack."
                    )
                    .font(.title2.bold())
                    Text("+\(mine.score) points").font(.headline)
                  }
                  ForEach(round.results ?? []) { result in
                    HStack {
                      Text(room.players.first { $0.id == result.playerId }?.name ?? "Player")
                      Spacer()
                      Text("\(result.score)").bold()
                      if room.mode == "party" {
                        Text("+\(result.points ?? 0) pts").font(.caption.bold())
                      }
                      if round.winners?.contains(result.playerId) == true {
                        Image(systemName: "crown.fill")
                      }
                    }
                  }
                  if room.status != "completed" {
                    Text("Next round shortly…").foregroundStyle(BattleTheme.muted)
                  } else {
                    Button("View results") { showFinalResults = true }
                      .buttonStyle(BattleButtonStyle()).accessibilityIdentifier("liveViewResults")
                  }
                }
              }.padding(22).background(BattleTheme.mint, in: RoundedRectangle(cornerRadius: 24))
              standings(room)
            } else {
              game(room, round: round)
            }
          } else {
            Text("This room has closed.").font(.title2)
          }
          if room.mode != "solo" { participants(room) }
        } else {
          ProgressView("Restoring your room…").frame(maxWidth: .infinity, minHeight: 200)
        }
        if let error = model.error { ErrorNotice(message: error) }
        if let uncertainty = model.uncertainty, uncertainty > 250 {
          Text("Your connection has high latency. Viewing times stay synchronized with the server.")
            .font(.caption).foregroundStyle(BattleTheme.muted)
        }
        Button(model.room?.mode == "solo" ? "End Solo Game" : "Leave Room", role: .destructive) {
          confirmLeave = true
        }
        .frame(minHeight: 44).disabled(!model.connected || model.busy)
        .accessibilityIdentifier("leaveLiveRoom")
      }.padding(22).frame(maxWidth: 560)
    }.frame(maxWidth: .infinity).background(BattleTheme.paper)
      .safeAreaInset(edge: .top, spacing: 0) {
        if let room = model.room, room.isVisualMemory, room.status == "running",
          let p = model.memoryPlayer, p.phase != "finished", let clock = model.clock
        {
          VisualMemoryStatusHeader(player: p, clock: clock, endsAt: room.memory?.endsAt)
        }
      }
      .navigationTitle(model.room?.mode == "solo" ? "Visual Memory" : "Room \(model.code)")
      .navigationBarTitleDisplayMode(.inline)
      .task(id: scenePhase) { if scenePhase == .active { await model.run() } else { model.stop() } }
      .onDisappear { model.stop() }
      .confirmationDialog("Leave this room?", isPresented: $confirmLeave, titleVisibility: .visible)
    {
      Button("Leave Room", role: .destructive) {
        Task {
          if await model.command(action: "leave") {
            UserDefaults.standard.removeObject(
              forKey: "liveRoom.\(app.configuration.apiURL.absoluteString).\(model.playerID)")
            app.path = []
          }
        }
      }
    } message: {
      Text(
        model.room?.isVisualMemory == true
          ? "Leaving ends your game and saves your progress. Live games keep the original two-minute deadline during interruptions. Return from a disconnection to resume; a missed pattern can be retried for one heart."
          : "Leaving during a round forfeits your attempt. Going offline does not restart the round. Untimed rounds wait for players to return or leave. Offline lobby members release their slot after 30 seconds."
      )
    }
  }
  private func lobby(_ room: LiveSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(room.mode == "party" ? "Bring your best." : "Your rival awaits.").font(
        .system(.largeTitle, design: .rounded, weight: .bold))
      Text(room.code).font(.system(size: 36, weight: .bold, design: .monospaced)).tracking(5)
        .accessibilityIdentifier("liveRoomCode")
      Text(
        room.isVisualMemory
          ? "Visual Memory · 2 minutes · 3 hearts"
          : "Counting Boxes · \(room.roundCount) rounds · Rules v\(room.rulesVersion)"
      ).font(
        .subheadline)
      Text(
        "\(room.players.count)/\(room.capacity) players · \(room.mode == "party" ? "At least three players" : "Two players") required. Everyone ready, then the host starts."
      )
      .foregroundStyle(BattleTheme.muted)
      if room.isVisualMemory {
        Text(
          "Memorize the white tiles, then tap them. Every 3 wrong tiles cost a heart and retry the level. Clear a level to advance. Everyone gets the same pattern at each level and retry, on their own pace."
        )
        .font(.subheadline)
        Text(
          "Scoring: 1,000 per cleared level, 10 per tile in an unfinished level, −1 per mistake. A retry resets partial tile points. Scores are confirmed by the server."
        )
        .font(.caption).foregroundStyle(BattleTheme.muted)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(room.lineup) { game in
            VStack(spacing: 5) {
              Image(systemName: "cube")
              Text("Round \(game.number)").bold()
              Text(game.rules.difficulty.capitalized)
            }.font(.caption).padding(12).background(
              .white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
          }
        }
      }
      let ready = room.players.first { $0.id == model.playerID }?.ready ?? false
      Button(ready ? "Not Ready" : "Ready") {
        Task { _ = await model.command(action: "ready", ready: !ready) }
      }
      .buttonStyle(BattleButtonStyle()).disabled(!model.connected || model.busy)
      .accessibilityIdentifier("liveReady")
      if room.hostId == model.playerID {
        Button("Start Battle") { Task { _ = await model.command(action: "start") } }
          .buttonStyle(BattleButtonStyle(secondary: true))
          .disabled(
            !model.connected || model.busy || (room.players.count < (room.mode == "party" ? 3 : 2))
              || room.players.contains { !$0.ready || !$0.connected }
          )
          .accessibilityIdentifier("liveStart")
      }
    }.padding(22).background(BattleTheme.blue, in: RoundedRectangle(cornerRadius: 26))
  }
  @ViewBuilder private func game(_ room: LiveSnapshot, round: LiveRound) -> some View {
    if let clock = model.clock {
      LiveGameView(
        round: round, clock: clock, playerID: model.playerID, count: $model.count,
        enabled: model.connected && !model.busy
      ) { Task { _ = await model.command(action: "submit") } }
    } else {
      ProgressView("Synchronizing clocks…")
    }
  }
  private func results(_ room: LiveSnapshot, round: LiveRound) -> some View {
    let winners = room.standings.filter { $0.rank == 1 }.map(\.playerId)
    return VStack(alignment: .leading, spacing: 18) {
      Image(systemName: "trophy.fill").font(.system(size: 46)).foregroundStyle(BattleTheme.orange)
      Text(
        winners.isEmpty
          ? "A battle well played."
          : winners.count > 1
            ? "A shared victory."
            : winners.contains(model.playerID) ? "You take the win!" : "A worthy rival."
      )
      .font(.system(.largeTitle, design: .rounded, weight: .bold))
      Text("\(room.roundCount)-round \(room.mode == "party" ? "party" : "1v1") · Final results")
        .foregroundStyle(BattleTheme.muted)
      standings(room)
      Button("Rematch") {
        Task {
          if await model.command(action: "rematch"), let code = model.room?.rematchCode {
            do {
              _ = try await model.api.joinLiveRoom(code: code)
              UserDefaults.standard.set(
                code,
                forKey: "liveRoom.\(app.configuration.apiURL.absoluteString).\(model.playerID)")
              app.path = [.liveRoom(code)]
            } catch { model.error = error.localizedDescription }
          }
        }
      }.buttonStyle(BattleButtonStyle()).disabled(!model.connected || model.busy)
      ShareLink(
        item: "Brain Battle · Counting Boxes\n"
          + room.standings.map { standing in
            "\(room.players.first { $0.id == standing.playerId }?.name ?? "Player"): \(standing.roundWins) round wins · \(standing.totalScore) score"
          }.joined(separator: "\n")
      ) { Label("Share Results", systemImage: "square.and.arrow.up") }
      Button("Back to Home") { app.path = [] }.buttonStyle(BattleButtonStyle())
    }.padding(24).background(BattleTheme.peach, in: RoundedRectangle(cornerRadius: 26))
  }
  private func standings(_ room: LiveSnapshot) -> some View {
    VStack(spacing: 14) {
      ForEach(
        room.standings.sorted { $0.rank == $1.rank ? $0.playerId < $1.playerId : $0.rank < $1.rank }
      ) { standing in
        HStack {
          Text("\(standing.rank)").font(.title2.bold()).frame(width: 30)
            .foregroundStyle(standing.rank == 1 ? BattleTheme.orange : BattleTheme.ink)
          VStack(alignment: .leading) {
            Text(room.players.first { $0.id == standing.playerId }?.name ?? "Player").font(
              .headline)
            if room.players.first(where: { $0.id == standing.playerId })?.forfeited == true {
              Text("Forfeited").font(.caption)
            }
            Text("\(standing.totalScore) total score").font(.caption).foregroundStyle(
              BattleTheme.muted)
          }
          Spacer()
          Text(room.mode == "party" ? "\(standing.points) pts" : "\(standing.roundWins) wins")
            .bold()
        }
      }
    }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
  }
  private func playerStatus(_ player: LivePlayer, room: LiveSnapshot) -> String {
    if player.forfeited { return "Forfeited" }
    if room.status == "completed" { return "Finished" }
    if let p = room.memory?.players.first(where: { $0.playerId == player.id }) {
      if p.phase == "finished" { return "Finished · Level \(p.level) · \(p.score) points" }
      return "\(player.connected ? "Playing" : "Offline") · Level \(p.level) · \(p.lives) hearts"
    }
    if !player.connected { return "Offline · Rejoin anytime" }
    if room.status == "running" {
      return room.round?.submitted.contains(player.id) == true ? "Answer locked" : "In the round"
    }
    return player.ready ? "Ready" : "In the lobby"
  }
  private func participants(_ room: LiveSnapshot) -> some View {
    VStack(spacing: 16) {
      ForEach(room.players) { player in
        HStack(spacing: 12) {
          PlayerAvatar(name: player.name, color: BattleTheme.lavender, size: 44)
          VStack(alignment: .leading, spacing: 3) {
            Text(player.name + (player.id == model.playerID ? " · You" : "")).font(.headline)
            Text(playerStatus(player, room: room))
              .font(.caption).foregroundStyle(BattleTheme.muted)
          }
          Spacer()
          if player.id == room.hostId { Text("Host").font(.caption.bold()) }
        }
      }
    }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
  }
}

private struct LiveGameView: View {
  let round: LiveRound
  let clock: ServerClock
  let playerID: String
  @Binding var count: Int
  let enabled: Bool
  let submit: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.1)) { _ in
      let now = clock.milliseconds()
      let phase = round.phase(at: now)
      let submitted = round.submitted.contains(playerID)
      VStack(spacing: 16) {
        Text("Round \(round.number) · Counting Boxes").font(
          .system(.title, design: .rounded, weight: .bold))
        HStack {
          Text(
            phase == "prepare"
              ? "Get ready" : phase == "display" ? "Look closely" : "How many cubes?"
          ).font(.headline)
          Spacer()
          if phase == "prepare" || phase == "display" {
            let end = phase == "prepare" ? round.startsAt : round.displayUntil
            Text("\(max(0, Int(ceil((end - now) / 1000))))s")
              .monospacedDigit().font(.headline).accessibilityIdentifier("liveCountdown")
          }
        }
        ZStack {
          RoundedRectangle(cornerRadius: 26).fill(BattleTheme.lavender)
          if let puzzle = round.puzzle {
            CubeSceneView(puzzle: puzzle).opacity(phase == "display" ? 1 : 0)
              .accessibilityHidden(phase != "display")
          }
          if phase != "display" || round.puzzle == nil {
            VStack(spacing: 12) {
              Image(
                systemName: submitted
                  ? "checkmark.circle" : phase == "prepare" ? "cube" : "brain.head.profile"
              ).font(.largeTitle)
              Text(
                submitted
                  ? "Answer locked in"
                  : phase == "prepare" ? "Same cubes. Same clock." : "Picture the stack."
              ).font(.headline)
              if phase == "waiting" || submitted {
                Text("Waiting for the final result…").font(.subheadline)
              }
            }.padding()
          }
        }.frame(height: min(210, max(120, UIScreen.main.bounds.height * 0.22))).transition(.opacity)
        if phase == "answer" && !submitted {
          HStack(spacing: 20) {
            Button {
              count = max(0, count - 1)
            } label: {
              Image(systemName: "minus").frame(width: 60, height: 60)
            }
            Text("\(count)").font(.system(size: 46, weight: .bold, design: .rounded))
              .monospacedDigit().frame(minWidth: 90)
            Button {
              count = min(100, count + 1)
            } label: {
              Image(systemName: "plus").frame(width: 60, height: 60)
            }
          }.buttonStyle(.bordered).disabled(!enabled)
          Button("Done", action: submit).buttonStyle(BattleButtonStyle()).disabled(!enabled)
            .accessibilityIdentifier("liveSubmit")
          Button("Clear") { count = 0 }.frame(minHeight: 44).disabled(!enabled)
        }
      }.animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: phase)
        .sensoryFeedback(.selection, trigger: phase)
        .sensoryFeedback(.selection, trigger: count)
    }
  }
}
