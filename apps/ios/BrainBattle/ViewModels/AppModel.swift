import Foundation
import Observation

enum AppRoute: Hashable {
  case visualMemory
  case memoryLiveMenu
  case liveMenu
  case liveRoom(String)
  case match(String)
  case invitation(String)
}

@MainActor @Observable final class AppModel {
  private(set) var api: any BrainAPI
  private(set) var configuration: AppConfiguration
  var profile: PlayerProfile? {
    didSet { loadDismissedBattles() }
  }
  private let dismissalPreferences: UserDefaults
  private(set) var dismissedBattleIDs: Set<String> = []
  var recent: [RecentMatch] = []
  var homeHistory = HomeHistory.empty
  var homeRefreshing = false
  var homeHistoryIssue: String?
  var loading = true
  var busy = false
  var needsOnboarding = true
  var error: String?
  var pendingInvitation: String?
  var pendingLiveCode: String?
  var path: [AppRoute] = [] {
    didSet {
      if case .liveRoom(let code) = path.last {
        UserDefaults.standard.set(code, forKey: activeLiveKey)
      } else {
        UserDefaults.standard.removeObject(forKey: activeLiveKey)
      }
      if case .match(let id) = path.last {
        UserDefaults.standard.set(id, forKey: lastMatchKey)
      } else {
        UserDefaults.standard.removeObject(forKey: lastMatchKey)
      }
    }
  }
  private var activeLiveKey: String {
    "activeLive.\(configuration.apiURL.absoluteString).\(profile?.id ?? "")"
  }
  private var lastMatchKey: String { "lastMatch.\(configuration.apiURL.absoluteString)" }
  private var onboardingKey: String { "onboarded.\(configuration.apiURL.absoluteString)" }

