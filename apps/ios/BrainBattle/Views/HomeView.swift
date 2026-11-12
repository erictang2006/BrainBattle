import SwiftUI

struct HomeView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var tab: BrainBattleTab = .home
  @State private var showInvite = false
  @State private var showSettings = false
  @State private var lastDismissedBattleID: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header
        switch tab {
        case .home: socialHome
        case .games: games
        case .friends: friends
        case .profile: profile
        }
        if let error = app.error {
          ErrorNotice(message: error)
          Button("Try again") { Task { await app.refreshHome() } }
            .buttonStyle(BattleButtonStyle(secondary: true))
        }
      }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
    }
    .background(BattleTheme.paper).toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) { BrainBattleTabBar(selection: $tab) }
    .refreshable { await app.refreshHome() }.task { await app.refreshHome() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await app.refreshHome() } }
    }
    .sheet(isPresented: $showInvite) { InvitationEntryView() }
    .sheet(isPresented: $showSettings) { SettingsView() }

  }

  private var header: some View {
    HStack {
      HStack(spacing: 8) {
        Image(systemName: "brain.head.profile").font(.system(size: 23, weight: .medium))
          .foregroundStyle(BattleTheme.orange)
        Text("brainbattle").font(.system(.title2, design: .rounded, weight: .heavy)).tracking(-0.8)
      }.accessibilityElement(children: .combine)
      Spacer(minLength: 8)
      Button {
        showSettings = true
      } label: {
        PlayerAvatar(name: app.profile?.name ?? "You", color: BattleTheme.blue, size: 44)
      }.buttonStyle(.plain).accessibilityLabel("Player and settings").accessibilityIdentifier(
        "openProfile")
    }
  }

  private var socialHome: some View {
    Group {
      VStack(alignment: .leading, spacing: 8) {
        Text("Your next rival awaits.")
          .font(.system(.title, design: .rounded, weight: .bold)).tracking(-1)
          .fixedSize(horizontal: false, vertical: true)
        Text("A little competition makes it more fun.").font(.subheadline).foregroundStyle(
          BattleTheme.muted)
      }
      if app.homeRefreshing && app.homeHistory.battles.isEmpty {
        ProgressView("Finding your rivalries…").font(.subheadline)
          .frame(maxWidth: .infinity, minHeight: 180)
          .background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
      } else if app.homeHistory.battles.isEmpty, let issue = app.homeHistoryIssue {
        VStack(alignment: .leading, spacing: 16) {
          Label("Your rivalries will be right back.", systemImage: "arrow.clockwise")
            .font(.system(.headline, design: .rounded, weight: .bold))
          Text(issue).font(.subheadline).foregroundStyle(BattleTheme.muted)
          Button("Refresh battles") { Task { await app.refreshHome() } }
            .buttonStyle(BattleButtonStyle())
        }.padding(22).background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
      } else {
        FeaturedRivalryCard(
          playerName: app.profile?.name ?? "You", rivalry: app.homeHistory.rivalry,
          busy: app.busy, challenge: createChallenge,
          rematch: {
            if let rivalry = app.homeHistory.rivalry {
              Task { await app.rematch(id: rivalry.lastMatchID) }
            }
          })
      }
      yourTurn
      mainActions
      joinLink
      recentBattles
      continuePlaying
      if let issue = app.homeHistoryIssue {
        Label(issue, systemImage: "arrow.clockwise").font(.caption).foregroundStyle(
          BattleTheme.muted)
      }
    }
  }

  private var yourTurn: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        sectionTitle("Your Turn")
        Text("\(app.visiblePendingBattles.count)").font(
          .system(.caption, design: .rounded, weight: .bold)
        )
        .padding(.horizontal, 9).padding(.vertical, 4).background(BattleTheme.peach, in: Capsule())
        Spacer()
        if app.homeRefreshing { ProgressView().controlSize(.small) }
      }
      if app.visiblePendingBattles.isEmpty {
        HStack(spacing: 12) {
          Image(systemName: "checkmark.circle").font(.title3).foregroundStyle(BattleTheme.muted)
          VStack(alignment: .leading, spacing: 4) {
            Text("No turns waiting in your recent battles.")
              .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Text("Set the score. Send the first challenge.").font(.caption).foregroundStyle(
              BattleTheme.muted)
          }
          Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
          .background(.white, in: RoundedRectangle(cornerRadius: 20))
      } else {
        ForEach(app.visiblePendingBattles) { battle in
          PendingChallengeCard(battle: battle) { open(battle.id) }
        }
        Text("From your recent challenges.").font(.caption).foregroundStyle(BattleTheme.muted)
      }
    }.accessibilityIdentifier("yourTurn")
  }

  @ViewBuilder private var mainActions: some View {
    if typeSize.isAccessibilitySize {
      VStack(spacing: 12) {
        challengeAction
        liveAction
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        challengeAction
        liveAction
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }
  private var challengeAction: some View {
    BattleActionCard(
      title: "Challenge a Friend", subtitle: "Set the score. Send a link.", icon: "link",
      color: BattleTheme.peach, busy: app.busy, action: createChallenge
    )
    .accessibilityIdentifier("createChallenge")
  }
  private var liveAction: some View {
    BattleActionCard(
      title: "Play Live", subtitle: "Real-time head-to-head.", icon: "person.2",
      color: BattleTheme.blue, action: { app.path.append(.liveMenu) }
    )
    .accessibilityIdentifier("playLive")
  }
  private var joinLink: some View {
    Button {
      showInvite = true
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "envelope.open")
        Text("Have a challenge link?")
        Image(systemName: "arrow.up.right").font(.caption)
      }.font(.system(.subheadline, design: .rounded, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
    }.buttonStyle(.plain).accessibilityIdentifier("openInvitation")
  }

  private var recentBattles: some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Recent Battles")
      Text("Completed games from your latest eight battles.").font(.caption).foregroundStyle(
        BattleTheme.muted)
      if app.homeHistory.completed.isEmpty {
        Text("Your first finish is just the beginning.").font(.subheadline).foregroundStyle(
          BattleTheme.muted
        )
        .padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(spacing: 0) {
          ForEach(app.homeHistory.completed) { battle in
            RecentBattleRow(battle: battle) { open(battle.id) }
            if battle.id != app.homeHistory.completed.last?.id {
              Divider().overlay(BattleTheme.ink.opacity(0.04))
            }
          }
        }
      }
    }
  }

  @ViewBuilder private var continuePlaying: some View {
    let battles = app.visibleOpenBattles
    if !battles.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        sectionTitle("Your Open Battles")
        ForEach(battles) { battle in
          HStack(spacing: 4) {
            Button {
              open(battle.id)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: battle.mode == .solo ? "cube" : "link").font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                  Text(
                    battle.mode == .solo
                      ? "Solo practice" : battle.opponent?.name ?? "Challenge a friend"
                  )
                  .font(.system(.subheadline, design: .rounded, weight: .bold))
                  Text(
                    battle.yoursComplete
                      ? "Your score is set · View and share" : "Pick up where you left off"
                  )
                  .font(.caption).foregroundStyle(BattleTheme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption)
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("openBattle.\(battle.id)")
            Button {
              app.dismissBattle(id: battle.id)
              lastDismissedBattleID = battle.id
            } label: {
              Image(systemName: "xmark.circle").font(.title3)
                .foregroundStyle(BattleTheme.muted).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel("Dismiss battle")
              .accessibilityIdentifier("dismissBattle.\(battle.id)")
          }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
        }
        Text("Dismiss hides a battle on this iPhone. It doesn’t cancel it.")
          .font(.caption).foregroundStyle(BattleTheme.muted)
      }
    }
    if let id = lastDismissedBattleID, app.dismissedBattleIDs.contains(id) {
      HStack {
        Label("Battle dismissed", systemImage: "checkmark.circle")
          .font(.subheadline).foregroundStyle(BattleTheme.muted)
        Spacer()
        Button("Undo") {
          app.restoreBattle(id: id)
          lastDismissedBattleID = nil
        }.font(.subheadline.bold()).frame(minHeight: 44)
          .accessibilityIdentifier("undoDismissBattle")
      }.padding(16).background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 20))
    }
  }

  private var games: some View {
    VStack(alignment: .leading, spacing: 22) {
      pageHeading(
        "Little games. Big energy.", subtitle: "A fresh challenge for your favourite brain.")
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          VStack(alignment: .leading, spacing: 8) {
            Text("Counting Boxes").font(.system(.title2, design: .rounded, weight: .bold))
            Text("Look closely. Think in 3D.").font(.subheadline).foregroundStyle(BattleTheme.muted)
          }
          Spacer(minLength: 0)
          RivalryCubeIllustration().frame(width: 70, height: 80).accessibilityHidden(true)
        }
        Button {
          Task { await app.create(mode: .solo) }
        } label: {
          Label("Solo practice", systemImage: "cube")
        }.buttonStyle(BattleButtonStyle()).disabled(app.busy).accessibilityIdentifier(
          "soloPractice")
        Button(action: createChallenge) { Text("Challenge a Friend") }
          .buttonStyle(BattleButtonStyle(secondary: true)).disabled(app.busy)
      }.padding(22).background(BattleTheme.peach, in: RoundedRectangle(cornerRadius: 24))
      ForEach([("Reaction Time", "bolt"), ("Sequence Memory", "square.grid.3x3")], id: \.0) {
        game in
        HStack(spacing: 14) {
          Image(systemName: game.1).frame(width: 32).font(.title2)
          Text(game.0).font(.system(.headline, design: .rounded, weight: .bold))
          Spacer(minLength: 0)
          Text("Coming Soon").font(.caption).foregroundStyle(BattleTheme.muted)
        }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
      }
    }
  }

  private var friends: some View {
    VStack(alignment: .leading, spacing: 22) {
      pageHeading(
        "Better with a rival.", subtitle: "A little friendly competition goes a long way.")
      VStack(alignment: .leading, spacing: 16) {
        Image(systemName: "person.2").font(.system(size: 36)).padding(.bottom, 4)
        Text("Good friends. Great rivals.").font(.system(.title2, design: .rounded, weight: .bold))
        Text("Friend lists are on the way. For now, send a challenge link to someone you know.")
          .font(.subheadline).foregroundStyle(BattleTheme.muted)
        Button(action: createChallenge) { Text("Challenge a Friend") }
          .buttonStyle(BattleButtonStyle()).disabled(app.busy)
      }.padding(24).background(BattleTheme.blue, in: RoundedRectangle(cornerRadius: 24))
      joinLink
      yourTurn
    }
  }

  private var profile: some View {
    VStack(alignment: .leading, spacing: 22) {
      pageHeading("Your corner.", subtitle: "A familiar face. A fresh challenge.")
      VStack(spacing: 16) {
        PlayerAvatar(name: app.profile?.name ?? "You", color: BattleTheme.blue, size: 76)
        Text(app.profile?.name ?? "You").font(.system(.title2, design: .rounded, weight: .bold))
        Text("Guest player").font(.subheadline).foregroundStyle(BattleTheme.muted)
        Button {
          showSettings = true
        } label: {
          Label("Edit profile & settings", systemImage: "slider.horizontal.3")
        }.buttonStyle(BattleButtonStyle()).accessibilityIdentifier("editProfile")
        Text(
          "Your guest identity is stored securely on this iPhone. Account linking is coming later."
        )
        .font(.footnote).foregroundStyle(BattleTheme.muted).multilineTextAlignment(.center)
      }.padding(24).frame(maxWidth: .infinity).background(
        .white, in: RoundedRectangle(cornerRadius: 24))
    }
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.system(.title3, design: .rounded, weight: .bold)).tracking(-0.3)
      .accessibilityAddTraits(.isHeader)
  }
  private func pageHeading(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1)
      Text(subtitle).font(.subheadline).foregroundStyle(BattleTheme.muted)
    }
  }
  private func createChallenge() { Task { await app.create(mode: .challenge) } }
  private func open(_ id: String) { app.path.append(.match(id)) }
}
