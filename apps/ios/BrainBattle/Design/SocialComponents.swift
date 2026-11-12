import SwiftUI

enum BrainBattleTab: String, CaseIterable {
  case home = "Home"
  case games = "Games"
  case friends = "Friends"
  case profile = "Profile"
  var symbol: String {
    switch self {
    case .home: "house.fill"
    case .games: "square.grid.2x2.fill"
    case .friends: "person.2.fill"
    case .profile: "person.crop.circle.fill"
    }
  }
}

struct BrainBattleTabBar: View {
  @Binding var selection: BrainBattleTab
  var body: some View {
    HStack(spacing: 0) {
      ForEach(BrainBattleTab.allCases, id: \.self) { tab in
        Button {
          selection = tab
        } label: {
          VStack(spacing: 5) {
            Image(systemName: tab.symbol).font(.system(size: 19, weight: .semibold)).frame(
              height: 23)
            Text(tab.rawValue).font(.system(.caption2, design: .rounded, weight: .semibold))
          }
          .foregroundStyle(selection == tab ? BattleTheme.ink : BattleTheme.muted)
          .frame(maxWidth: .infinity).padding(.vertical, 12)
          .background {
            if selection == tab {
              Capsule().fill(BattleTheme.lavender).frame(width: 52, height: 32).offset(y: -9)
            }
          }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("tab.\(tab.rawValue.lowercased())")
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
      }
    }
    .padding(.horizontal, 16).background(BattleTheme.paper)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .overlay(alignment: .top) { Rectangle().fill(BattleTheme.ink.opacity(0.07)).frame(height: 1) }
    .sensoryFeedback(.selection, trigger: selection)
  }
}

struct FeaturedRivalryCard: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let playerName: String
  let rivalry: FeaturedRivalry?
  let busy: Bool
  let challenge: () -> Void
  let rematch: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 6) {
        Image(systemName: "sparkles")
        Text(rivalry == nil ? "A LITTLE FRIENDLY COMPETITION" : "RECENT RIVALRY").tracking(1.3)
      }
      .font(.system(.caption2, design: .rounded, weight: .bold)).foregroundStyle(BattleTheme.muted)
      if let rivalry {
        let rivalsLayout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 8))
        rivalsLayout {
          rival(name: playerName, wins: rivalry.wins, color: BattleTheme.peach)
          RivalryCubeIllustration().frame(width: 80, height: 80).accessibilityHidden(true)
          rival(name: rivalry.opponent.name, wins: rivalry.losses, color: BattleTheme.blue)
        }
        Text(rivalry.message).font(.system(.title3, design: .rounded, weight: .bold))
          .fixedSize(horizontal: false, vertical: true)
        Text(
          "Recent head-to-head · \(rivalry.draws) \(rivalry.draws == 1 ? "draw" : "draws")"
        )
        .font(.caption).foregroundStyle(BattleTheme.muted)
        Button(action: rematch) {
          Label(busy ? "Creating…" : "Rematch", systemImage: "arrow.counterclockwise")
        }.buttonStyle(BattleButtonStyle()).disabled(busy).accessibilityIdentifier("rivalryRematch")
      } else {
        let introLayout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
          : AnyLayout(HStackLayout(spacing: 12))
        introLayout {
          VStack(alignment: .leading, spacing: 10) {
            Text("Every rivalry\nstarts somewhere.")
              .font(.system(.title2, design: .rounded, weight: .bold)).tracking(-0.6)
              .fixedSize(horizontal: false, vertical: true)
            Text("Challenge a friend and start your first brain battle!")
              .font(.subheadline).foregroundStyle(BattleTheme.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
          RivalryCubeIllustration().frame(width: 80, height: 96).accessibilityHidden(true)
        }
        Button(action: challenge) { Text(busy ? "Creating…" : "Challenge a Friend") }
          .buttonStyle(BattleButtonStyle()).disabled(busy).accessibilityIdentifier(
            "featuredChallenge")
      }
    }
    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
    .background(BattleTheme.lavender, in: RoundedRectangle(cornerRadius: 24))
    .accessibilityElement(children: .contain).accessibilityIdentifier("featuredRivalry")
  }
  private func rival(name: String, wins: Int, color: Color) -> some View {
    VStack(spacing: 7) {
      PlayerAvatar(name: name, color: color, size: 48)
        .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 3) }
      Text(name).font(.system(.subheadline, design: .rounded, weight: .bold))
        .lineLimit(2).multilineTextAlignment(.center)
      Text("\(wins) \(wins == 1 ? "win" : "wins")").font(.caption).foregroundStyle(
        BattleTheme.muted)
    }.frame(maxWidth: .infinity)
  }
}