  init(
    configuration: AppConfiguration = .current, api: (any BrainAPI)? = nil,
    dismissalPreferences: UserDefaults = .standard
  ) {
    self.configuration = configuration
    self.api = api ?? APIClient(baseURL: configuration.apiURL)
    self.dismissalPreferences = dismissalPreferences
  }
  var visibleOpenBattles: [HomeBattle] {
    (homeHistory.otherPlayable + homeHistory.waiting).filter { !dismissedBattleIDs.contains($0.id) }
  }
  var visiblePendingBattles: [HomeBattle] {
    homeHistory.pending.filter { !dismissedBattleIDs.contains($0.id) }
  }
  private var dismissalKey: String? {
    profile.map { "dismissedBattles.\(configuration.apiURL.absoluteString).\($0.id)" }
  }
  private func loadDismissedBattles() {
    dismissedBattleIDs = Set(
      dismissalKey.flatMap { dismissalPreferences.stringArray(forKey: $0) } ?? [])
  }
  func dismissBattle(id: String) {
    guard let key = dismissalKey,
      homeHistory.battles.contains(where: { $0.id == id && !$0.complete })
    else { return }
    dismissedBattleIDs.insert(id)
    dismissalPreferences.set(dismissedBattleIDs.sorted(), forKey: key)
  }
  func restoreBattle(id: String) {
    guard let key = dismissalKey else { return }
    dismissedBattleIDs.remove(id)
    dismissalPreferences.set(dismissedBattleIDs.sorted(), forKey: key)
  }
  func connect() async {
    guard loading else { return }
    do {
      profile = try await api.session()
      needsOnboarding = !UserDefaults.standard.bool(forKey: onboardingKey)
      recent = try await api.recentMatches()
      error = nil
      if !needsOnboarding {
        if let code = pendingLiveCode {
          acceptLiveInvitation(code)
        } else if let token = pendingInvitation {
          path = [.invitation(token)]
          pendingInvitation = nil
        } else if let code = UserDefaults.standard.string(forKey: activeLiveKey),
          LiveRoomCode.parse(code) != nil
        {
          path = [.liveRoom(code)]
        } else if let id = UserDefaults.standard.string(forKey: lastMatchKey),
          UUID(uuidString: id) != nil
        {
          path = [.match(id)]
        }
      }
    } catch { self.error = error.localizedDescription }
    loading = false
  }
  func onboard(name: String) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      profile = try await api.rename(name.trimmingCharacters(in: .whitespacesAndNewlines))
      UserDefaults.standard.set(true, forKey: onboardingKey)
      needsOnboarding = false
      error = nil
      if let code = pendingLiveCode {
        acceptLiveInvitation(code)
      } else if let token = pendingInvitation {
        path = [.invitation(token)]
        pendingInvitation = nil
      }
    } catch { self.error = error.localizedDescription }
  }
  func create(mode: MatchMode, roundCount: Int = 5) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let match = try await api.createMatch(mode: mode, roundCount: roundCount)
      error = nil
      path.append(.match(match.id))
    } catch { self.error = error.localizedDescription }
  }
  func refreshHome() async {
    guard !homeRefreshing else { return }
    homeRefreshing = true
    defer { homeRefreshing = false }
    let currentAPI = api
    let origin = configuration.apiURL
    do {
      let summaries = try await currentAPI.recentMatches()
      var details: [String: HomeBattle] = [:]
      // Keep session refresh/rotation ordered rather than racing eight bearer requests.
      for summary in summaries {
        guard !Task.isCancelled else { return }
        if let match = try? await currentAPI.match(id: summary.id) {
          details[match.id] = HomeBattle(match)
        }
      }
      guard origin == configuration.apiURL, !Task.isCancelled else { return }
      recent = summaries
      homeHistory = HomeHistory(battles: summaries.compactMap { details[$0.id] })
      homeHistoryIssue =
        details.count == summaries.count
        ? nil
        : "Some battles couldn’t be loaded. Pull down to try again."
      error = nil
    } catch {
      guard origin == configuration.apiURL, !Task.isCancelled else { return }
      homeHistoryIssue = "Your battles couldn’t be refreshed. Pull down to try again."
      self.error = error.localizedDescription
    }
  }
  func rematch(id: String) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let match = try await api.rematch(id: id)
      error = nil
      path.append(.match(match.id))
    } catch { self.error = error.localizedDescription }
  }
  private func acceptLiveInvitation(_ code: String) {
    Task {
      do {
        let client = APIClient(baseURL: configuration.apiURL)
        let room = try await client.joinLiveRoom(code: code)
        pendingLiveCode = nil
        UserDefaults.standard.set(
          room.code, forKey: "liveRoom.\(configuration.apiURL.absoluteString).\(profile?.id ?? "")")
        path = [.liveRoom(room.code)]
      } catch { self.error = error.localizedDescription }
    }
  }
  func openInvitation(_ input: String) {
    if let code = LiveRoomCode.parse(input) {
      pendingLiveCode = code
      if profile != nil && !needsOnboarding { acceptLiveInvitation(code) }
      return
    }
    guard let token = InvitationLink.token(from: input, webOrigin: configuration.webURL) else {
      error = "Paste the 48-character challenge code, or a Brain Battle invitation."
      return
    }
    if profile == nil || needsOnboarding {
      pendingInvitation = token
    } else {
      path.append(.invitation(token))
    }
  }
  #if DEBUG
    func configure(apiOrigin: String, webOrigin: String) async -> Bool {
      guard let apiURL = AppConfiguration.validOrigin(apiOrigin),
        let webURL = AppConfiguration.validOrigin(webOrigin)
      else {
        error = "Enter complete server origins, for example http://192.168.1.20:4000."
        return false
      }
      path = []
      profile = nil
      recent = []
      homeHistory = .empty
      homeHistoryIssue = nil
      pendingInvitation = nil
      UserDefaults.standard.set(apiOrigin, forKey: "debug.apiOrigin")
      UserDefaults.standard.set(webOrigin, forKey: "debug.webOrigin")
      configuration = AppConfiguration(apiURL: apiURL, webURL: webURL)
      api = APIClient(baseURL: apiURL)
      loading = true
      await connect()
      return error == nil
    }
  #endif
}
