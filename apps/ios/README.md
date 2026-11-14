# Brain Battle for iOS

Native SwiftUI + Core Animation 3D client for the existing Fastify application. Minimum deployment target: **iOS 18**. No WebView, JavaScript runtime, third-party iOS package, or duplicated game engine is required.

The native home now uses a Social Rivalry layout with recent head-to-head results, actual pending turns, and Home/Games/Friends/Profile navigation. See [SOCIAL_HOME.md](SOCIAL_HOME.md) for implementation details and the limits of the current recent-match API.

New matches use [Counting Boxes v2](COUNTING_BOXES_V2.md): sparse stationary 5×5 arrangements, 3–16 cubes, fast per-round timing, and shared Quick Count/Type Answer controls. Stored v1 matches retain their original timing and scores. The earlier [gameplay polish](GAMEPLAY_POLISH.md) remains documented as implementation history.

## Distribute to friends

Follow the [native-only TestFlight guide](../../TESTFLIGHT.md) and [readiness report](NATIVE_BETA_READINESS.md). Release connects directly to `https://brain-battle-api.onrender.com`; live room codes and async challenge codes work without a Next.js deployment. The web app remains optional and preserved.

## Reuse and architecture

The repository inspection found these components usable without rewriting them:

| Existing component        | Native integration                                                                                                      |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `packages/games`          | All versioned deterministic generation, validation, and scoring stay on the server                                      |
| `apps/api/src/service.ts` | Five-round orchestration, independent player clocks, atomic invitation claims, finalization, rematches                  |
| `packages/db`             | Existing async tables and PostgreSQL/PGlite connections, plus an additive live-room migration |
| `packages/shared`         | Swift Codable models mirror public DTOs; native requests use the same Zod-validated endpoints                           |
| Supabase Auth             | Existing anonymous sign-in, user verification, and refresh are reused by a native bearer transport                      |
| Socket.IO                 | Authenticated native live rooms and existing web notifications; async native matches use foreground HTTP polling                 |
| `apps/web`                | Preserved. Native and web players can challenge each other using the same links and rules                               |

Visual Memory is playable from Games in Solo, live 1v1, and Party Mode. It has three hearts, independent level progression, fair shared patterns, persistent results/personal bests, and native rematches. See [VISUAL_MEMORY.md](VISUAL_MEMORY.md) for rules, verification, Simulator instructions, and API deployment requirements.

Native source organization:

```text
BrainBattle/
  App/                 App entry, navigation, build/environment configuration
  Models/              Public Codable DTOs, safe invitation parser, monotonic server clock
  Networking/          URLSession actor, Keychain credentials, redirect rejection
  ViewModels/          Guest/onboarding/navigation and per-match presentation state
  Games/CountingBoxes/ Core Animation 3D rendering from public coordinates only
  Views/               Native home, onboarding, invitation, match, results, settings
  Design/              Colors and reusable native controls
  Resources/           Icons, launch colors, Info.plist, required-reason privacy manifest
```

`MatchViewModel` holds drafts, selected panels, and server projections. It never calculates a score or a winner. The display clock uses a server timestamp plus monotonic device uptime, and hides geometry at the stored deadline even before the next poll. Backgrounding hides the active puzzle and stops polling; foregrounding fetches current authoritative state. The last open match ID is retained so terminating and reopening the app retrieves the same attempt and original deadlines. Puzzles and credentials are never stored in preferences.

The cube surface uses native Core Animation `CATransformLayer` containers with six transformed faces per cube, depth ordering, a fixed orthographic camera transform, and stationary gameplay with a subtle v2 ground grid. Each view owns its layers independently; server refreshes reuse geometry. This avoids the RealityKit shadow/shader and drawable failures observed when running multiple iOS Simulators together. Public cube coordinates and server-owned deadlines remain unchanged.

## Run in Simulator

1. Start the existing application from the repository root:

   ```sh
   npm install
   npm run dev
   ```

   The API should listen on port 4000. A server started before these changes must reload the added `/api/native/session` endpoint.

