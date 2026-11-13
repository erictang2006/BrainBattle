# Native-only TestFlight beta readiness

November 12, 2026. Target API: `https://brain-battle-api.onrender.com`.

## Changes

- Release points directly to the hosted HTTPS API. Debug retains local development settings.
- Live rooms share six-character codes plus native joining instructions using ShareLink. The join field accepts plain codes and complete native share messages.
- Async matches share the existing 48-character invitation token as a challenge code. The native client extracts it from the authenticated host DTO locally, without opening its legacy website URL. Entry accepts the raw code, native share message and supported legacy native/configured-origin links.
- Preview and acceptance retain the original single-use/expiration/membership behavior. Private puzzle seeds and explicit answer keys remain server-only. No changes to engine rules, scoring or deadlines.
- Existing web application, backend API contracts, local `.env`, databases and recovery backups are preserved. The final audit adds a backward-compatible API reliability fix: room creation and rematches retry code collisions using the existing unique constraint and transaction. Expired rooms return HTTP 410 with a clear message, and the native client stops retrying terminal room errors. No schema change or migration is needed; redeploy the existing Render API to apply these safeguards.
- A reusable opt-in hosted smoke script and Release native UI check were added. They create fresh test guests/games only and never reset existing data or log credentials.

## Executed validation

- Public health check returned `{"ok":true,"auth":"supabase"}`.
- Hosted HTTP/Socket.IO smoke: three independent Supabase guest sessions; authenticated identity restoration; async token preview/claim; third-guest duplicate claim rejection; five async rounds with identical puzzles and agreed results; fresh async rematch; full five-round live 1v1 and three-player party; equivalent puzzles; duplicate protection; reconnect with unchanged deadlines; matching final standings and live rematches. **Passed without any website request.**
- Backend regression suite: **34 tests passed**, including forced collision retries for creation/concurrent rematches and bounded failures without data changes, against isolated test databases. No local or hosted production database reset.
- Device-targeted Release compile with signing disabled: **passed**. This is a compile check, not physical-device execution or a signed distribution archive.
- Built Release Info.plist: both API and compatibility-origin values resolve to `https://brain-battle-api.onrender.com`.
- App icon checked: 1024×1024, no alpha channel.
- Native Release tests: **23 passed on the final independent retry**, including raw challenge codes, native share-message parsing, malformed/ambiguous input rejection, legacy-link compatibility, Keychain round-trip, existing async view models, and actual Swift Socket.IO guests against the hosted API with unchanged reconnect deadlines and agreed round results.
- Release Simulator UI on iPhone 17 Pro: the expanded async check **passed** all five native rounds against a host that completed its five rounds first, final comparison, native code sharing, live room creation/sharing, and background/foreground lobby recovery. The expanded solo check also **passed** all five rounds, results, and terminating/relaunching the app with the same saved result and no repeat onboarding. No Next.js site was used.
- The first UI test build hit a Swift 6 async-test wait API restriction; it was corrected and the complete Release test run passed. Normal Archive testability/signing settings remain unchanged.

The hosted smoke verifies actual application reads/writes and authentication through the deployed API. It does not directly inspect the server's DATABASE_URL, rotate credentials, restart Render or audit the database provider's dashboard. The deployment owner should retain the production PostgreSQL configuration they have set up.

## Manual steps before upload

- Select an enrolled Apple Developer team. No team ID is checked into the project.
- Confirm/register the existing `com.brainbattle.BrainBattle` bundle identifier under that team or replace it with an available identifier consistently.
- Current version is `0.1.0`, build `1`; increase Build if already uploaded. Availability in App Store Connect was not independently checked.
- Test Release on physical iPhones, including cellular access, guest restoration, both live modes, async codes, background/reconnect, final results and rematches.
- Create/select the App Store Connect app, archive the signed app, validate/upload, and complete beta metadata/review and tester invitations.

Physical-device execution, a signed archive, TestFlight upload and beta approval have **not** been performed by this change. See [the TestFlight guide](../../TESTFLIGHT.md).

## Final audit notes

