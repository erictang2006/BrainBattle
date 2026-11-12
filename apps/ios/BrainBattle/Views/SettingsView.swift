import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var busy = false
  @State private var error: String?
  #if DEBUG
    @State private var apiOrigin = ""
    @State private var webOrigin = ""
  #endif
  var body: some View {
    NavigationStack {
      Form {
        Section("Your guest profile") {
          TextField("Player name", text: $name).textContentType(.nickname).autocorrectionDisabled()
          Button("Save name") {
            Task {
              busy = true
              defer { busy = false }
              do {
                app.profile = try await app.api.rename(name)
                dismiss()
              } catch { self.error = error.localizedDescription }
            }
          }.disabled(busy || name.count < 2 || name.count > 24)
          Text(
            "Your guest identity is kept securely on this iPhone. Registration and cross-device recovery are coming later."
          )
          .font(.footnote).foregroundStyle(BattleTheme.muted)
        }
        #if DEBUG
          Section("Development servers") {
            TextField("API origin", text: $apiOrigin).keyboardType(.URL)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Web / invitation origin", text: $webOrigin).keyboardType(.URL)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Connect to server") {
              Task {
                busy = true
                defer { busy = false }
                if await app.configure(apiOrigin: apiOrigin, webOrigin: webOrigin) {
                  dismiss()
                } else {
                  error = app.error
                }
              }
            }.disabled(busy)
            Text(
              "Simulator: localhost. iPhone: your Mac’s LAN address. Credentials are isolated for each API origin."
            )
            .font(.footnote)
          }
        #endif
        if let error { Section { ErrorNotice(message: error) } }
      }.navigationTitle("Your player")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
          name = app.profile?.name ?? ""
          #if DEBUG
            apiOrigin = app.configuration.apiURL.absoluteString
            webOrigin = app.configuration.webURL.absoluteString
          #endif
        }
    }
  }
}