2. Open `apps/ios/BrainBattle.xcodeproj` in Xcode. Select the **BrainBattle** shared scheme and an iPhone Simulator. Build and run.
3. Enter a guest name. Choose **Challenge a friend** or **Solo practice**. Both clients use server-provided versioned timing: v2 progresses through 3/6, 2.5/6, and 2/5-second observation/answer windows. Saved v1 matches remain at 8/12 seconds.
4. Share the challenge from the toolbar or results card using the native iOS share sheet. Native sharing sends the secure invitation token as a challenge code plus in-app instructions; it never opens the legacy website URL.
5. To accept another player's challenge before public universal links are configured, use **Have a challenge code?** on the home screen and paste the code or native message. `brainbattle://invite/<48-character-token>` links are also handled. A separate web private window provides a second guest for local testing.

Debug builds default to API `http://localhost:4000` and web `http://localhost:3000`. Development server settings are available from the profile sheet and the connection-error screen. Each API origin has its own Keychain credential and navigation preferences.

This workspace's local data store was recovered during implementation; see [RECOVERY-NOTE.md](RECOVERY-NOTE.md) for the preserved original, recovered row counts, and completeness limitation. Its `.env` selects the separate restored directory. `PGLITE_DIRECTORY` is optional for other checkouts. A directory lock now prevents two API/migration processes from opening the same persistent local store.

The checked-in Xcode project needs no generator installation. After adding or removing source/resource files, regenerate it with:

```sh
python3 apps/ios/scripts/generate-project.py
```

The script generates a conventional project and shared scheme with app, unit-test, and UI-test targets. Icon assets are already checked in; `swift apps/ios/scripts/generate-icon.swift` can regenerate the original native SF Symbols artwork on macOS.

## Run on an iPhone

1. Connect/unlock the iPhone, trust the Mac, and enable Developer Mode if Xcode requests it.
2. In the app target's **Signing & Capabilities**, select your Apple development team and choose an available bundle identifier. The checked-in identifier is a development default, not a registered App Store app.
3. On the Mac, set `HOST=0.0.0.0` in the existing root `.env` and restart Fastify. Allow local connections through the Mac firewall. Keep the phone and Mac on the same trusted Wi-Fi network.
4. In the Debug app's development settings, enter `http://<Mac-LAN-IP>:4000` as API origin. `localhost` on a physical iPhone refers to the phone.
5. Native room/challenge codes require only the API. If also testing the optional web app, set `WEB_ORIGIN` to its reachable origin, use that web origin in Debug settings for legacy links, and bind Next.js to `0.0.0.0` for other devices.
6. Allow the app's local-network permission when prompted. Build and run using the iPhone destination in Xcode.

The app uses `NSAllowsLocalNetworking` for development connections; it does not globally disable App Transport Security. Release configuration accepts only HTTPS origins and has no editable development-server screen. For remote testing or TestFlight, use the hosted HTTPS API. A web deployment is optional; native codes do not depend on it.

## Native authentication contract

Native authentication uses `POST /api/native/session`:

- Initial request: no authorization. Response body is the existing `{ id, name }` profile; the `X-Brain-Session` response header contains a signed native credential. It does not set a web cookie.
- Store that header in Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Subsequent API requests send `Authorization: Bearer <credential>`. The client treats the credential as opaque.
- The server verifies the signature, the native transport marker, and a 30-day expiry. Production still uses Supabase `getUser()` and the existing refresh flow. A refreshed credential is returned in `X-Brain-Session`, including on an error response after refresh, and persisted by the client.
- Repeating `/native/session` with an existing bearer restores the profile. Invalid or expired bearers return 401; they never silently create another guest. No browser cookies are consumed by the native onboarding endpoint.
- Web clients keep their existing signed HttpOnly cookies. Native credentials are not accepted as web cookies, and web cookie values are not accepted as native bearer credentials.
- Credentials are isolated per configured API origin. URLSession uses an ephemeral, cookie-free, uncached configuration and refuses redirects. Tokens are never logged, included in share URLs, or saved in UserDefaults.

