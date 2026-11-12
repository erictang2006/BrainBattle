import SwiftUI

struct OnboardingView: View {
  @Environment(AppModel.self) private var app
  @State private var name = ""
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Label("brainbattle", systemImage: "brain.head.profile")
          .font(.system(.title2, design: .rounded, weight: .heavy))
          .foregroundStyle(BattleTheme.ink).padding(.top, 12)
        CubeSceneView(puzzle: .illustration, illustration: true, interactive: false)
          .frame(height: 240).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 12) {
          Eyebrow(text: "A little friendly brain power")
          Text("Great minds.\nFriendly rivals.")
            .font(.system(size: 44, weight: .heavy, design: .rounded)).tracking(-2)
          Text("Five tiny challenges. One good rivalry. Pick a name your friends will recognize.")
            .font(.subheadline).foregroundStyle(BattleTheme.muted).lineSpacing(4)
        }
        VStack(alignment: .leading, spacing: 9) {
          Eyebrow(text: "Your player name")
          TextField("Cube Captain", text: $name)
            .textContentType(.nickname).autocorrectionDisabled().submitLabel(.go)
            .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("onboardingName")
            .onSubmit { Task { await app.onboard(name: name) } }
          Text("2–24 characters · letters, numbers, spaces, _ or -")
            .font(.caption).foregroundStyle(BattleTheme.muted)
        }
        if let error = app.error { ErrorNotice(message: error) }
        Button {
          Task { await app.onboard(name: name) }
        } label: {
          HStack {
            Text(app.busy ? "Saving your name…" : "Let’s play")
            Image(systemName: "arrow.right")
          }
        }
        .buttonStyle(BattleButtonStyle()).disabled(
          app.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
            || name.count > 24
        )
        .accessibilityIdentifier("onboardingContinue")
        Label("No sign-up. Your guest profile stays on this iPhone.", systemImage: "lock.shield")
          .font(.caption).foregroundStyle(BattleTheme.muted).frame(maxWidth: .infinity)
      }.padding(24)
    }.background(BattleTheme.paper).scrollDismissesKeyboard(.interactively)
  }
}