struct PendingChallengeCard: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let battle: HomeBattle
  let play: () -> Void
  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
      : AnyLayout(HStackLayout(spacing: 12))
    layout {
      HStack(spacing: 12) {
        PlayerAvatar(name: battle.opponent?.name ?? "You", color: BattleTheme.blue)
        VStack(alignment: .leading, spacing: 4) {
          Text(battle.opponent?.name ?? "Your challenge")
            .font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(2)
          Text("Counting Boxes · \(battle.roundCount) rounds").font(.caption).foregroundStyle(
            BattleTheme.muted)
        }
      }
      if !typeSize.isAccessibilitySize { Spacer(minLength: 2) }
      Button(action: play) {
        Text("Play").font(.system(.subheadline, design: .rounded, weight: .bold))
          .padding(.horizontal, 20).frame(minHeight: 44).background(
            BattleTheme.peach, in: Capsule())
      }.buttonStyle(.plain)
        .accessibilityLabel("Play challenge with \(battle.opponent?.name ?? "your friend")")
        .accessibilityIdentifier("pending.\(battle.id)")
    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
  }
}

struct BattleActionCard: View {
  let title: String
  let subtitle: String
  let icon: String
  let color: Color
  var comingSoon = false
  var busy = false
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: icon).font(.system(size: 23, weight: .medium))
          Spacer(minLength: 0)
          if !comingSoon { Image(systemName: "arrow.up.right").font(.caption.bold()) }
        }.frame(minHeight: 28)
        VStack(alignment: .leading, spacing: 7) {
          Text(title).font(.system(.headline, design: .rounded, weight: .bold))
            .fixedSize(horizontal: false, vertical: true)
          Text(subtitle).font(.caption).foregroundStyle(BattleTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        if comingSoon {
          Text("Coming Soon").font(.system(.caption2, design: .rounded, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.6), in: Capsule())
        }
      }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color, in: RoundedRectangle(cornerRadius: 22))
    }.buttonStyle(.plain).disabled(busy)
  }
}

struct RecentBattleRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let battle: HomeBattle
  let open: () -> Void
  private var badgeColor: Color {
    switch battle.outcome {
    case .victory: BattleTheme.mint
    case .defeat: BattleTheme.pink
    default: BattleTheme.lavender
    }
  }
  var body: some View {
    Button(action: open) {
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        : AnyLayout(HStackLayout(spacing: 12))
      layout {
        HStack(spacing: 12) {
          PlayerAvatar(name: battle.opponent?.name ?? "You", color: BattleTheme.blue)
          VStack(alignment: .leading, spacing: 4) {
            Text(battle.mode == .solo ? "Solo practice" : battle.opponent?.name ?? "Your friend")
              .font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(2)
            Text("Counting Boxes · \(battle.roundCount) rounds").font(.caption).foregroundStyle(
              BattleTheme.muted)
          }
        }
        if !typeSize.isAccessibilitySize { Spacer(minLength: 2) }
        HStack(spacing: 8) {
          Text(battle.outcome?.title ?? "Completed")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 7).background(badgeColor, in: Capsule())
          Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(
            BattleTheme.muted)
        }
      }.padding(.vertical, 14).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("recentBattle.\(battle.id)")
  }
}

/// Decorative artwork only, independent of the scored Counting Boxes renderer.
struct RivalryCubeIllustration: View {
  var body: some View {
    Canvas { context, size in
      let unit = min(size.width / 4.5, size.height / 5.5)
      func point(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        CGPoint(
          x: size.width / 2 + (x - z) * unit,
          y: size.height * 0.66 + (x + z) * unit * 0.5 - y * unit * 1.15)
      }
      func face(_ vertices: [CGPoint], _ color: Color) {
        let path = Path { path in
          path.addLines(vertices)
          path.closeSubpath()
        }
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(BattleTheme.paper.opacity(0.55)), lineWidth: 0.8)
      }
      for y in 0..<2 {
        for x in 0..<2 {
          for z in 0..<2 where y == 0 || (x == 0 && z == 0) {
            let x = CGFloat(x)
            let y = CGFloat(y)
            let z = CGFloat(z)
            face(
              [
                point(x, y, z + 1), point(x + 1, y, z + 1),
                point(x + 1, y + 1, z + 1), point(x, y + 1, z + 1),
              ],
              Color(red: 0.89, green: 0.48, blue: 0.24))
            face(
              [
                point(x + 1, y, z), point(x + 1, y, z + 1),
                point(x + 1, y + 1, z + 1), point(x + 1, y + 1, z),
              ],
              Color(red: 0.96, green: 0.60, blue: 0.34))
            face(
              [
                point(x, y + 1, z), point(x + 1, y + 1, z),
                point(x + 1, y + 1, z + 1), point(x, y + 1, z + 1),
              ],
              Color(red: 1, green: 0.73, blue: 0.49))
          }
        }
      }
    }
  }
}
