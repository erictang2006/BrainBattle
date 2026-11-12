# Live multiplayer implementation

## Rollout checkpoints

Phases A–C are implemented in order: one-round 1v1 infrastructure, five-round progression/rematches, then 3–8-player parties. New rooms default to five rounds; existing one-round rooms keep their format. Reaction Time and Sequence Memory do not exist yet; mixed games remain Phase D.

## Architecture

Existing async tables, engine versions, web API contracts, signed web cookies and native Keychain credentials remain intact. An additive `0002_live_rooms.sql` migration introduces `live_rooms`. Each room is a small private JSON aggregate locked with PostgreSQL `FOR UPDATE` on every mutation. This keeps joins, starts and submissions atomic without a second service. The schema journal applies migrations once to PostgreSQL or PGlite. Do not run a migration command or another API process against an open PGlite directory: the existing API applies migrations during its normal startup.

`LiveService` owns room membership, readiness, seeds, scoring, deadlines and result finalization. It resolves Counting Boxes through the existing versioned registry. The server scheduler resumes persisted deadlines after restart. Every socket authenticates through the existing session verifier; explicit 401 event acknowledgements trigger native reconnection through the HTTP session refresh flow without replacing the guest; live commands revalidate credentials, authorize membership, validate strict Zod payloads and apply a per-socket event budget. HTTP creation and joining use the same authenticated API transport as async matches.

The Swift `LiveSocket` implements the Engine.IO v4 / Socket.IO v5 default-namespace JSON subset over URLSession WebSockets: namespace connect, heartbeats, event framing, acknowledgements, timeouts and disconnect. It is not a bare WebSocket pretending to be Socket.IO. No new dependency is required. Protocol references: https://socket.io/docs/v4/engine-io-protocol/ and https://socket.io/docs/v4/socket-io-protocol/ .

`LiveRoomModel` reconnects using the same Keychain identity, subscribes to a complete room snapshot and rejects older revisions. Three clock samples select the lowest round-trip time and estimate the server clock at the midpoint. Rendering uses monotonic elapsed time after synchronization. Backgrounding closes the connection; foregrounding refreshes authentication and restores the snapshot. Draft count and stable submission UUID persist per origin, identity, room and round. Relaunching while in a room restores its route; Play Live also offers the last room for that profile.

## Synchronization and privacy

The host starts only when the minimum count is met (exactly two for a duel, at least three for a party) and every member is connected and ready. A future server timestamp provides a preparation window. Public cube coordinates arrive before that timestamp to permit preparation; the native view hides them until the scheduled start and hides them at the persisted display deadline. Seeds, submission UUIDs and explicit answer keys are never in snapshots. Scores and correctness remain private until all attempts are finalized or the deadline passes.

Coordinates necessarily reveal the count to an instrumented client. This is the same inherent limitation as the existing counting game; preparation is not a cryptographic anti-cheat boundary. Clock estimates have network uncertainty. Late connections keep the original deadlines; there is no claim of physically simultaneous display or latency-compensated scoring. v2 scoring and viewing/answer durations are unchanged.

## Lifecycle policy

Lobby invitations expire after two hours. New membership is rejected after start; existing members can restore their snapshot. An offline lobby host transfers to a connected member after 20 seconds. When another lobby member is online, slots offline for 30 seconds are released so an absent member cannot block the ready check. Rejoining restores the same identity if a slot is still available and the room has not started. After start the server runs independently of the host. Network disconnects never extend a deadline or immediately forfeit a player. Missing attempts become zero at the common deadline. Voluntary in-game leave forfeits remaining attempts and removes final winner eligibility. Earlier finalized attempts and their recorded points remain immutable; forfeited players rank last. The first scored attempt is immutable, including retries with a different UUID. Empty lobbies close.

## Scoring and rematches

Duel standings count unique round wins. Equal raw scores draw the round and award neither player a win. Equal final win counts share first place. Existing engine scoring is unchanged.

Party placement uses competition ranking: `1 + number of non-forfeited scores strictly greater`. Points are `N - placement`, where N is the roster frozen at match start. Tied players receive the same placement and points, and subsequent places are skipped. For eight players, scores tied for second receive six points each; the next player is fourth and receives four. If all players time out with zero, they share first and receive N−1 points each. Forfeits always earn zero for forfeited rounds. Final points use the same tied-rank policy; no hidden time or identity tie-breaker changes scores. Sorting equal ranks by player ID is only for stable presentation.