- A hosted sign-in request timed out in the initial combined Release test run. A separate production session probe completed successfully in about one second, and all 23 native unit/integration tests passed on the independent iPhone 17 retry. The initial combined run is not reported as green. Hosting and device-network reliability still require the physical-phone checks below; no timer rules were relaxed to accommodate a timeout.
- The checked-in privacy manifest declares UserDefaults and system-uptime usage, with tracking disabled. The app does not enable arbitrary insecure transport. Local-network access supports Debug development. `brainbattle` is the optional custom URL scheme; no associated-domain entitlement or universal-link deployment is required.
- The simulator-only local Keychain entitlements are conditional on the simulator SDK. The device build does not use `LOCALTEST` signing material. No Apple team, signing certificate or App Store credentials have been invented or changed.
- Current Release API origin remains `https://brain-battle-api.onrender.com`; compatibility parsing does not fetch a web page. `WEB_ORIGIN` remains only for server CORS and legacy web contracts.

## Final live Release UI checks

- iPhone 17 Pro: **passed** hosted native 1v1 joining by code, Ready, all five rounds, results and rematch.
- iPhone 17: **passed** hosted native Party room creation, six-character sharing code, seven authenticated test peers joining, native host Ready/Start, all five rounds, final rankings and rematch.
- These two checks used the existing Render API. The loopback test companion only supplied automated peer players; it did not host game state, open a database or act as a website. The actual iOS client used the public HTTPS/WSS API directly.
- These are four passing native UI cases in this audit: full async, full solo/relaunch, live 1v1, and native-hosted eight-player party. The party check uses one native client and seven Node Socket.IO peers, not eight physical phones.

## Files changed in the native-only preparation and final audit

- `apps/ios/Configuration/Release.xcconfig`: real Render HTTPS origin and compatibility-only origin alias; Debug configuration unchanged.
- `BrainBattle/Models/APIModels.swift`, `Live/LiveModels.swift`: native challenge/room share messages and validated code redemption.
- `BrainBattle/Views/{HomeView,InvitationView,MatchView}.swift`, `ViewModels/AppModel.swift`, `Live/LiveViews.swift`: code-based UI and native ShareLink, without website navigation.
- `BrainBattle/Live/LiveRoomModel.swift`: terminal expired-room handling alongside existing reconnect behavior.
- `apps/api/src/live-service.ts`: bounded collision retries for creation/rematches and clear expired-room responses, preserving existing contracts and data.
- `tests/live.test.ts`: forced collisions, concurrent rematch allocation, exhaustion and expiration tests.
- Native `RulesPresentationTests`, `LiveTests`, `LiveIntegrationTests`, `NativeBetaUITests`, `LiveUITests`: code validation, real Release transport and full gameplay/reliability checks.
- `apps/ios/BrainBattle.xcodeproj/project.pbxproj`: includes the new native beta UI test source; signing/team/build choices preserved.
- `scripts/check-hosted-beta.ts`, `scripts/live-ui-fixture.ts`: opt-in hosted validation with no direct database access or credential logging.
- `TESTFLIGHT.md`, root/iOS READMEs, `LIVE_MULTIPLAYER.md`, this report: native-only instructions and exact verification limits.

## Required rollout order

1. Review and commit/push the prepared changes to the branch connected to the existing Render service. Allow its configured auto-deploy, or deploy that commit using Render's existing service controls. No new deployment service is needed.
2. Check `/api/health` and a new room after deployment. The collision retry fix was verified against isolated databases; it has not been silently deployed or claimed to be exercised on the unchanged production server.
3. In Xcode, select your enrolled Apple team and confirm/register the bundle ID. Current version/build: `0.1.0` / `1`; increment Build if already used.
4. Test Release on real iPhones over cellular, then select BrainBattle → generic iOS device → Product → Archive. Use a normally signed Release archive, not the unsigned compilation artifact.
5. Upload through Organizer → Distribute App → App Store Connect. Assign an internal group, install on your own phone, then create the external group, supply beta metadata/review information and invite friends after approval.

Not executed: the complete legacy CountingBoxesUITests suite (the four selected hosted readiness UI cases were run), physical-device testing, a deliberate production database outage, forced expiry/rotation of a real Supabase refresh token, signed distribution archive creation, App Store Connect upload or beta approval. Existing database/auth error and expiration paths are covered by isolated tests; no production outage or data reset was induced for validation.
