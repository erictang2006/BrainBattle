import Foundation

struct AppConfiguration {
  let apiURL: URL
  let webURL: URL
  static func validOrigin(_ value: String) -> URL? {
    guard let url = URL(string: value), let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.path.isEmpty || url.path == "/"
    else { return nil }
    #if DEBUG
      guard ["http", "https"].contains(url.scheme) else { return nil }
    #else
      guard url.scheme == "https" else { return nil }
    #endif
    return URL(string: value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
  }
  static var current: AppConfiguration {
    #if DEBUG
      let api = UserDefaults.standard.string(forKey: "debug.apiOrigin") ?? "http://localhost:4000"
      let web = UserDefaults.standard.string(forKey: "debug.webOrigin") ?? "http://localhost:3000"
    #else
      let api =
        Bundle.main.object(forInfoDictionaryKey: "BrainAPIOrigin") as? String
        ?? "https://api.invalid"
      let web =
        Bundle.main.object(forInfoDictionaryKey: "BrainWebOrigin") as? String
        ?? "https://web.invalid"
    #endif
    return AppConfiguration(
      apiURL: validOrigin(api) ?? URL(string: "https://api.invalid")!,
      webURL: validOrigin(web) ?? URL(string: "https://web.invalid")!)
  }
}
