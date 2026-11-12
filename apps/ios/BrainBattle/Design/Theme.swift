import SwiftUI

enum BattleTheme {
  static let paper = Color(red: 250 / 255, green: 248 / 255, blue: 246 / 255)
  static let ink = Color(red: 40 / 255, green: 38 / 255, blue: 49 / 255)
  static let muted = Color(red: 129 / 255, green: 122 / 255, blue: 140 / 255)
  static let lavender = Color(red: 238 / 255, green: 230 / 255, blue: 246 / 255)
  static let peach = Color(red: 250 / 255, green: 223 / 255, blue: 200 / 255)
  static let blue = Color(red: 226 / 255, green: 239 / 255, blue: 255 / 255)
  static let mint = Color(red: 221 / 255, green: 243 / 255, blue: 228 / 255)
  static let pink = Color(red: 251 / 255, green: 224 / 255, blue: 225 / 255)
  static let orange = Color(red: 0.95, green: 0.53, blue: 0.30)
}

struct BattleButtonStyle: ButtonStyle {
  var secondary = false
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(.subheadline, design: .rounded, weight: .bold))
      .frame(maxWidth: .infinity).padding(.vertical, 17)
      .foregroundStyle(secondary ? BattleTheme.ink : .white)
      .background(
        secondary ? BattleTheme.lavender : BattleTheme.ink, in: RoundedRectangle(cornerRadius: 18)
      )
      .opacity(enabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

struct Eyebrow: View {
  let text: String
  var body: some View {
    Text(text.uppercased()).font(.system(.caption2, design: .rounded, weight: .bold))
      .tracking(1.6).foregroundStyle(BattleTheme.muted)
  }
}

struct ErrorNotice: View {
  let message: String
  var body: some View {
    Label(message, systemImage: "exclamationmark.circle")
      .font(.footnote).foregroundStyle(BattleTheme.ink)
      .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(BattleTheme.peach, in: RoundedRectangle(cornerRadius: 16))
      .accessibilityIdentifier("errorNotice")
  }
}

struct PlayerAvatar: View {
  let name: String
  var color: Color = BattleTheme.lavender
  var size: CGFloat = 40
  var body: some View {
    Text(String(name.prefix(1)).uppercased()).font(
      .system(.subheadline, design: .rounded, weight: .bold)
    )
    .lineLimit(1).minimumScaleFactor(0.6).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .frame(width: size, height: size).background(color, in: Circle())
    .accessibilityHidden(true)
  }
}
