import SwiftUI

struct InvitationEntryView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var link = ""
  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 22) {
        Eyebrow(text: "A friendly rivalry awaits")
        Text("Your invitation to\na little competition.").font(
          .system(.largeTitle, design: .rounded, weight: .heavy))
        Text(
          "Paste the challenge link your friend sent. You’ll see who invited you before accepting."
        )
        .foregroundStyle(BattleTheme.muted)
        TextField("https://…/invite/…", text: $link, axis: .vertical)
          .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
          .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 16))
          .accessibilityIdentifier("invitationLink")
        if let error = app.error { ErrorNotice(message: error) }
        Button {
          app.error = nil
          app.openInvitation(link)
          if app.error == nil { dismiss() }
        } label: {
          Label("Preview challenge", systemImage: "arrow.right")
        }
        .buttonStyle(BattleButtonStyle()).disabled(link.isEmpty)
        .accessibilityIdentifier("previewInvitation")
        Spacer()
      }.padding(24).background(BattleTheme.paper)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }.presentationDetents([.large])
  }
}

struct InvitationView: View {
  @Environment(AppModel.self) private var app
  let token: String
  @State private var invitation: Invitation?
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        CubeSceneView(puzzle: .illustration, illustration: true, interactive: false)
          .frame(height: 230).accessibilityHidden(true)
        Eyebrow(text: "A friendly challenge has arrived")
        Text(
          invitation.map { "\($0.hostName) thinks you’re up for it." } ?? "A little brain battle?"
        )
        .font(.system(size: 36, weight: .heavy, design: .rounded)).tracking(-1.5)
        Text("Five rounds. The same puzzles. Your own clock. Think you can take the top spot?")
          .foregroundStyle(BattleTheme.muted).lineSpacing(4)
        Label("1 vs. 1 · Counting Boxes", systemImage: "cube").font(.subheadline.weight(.semibold))
        if let error { ErrorNotice(message: error) }
        if let invitation {
          if invitation.expired && !invitation.claimed {
            ErrorNotice(message: "This challenge has expired. Ask your friend for a rematch.")
          } else {
            Button {
              Task { await claim() }
            } label: {
              Label(
                busy ? "Opening…" : invitation.claimed ? "Open challenge" : "Challenge accepted",
                systemImage: "arrow.right")
            }.buttonStyle(BattleButtonStyle()).disabled(busy).accessibilityIdentifier(
              "acceptInvitation")
            Text(
              invitation.claimed
                ? "Only the two existing players can reopen this challenge."
                : "One link. One challenger. One good rivalry."
            )
            .font(.caption).foregroundStyle(BattleTheme.muted)
          }
        } else {
          Button("Load invitation") { Task { await load() } }.buttonStyle(BattleButtonStyle())
            .disabled(busy)
        }
      }.padding(24)
    }.background(BattleTheme.paper).navigationTitle("Challenge").navigationBarTitleDisplayMode(
      .inline
    )
    .task { await load() }
  }
  private func load() async {
    busy = true
    defer { busy = false }
    do {
      invitation = try await app.api.invitation(token: token)
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  private func claim() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let match = try await app.api.claim(token: token)
      app.path = [.match(match.id)]
    } catch { self.error = error.localizedDescription }
  }
}
