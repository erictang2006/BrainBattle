import SwiftUI

@main struct BrainBattleApp: App {
  @State private var app = AppModel()
  var body: some Scene {
    WindowGroup { RootView().environment(app).tint(BattleTheme.ink).preferredColorScheme(.light) }
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var app
  @State private var showSettings = false
  var body: some View {
    @Bindable var app = app
    NavigationStack(path: $app.path) {
      Group {
        if app.loading {
          VStack(spacing: 20) {
            Image(systemName: "brain.head.profile").font(.system(size: 60)).foregroundStyle(
              BattleTheme.orange)
            ProgressView("Warming up your brain…")
          }.frame(maxWidth: .infinity, maxHeight: .infinity).background(BattleTheme.paper)
        } else if app.profile == nil {
          VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle)
            Text("Let’s get connected.").font(.system(.largeTitle, design: .rounded, weight: .bold))
            ErrorNotice(message: app.error ?? "The Brain Battle server could not be reached.")
            Button("Try again") {
              app.loading = true
              Task { await app.connect() }
            }.buttonStyle(BattleButtonStyle())
            #if DEBUG
              Button("Development server settings") { showSettings = true }
            #endif
          }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(
            BattleTheme.paper)
        } else if app.needsOnboarding {
          OnboardingView()
        } else {
          HomeView()
        }
      }
      .navigationDestination(for: AppRoute.self) { route in
        switch route {
        case .visualMemory: VisualMemoryMenuView()
        case .memoryLiveMenu: LiveMenuView(initialFormat: "visual-memory")
        case .liveMenu: LiveMenuView()
        case .liveRoom(let code): LiveRoomView(code: code, playerID: app.profile?.id ?? "", apiURL: app.configuration.apiURL).id(code)
        case .match(let id): MatchView(id: id, api: app.api).id(id)
        case .invitation(let token): InvitationView(token: token)
        }
      }
    }
    .foregroundStyle(BattleTheme.ink)
    .task { await app.connect() }
    .onOpenURL { app.openInvitation($0.absoluteString) }
    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) {
      if let url = $0.webpageURL { app.openInvitation(url.absoluteString) }
    }
    .sheet(isPresented: $showSettings) { SettingsView() }
  }
}