A four-second persisted intermission follows every non-final round. Each next round has its own four-second prepare window and unchanged v2 viewing/answer duration. The scheduler starts overdue *next* rounds in the future after a restart rather than fast-forwarding unseen puzzles. Finalized rounds contribute immutable totals. Concurrent rematch requests lock the original room and create one shared fresh lobby, preserving mode, limit and round count. Players opt into that lobby with their existing identity; the previous result remains available.

## Local testing

Keep the existing API on port 4000. Open `apps/ios/BrainBattle.xcodeproj`, choose the BrainBattle scheme and an iPhone Simulator, then Run. Choose **Play Live**, create a room, share its six-character code, and join from the second Simulator using its own guest session. Native links use `brainbattle://room/CODE`; these are custom scheme links, not configured universal links. Physical phones need the existing LAN/HTTPS API configuration.

`npm test` covers the server and async regressions. Native `BrainBattleTests/LiveIntegrationTests` creates fresh guests through the existing local API, then tests two actual native Socket.IO transports, reconnect and finalized results. It skips when the local API cannot establish a guest session. It never opens the database directly.

For the automated native UI flow, run `node --import tsx scripts/live-ui-fixture.ts` alongside the existing API, then run `BrainBattleUITests/LiveUITests`. The test companion listens only on localhost:4011, creates fresh guests via HTTP, and plays a companion using the official Node Socket.IO client. Stop it after testing. It does not add a production route or change any database files directly.

## Deployment limits

This first implementation runs one API process. Socket presence and broadcasts are process-local; horizontal scaling needs a shared Socket.IO adapter, coordinated scheduler and shared presence. PostgreSQL support follows the existing Drizzle driver; automated persistence tests currently use PGlite. No environment files, recovered databases or backups need replacement. Existing async history remains separate from live rooms.

## Verification recorded November 12, 2026

- `npm test`: **32 passed**. Includes deterministic/scoring tests, async authorization/idempotency, additive v1-to-v2 migration, actual database close/reopen with original live/async deadlines, eight authenticated sockets, capacity races, five-round party points/ties/forfeits, reconnect, host recovery and shared rematches.
- `npm run typecheck`: passed for backend, packages, tests and web.
- `npm run test:browser`: **2 passed**, covering two independent browser guests completing an async challenge and the original cookie-authenticated Socket.IO notification contract.
- Xcode Debug Simulator build and build-for-testing: passed.
- Native `BrainBattleTests`: **22 passed**, including two real Swift Socket.IO transports with separate fresh guest sessions, equal public puzzles, reconnect, stable deadlines, duplicate submission and agreed final results. The native integration test executed against the existing API; it was not skipped.
- iPhone 17 UI test: five-round 1v1 join/ready/play/results/rematch passed.
- iPhone 17 Pro UI test: eight-player party join/ready/five rounds/results/rematch passed. This uses one SwiftUI client and seven independent official Node Socket.IO test peers; it is not a claim of eight physical phones or eight Simulators.

The latest native tests also cover protocol framing/heartbeat packets, validated room links, absolute phase boundaries, Keychain behavior and existing async view models. Full-duration UI matches exercise server heartbeats for over a minute. Failed development runs were corrected and rerun: reconnect teardown no longer closes a replacement socket; the test companion is kept stable during a match.

Physical iPhone execution, distribution signing, production Supabase refresh, external PostgreSQL deployment, universal links and multi-process scaling were not verified here. The existing Core Animation renderer is unchanged. Mixed games are not implemented. The web keeps its async/solo screens and does not yet expose native live room UI.

### Reproducing the native checks

With the single existing API running, start the test-only helper:

```sh
node --import tsx scripts/live-ui-fixture.ts
```

Then use the Xcode Test navigator for `BrainBattleTests` and `LiveUITests`, or:

```sh
xcodebuild -project apps/ios/BrainBattle.xcodeproj -scheme BrainBattle \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath apps/ios/build/LiveDerived \
  -only-testing:BrainBattleTests -only-testing:BrainBattleUITests/LiveUITests test
```

Use different explicit result bundle paths when running `test-without-building` on multiple Simulators concurrently. Stop the helper when testing is complete. The shared package's `@brain/shared/live` entry point contains runtime live validators; the original entry point re-exports live types only, keeping Next.js source-module resolution compatible.
