import SwiftUI

struct MatchView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var model: MatchViewModel
  @State private var phaseNow: Double = 0
  @State private var typeAnswer = false
  @State private var completedReveals: Set<Int> = []
  init(id: String, api: any BrainAPI) {
    _model = State(initialValue: MatchViewModel(id: id, api: api))
  }
  private var now: Double {
    // phaseNow triggers boundary redraws; the monotonic server clock is the one
    // source of presentation time, even after a correcting refresh.
    let boundaryTick = phaseNow
    return model.clock?.milliseconds() ?? boundaryTick
  }
  private var phase: RoundState? { model.currentRound?.phase(at: now) }
  private var timed: Bool {
    model.match?.yoursComplete != true && (phase == .display || phase == .answer)
  }

  var body: some View {
    GeometryReader { viewport in
      ScrollViewReader { scroll in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Color.clear.frame(height: 0).id("stageTop")
            if let match = model.match {
              if model.showsFinalResults {
                ResultsView(match: match, busy: model.busy) {
                  Task { if let next = await model.rematch() { app.path = [.match(next.id)] } }
                }
              } else if let round = model.currentRound, let clock = model.clock {
                HStack(alignment: .center, spacing: 12) {
                  VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Round \(round.number) of \(match.rounds.count)")
                    Text("Counting Boxes").font(.system(.title2, design: .rounded, weight: .heavy))
                      .tracking(-0.6).fixedSize(horizontal: false, vertical: true)
                  }
                  Spacer(minLength: 0)
                  if phase == .display { RoundCountdown(round: round, clock: clock) }
                }
                RoundProgressStrip(rounds: match.rounds, current: round.number)
                if round.state == .done {
                  roundResult(round)
                } else {
                  roundContent(
                    round, match: match,
                    stageHeight: max(
                      120,
                      min(255, viewport.size.height * (viewport.size.height < 620 ? 0.25 : 0.36))))
                }
              }
              if let error = model.error, !timed {
                ErrorNotice(message: error)
                Button("Reconnect and refresh") { Task { await model.refresh() } }
                  .buttonStyle(BattleButtonStyle(secondary: true))
              }
              if !timed {
                if !match.yoursComplete { matchup(match) }
                if let code = match.invitationToken {
                  shareCard(code: code, finished: match.yoursComplete)
                }
                Label(
                  "One fair shot per round. Your clock stays with you.", systemImage: "lock.shield"
                )
                .font(.caption).foregroundStyle(BattleTheme.muted)
              }
            } else {
              ProgressView("Finding your battle…").frame(maxWidth: .infinity).padding(.vertical, 80)
              if let error = model.error {
                ErrorNotice(message: error)
                Button("Try again") { Task { await model.refresh() } }.buttonStyle(
                  BattleButtonStyle())
              }
            }
          }.padding(.horizontal, 20).padding(.bottom, 24)
        }
        .onChange(of: phase) { old, new in
          // No animated outgoing puzzle: geometry is removed exactly at the boundary.
          if old != .display || new != .answer { scroll.scrollTo("stageTop", anchor: .top) }
        }
        .onChange(of: model.match?.yoursComplete) { _, complete in
          if complete == true { scroll.scrollTo("stageTop", anchor: .top) }
        }
      }
    }
    .background(BattleTheme.paper).navigationTitle("Your battle").navigationBarTitleDisplayMode(
      .inline
    )
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if timed, model.match?.yoursComplete != true,
        let round = model.currentRound, round.inputAvailable(at: now) || model.error != nil
      {
        VStack(spacing: 8) {
          if let error = model.error {
            ErrorNotice(message: error).accessibilityIdentifier("submissionError")
            Button("Refresh round") { Task { await model.refresh() } }
              .font(.caption.bold()).frame(minHeight: 36).disabled(model.busy)
          }
          if round.inputAvailable(at: now) { submitButton }
        }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
          .background(BattleTheme.paper)
      }
    }
    .task(id: scenePhase) {
      model.restoreDraft(
        scope: "\(app.configuration.apiURL.absoluteString).\(app.profile?.id ?? "guest")")
      if scenePhase == .active { await model.poll() }
    }
    .task(id: boundaryKey) { await trackBoundaries() }
    .refreshable { await model.refresh() }
    .sensoryFeedback(.selection, trigger: model.answer)
    .sensoryFeedback(trigger: phase) { old, new in
      scenePhase == .active && old == .display && new == .answer ? .impact(weight: .medium) : nil
    }
    .sensoryFeedback(trigger: model.currentRound?.attempt) { old, new in
      guard scenePhase == .active, old == nil, let new else { return nil }
      return new.correct ? .success : .warning
    }
    .toolbar {
      if let text = model.match?.challengeShareText, !timed {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            .accessibilityLabel("Share challenge")
        }
      }
    }
  }

  @ViewBuilder private func roundContent(
    _ round: GameRound, match: BattleMatch, stageHeight: CGFloat
  ) -> some View {
    let phase = round.phase(at: now)
    VStack(alignment: .leading, spacing: 16) {
      Text(
        phase == .ready
          ? "Make every cube count."
          : phase == .display ? "Look closely. Think in 3D." : "How many cubes?"
      )
      .font(.system(.headline, design: .rounded, weight: .bold))
      .contentTransition(.opacity)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: phase)
      if phase == .display {
        if scenePhase == .active, let puzzle = round.puzzle {
          CubeSceneView(puzzle: puzzle).id(round.number).frame(height: stageHeight)
            .transition(.identity)
        } else {
          hiddenStage(title: "Your clock keeps running.", icon: "eye.slash", height: stageHeight)
        }
      } else if phase == .answer {
        hiddenStage(
          title: !round.inputAvailable(at: now)
            ? "Time’s up. Setting your score…" : "Keep counting. Trust your eye.",
          icon: "eye.slash", height: stageHeight)
      } else {
        VStack(spacing: 14) {
          Image(systemName: "cube.transparent.fill").font(.system(size: 52, weight: .light))
            .foregroundStyle(Color(red: 0.57, green: 0.46, blue: 0.77))
          Text("A little focus. A good eye.").font(
            .system(.title3, design: .rounded, weight: .bold))
          Text("Count the stack, then enter your total.").font(.subheadline).foregroundStyle(
            BattleTheme.muted)
        }.padding(22).frame(maxWidth: .infinity, minHeight: min(220, stageHeight))
          .background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 26))
        HStack(spacing: 12) {
          ruleChip(
            String(format: "%gs to look", (round.rules?.displayMs ?? 8000) / 1000), icon: "eye")
          ruleChip(
            round.rules?.answerTimeLimit == false ? "No answer time limit" : "Enter your count",
            icon: "number"
          )
        }
        Button {
          Task { await model.start() }
        } label: {
          Label(
            now >= match.expiresAt
              ? "Challenge expired" : model.busy ? "Getting ready…" : "Start round \(round.number)",
            systemImage: "arrow.right")
        }.buttonStyle(BattleButtonStyle()).disabled(
          model.busy || now >= match.expiresAt || scenePhase != .active
        )
        .accessibilityIdentifier("startRound")
        Text("Correct counts earn 1,000 points, plus up to 500 for speed.")
          .font(.caption).foregroundStyle(BattleTheme.muted)
      }
      if phase == .display || phase == .answer, round.inputAvailable(at: now) {
        countControls
          .disabled(
            model.busy || model.submissionUncertain || phase != .answer || scenePhase != .active
          )
          .opacity(phase == .answer ? 1 : 0.45)
      }
    }
  }

  private var submitButton: some View {
    Button {
      Task { await model.submit() }
    } label: {
      HStack {
        Text(model.busy ? "Sending…" : model.submissionUncertain ? "Retry submission" : "Done")
        Spacer()
        if model.busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.right") }
      }.padding(.horizontal, 18)
    }.buttonStyle(BattleButtonStyle())
      .disabled(model.busy || phase != .answer || scenePhase != .active)
      .accessibilityIdentifier("submitAnswer")
  }

  private var countControls: some View {
    VStack(spacing: 10) {
      HStack {
        Text("Your count").font(.subheadline).foregroundStyle(BattleTheme.muted)
        Spacer()
        Text(model.answer).font(.system(size: 36, weight: .heavy, design: .rounded))
          .monospacedDigit().accessibilityLabel("Cube count: \(model.answer)")
          .accessibilityIdentifier("answerCount")
      }.padding(.horizontal, 16).padding(.vertical, 8)
        .background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 18))
      Picker("Answer method", selection: $typeAnswer) {
        Text("Quick Count").tag(false)
        Text("Type Answer").tag(true)
      }.pickerStyle(.segmented).accessibilityIdentifier("answerMethod")
      if typeAnswer {
        keypad
      } else {
        HStack(spacing: 10) {
          Button {
            model.decrement()
          } label: {
            Text("−1").font(.headline).frame(minWidth: 52, minHeight: 56)
          }.buttonStyle(NumberKeyStyle()).accessibilityLabel("Subtract one")
            .accessibilityIdentifier("decrementCount").disabled((Int(model.answer) ?? 0) == 0)
          Button {
            model.increment()
          } label: {
            Text("+1").font(.system(.title, design: .rounded, weight: .bold))
              .frame(maxWidth: .infinity, minHeight: 60)
              .background(BattleTheme.peach, in: RoundedRectangle(cornerRadius: 18))
          }.buttonStyle(.plain).accessibilityLabel("Add one").accessibilityIdentifier(
            "incrementCount")
          Button {
            model.clearAnswer()
          } label: {
            Text("Clear").font(.subheadline.bold()).frame(minWidth: 60, minHeight: 56)
          }.buttonStyle(NumberKeyStyle()).accessibilityIdentifier("clearCount")
        }
      }
    }
  }

  private var keypad: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
      ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "clear", "0", "delete"], id: \.self) {
        key in
        Button {
          if key == "delete" {
            model.deleteDigit()
          } else if key == "clear" {
            model.clearAnswer()
          } else {
            model.digit(key)
          }
        } label: {
          Group {
            if key == "delete" {
              Image(systemName: "delete.left")
            } else if key == "clear" {
              Text("Clear").font(.system(.subheadline, design: .rounded, weight: .semibold))
            } else {
              Text(key)
            }
          }.font(.system(.title2, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity).frame(minHeight: typeSize.isAccessibilitySize ? 62 : 48)
        }.buttonStyle(NumberKeyStyle())
          .accessibilityLabel(key == "delete" ? "Delete digit" : key.capitalized)
          .accessibilityIdentifier("digit.\(key)")
      }
    }
  }

  private var boundaryKey: [Double] {
    [
      model.clock?.serverMilliseconds ?? 0, model.currentRound?.displayUntil ?? 0,
      model.currentRound?.deadline ?? 0, model.currentRound?.feedbackUntil ?? 0,
      scenePhase == .active ? 1 : 0,
    ]
  }
  private func trackBoundaries() async {
    guard let clock = model.clock, let round = model.currentRound else { return }
    phaseNow = clock.milliseconds()
    guard scenePhase == .active else { return }
    for boundary in [round.displayUntil, round.deadline, round.feedbackUntil].compactMap({ $0 })
      .sorted()
    {
      guard boundary > phaseNow else { continue }
      do {
        try await Task.sleep(for: .seconds(max(0, boundary - clock.milliseconds()) / 1000))
      } catch { return }
      guard !Task.isCancelled else { return }
      phaseNow = max(boundary, clock.milliseconds())
      if boundary == round.deadline { await model.refresh() }
    }
  }
  private func hiddenStage(title: String, icon: String, height: CGFloat) -> some View {
    VStack(spacing: 16) {
      Image(systemName: icon).font(.system(size: 38)).foregroundStyle(BattleTheme.muted)
      Text(title).font(.system(.headline, design: .rounded, weight: .semibold))
        .multilineTextAlignment(.center)
    }.padding(20).frame(maxWidth: .infinity, minHeight: height)
      .background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 26))
  }
  private func ruleChip(_ text: String, icon: String) -> some View {
    Label(text, systemImage: icon).font(.system(.caption, design: .rounded, weight: .semibold))
      .frame(maxWidth: .infinity).padding(.vertical, 12)
      .background(.white, in: RoundedRectangle(cornerRadius: 14))
  }
  private func roundResult(_ round: GameRound) -> some View {
    let correct = round.attempt?.correct == true
    return VStack(spacing: 18) {
      if let reveal = round.reveal {
        CubeAnswerRevealView(reveal: reveal) { completedReveals.insert(round.number) }
          .id(round.number)
      }
      if round.reveal == nil || completedReveals.contains(round.number) {
        Image(
          systemName: correct
            ? "checkmark" : round.attempt?.timedOut == true ? "timer" : "arrow.uturn.forward"
        )
        .font(.system(size: 32, weight: .semibold)).frame(width: 80, height: 80)
        .background(
          correct ? BattleTheme.mint : BattleTheme.peach, in: RoundedRectangle(cornerRadius: 26))
        Text(
          correct
            ? "Spot on!"
            : round.attempt?.timedOut == true ? "The clock got this one." : "A tricky little stack."
        )
        .font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
        Text(
          correct
            ? "A good eye. A well-earned score." : "Reset your focus. The next round is yours."
        )
        .font(.subheadline).foregroundStyle(BattleTheme.muted).multilineTextAlignment(.center)
        VStack(spacing: 4) {
          Text("+\(round.attempt?.score ?? 0)").font(
            .system(size: 48, weight: .heavy, design: .rounded)
          ).monospacedDigit()
          Eyebrow(text: "points this round")
        }.padding(20).frame(maxWidth: .infinity)
          .background(
            correct ? BattleTheme.mint.opacity(0.65) : BattleTheme.peach.opacity(0.65),
            in: RoundedRectangle(cornerRadius: 22))
        if let opponent = round.opponent {
          Text("Your friend: \(opponent.score) points").font(.footnote).foregroundStyle(
            BattleTheme.muted)
        } else if model.match?.mode == .challenge {
          Label("Your friend’s result is still under wraps.", systemImage: "lock")
            .font(.footnote).foregroundStyle(BattleTheme.muted)
        }
        Button {
          model.nextRound()
        } label: {
          Label(
            round.number == model.match?.rounds.count ? "View results" : "Next round",
            systemImage: "arrow.right")
        }
        .buttonStyle(BattleButtonStyle()).disabled(now < (round.feedbackUntil ?? 0))
        .accessibilityIdentifier("nextRound")
      }
    }.padding(.vertical, 14).frame(maxWidth: .infinity)
  }
  private func matchup(_ match: BattleMatch) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Eyebrow(text: "The matchup")
      playerRow(name: match.you.name, detail: "That’s you", score: match.total)
      if match.mode == .challenge {
        Divider()
        playerRow(
          name: match.opponent?.name ?? "Your friend",
          detail: match.complete
            ? "Final score"
            : match.opponent == nil ? "Waiting for a challenger" : "Challenge accepted",
          score: match.complete ? match.opponentTotal : nil)
      }
      Text(
        match.mode == .solo
          ? "Your next best is waiting." : "Opponent totals unlock after all rounds are final."
      )
      .font(.caption).foregroundStyle(BattleTheme.muted)
    }.padding(22).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
  }
  private func playerRow(name: String, detail: String, score: Int?) -> some View {
    HStack(spacing: 12) {
      PlayerAvatar(name: name)
      VStack(alignment: .leading, spacing: 5) {
        Text(name).font(.system(.subheadline, design: .rounded, weight: .bold))
        Text(detail).font(.caption).foregroundStyle(BattleTheme.muted)
      }
      Spacer()
      Text(score.map { $0.formatted() } ?? "—").font(
        .system(.title2, design: .rounded, weight: .bold))
    }
  }
  private func shareCard(code: String, finished: Bool) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Image(systemName: "link").font(.title2)
      Text(
        finished ? "Your score is set.\nSend the challenge." : "A little rivalry goes a long way."
      )
      .font(.system(.title2, design: .rounded, weight: .bold))
      Text(
        "Your friend gets the same five puzzles and their own clock. One challenger, 48 hours to play."
      )
      .font(.subheadline).foregroundStyle(BattleTheme.muted)
      Text(code).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
        .accessibilityLabel("Challenge code: \(code)").accessibilityIdentifier("challengeCode")
      ShareLink(
        item: InvitationLink.shareText(code), subject: Text("A little Brain Battle?"),
        message: Text("Five rounds of Counting Boxes. Think you can beat my score?")
      ) {
        Label("Share challenge", systemImage: "square.and.arrow.up")
      }.buttonStyle(BattleButtonStyle()).accessibilityIdentifier("shareChallenge")
    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      .background(BattleTheme.peach, in: RoundedRectangle(cornerRadius: 26))
  }
}