All match, profile, round, invitation and rematch endpoints are otherwise unchanged. No private seed or explicit answer key is added to a native response. Rendering coordinates are necessarily inspectable by a determined client, as with the existing friendly-competition web game.

## Tests and builds

Run backend compatibility tests from the root:

```sh
npm test
npm run typecheck
```

Native tests require an available iPhone Simulator. Replace the destination with an installed device name or UUID:

```sh
xcodebuild -project apps/ios/BrainBattle.xcodeproj -scheme BrainBattle \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath apps/ios/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

**Keep Simulator signing enabled.** Simulator-only local entitlements are supplied for Keychain tests and app sessions; disabling all signing produces Keychain error `-34018`. These entitlements are conditional on the Simulator SDK and are not used for device builds. An Apple account/team is not needed for this local ad-hoc Simulator signature.

Unit tests cover public DTO decoding, invitation validation, monotonic deadlines, secure credential storage/rotation, error recovery, and submission ID reuse after an uncertain network response. UI tests use the actual local API and real deadlines, not a local answer key or fake scoring. They cover native play, invitation acceptance, final comparison, relaunch recovery, results, the native share sheet, and rematch. A pixel-level assertion verifies that the gameplay viewport contains rendered cube faces. Backend tests additionally exercise a full native/web match and reject expired, tampered, wrong-transport, and unauthorized bearer sessions.

An unsigned device compile can run without provisioning:

```sh
xcodebuild -project apps/ios/BrainBattle.xcodeproj -scheme BrainBattle \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath apps/ios/build/Device CODE_SIGNING_ALLOWED=NO build
```

Build artifacts, test results, and screenshots belong in the ignored `apps/ios/build` or `apps/ios/DerivedData` directories.

## Manual configuration before distribution

- Release is configured for `https://brain-battle-api.onrender.com`. Keep production PostgreSQL, Supabase and session secrets on the server. A Next.js deployment is not required for this native beta.
- Select your development team, register the bundle identifier, provision devices, create the App Store Connect application, and configure release signing. Physical-device execution requires these steps and has not been assumed from an unsigned compile.
- The native beta shares codes, so no website or universal links are required. For an optional future web deployment, legacy HTTPS invitations open that web app unless universal links are configured. The app already handles the incoming activity; add your real `applinks` domain entitlement and host a matching `apple-app-site-association` file with your team/bundle identifier. Do not ship a made-up domain or team ID. Paste-to-open and the custom scheme work without that association.
- Review product privacy disclosures for stored guest names, identifiers and gameplay data, provide privacy/support URLs, and complete App Store metadata, age rating, export compliance and screenshots. The included required-reason manifest declares app-local preferences and timer uptime; it is not a completed App Store privacy questionnaire.
- Supabase-backed native refresh and external PostgreSQL need verification against a configured deployment. The local integration tests use the existing persistent-development auth path and PGlite.

Later mini-games, push notifications, account recovery/linking and offline scored play remain future work. Async rematches create another claimable challenge; live rematches create a shared fresh lobby. Live room gameplay is documented below. A 30-day expired anonymous native credential currently requires a future account/session recovery flow rather than silently replacing the guest.

Apple references: [Core Animation 3D layers](https://developer.apple.com/documentation/quartzcore/catransformlayer), [Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly), [associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains), and [required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).


## Native live multiplayer

**Play Live** now offers 1v1 and 3–8-player Party Mode. Create a private five-round Counting Boxes room, share its code or native invitation, ready up, and let the host start. Results, tied rankings, reconnect recovery and shared rematches use the existing Fastify server. No new environment variables or external packages are required. The existing API owner applies the additive migration on its normal restart; never start a second process against its PGlite directory.

Architecture, scoring policies, test commands and current limits: [LIVE_MULTIPLAYER.md](LIVE_MULTIPLAYER.md).
