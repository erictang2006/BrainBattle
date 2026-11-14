# Visual Memory

Implemented for native Brain Battle Solo, live 1v1, and 3–8-player Party Mode. Existing Counting Boxes rules, async invitations, room codes, and five/ten-round formats remain in place. Nothing was pushed or deployed.

The supplied attachment contained the written specification only. No screen recording was available, so exact timing and progression could not be compared with the video.

## Playing

Open **Games → Play Visual Memory**. Choose Solo or **Play Live → 1v1 Battle / Party Mode**. Visual Memory is also selectable from the existing Play Live screen. Live rooms use the existing codes, sharing, ready checks, host start, reconnect, results, and shared rematch lobby.

- Solo has three hearts and no match deadline or final level. Results show highest level reached, score, hearts, mistakes, personal best, and Play Again.
- Live players start together after a four-second countdown and have a shared two-minute deadline. Each advances independently. The match ends earlier if everyone is finished.
- Each player's three hearts and mistake counter are independent. An eliminated player sees their saved run and live scores while others continue. Disconnected players can return before the original deadline; offline players cannot delay results past it.
- Results show winners/ties, every score, highest levels, remaining hearts, final ranks, and rematch. Players who voluntarily leave are marked forfeited and ranked last.
- The Visual Memory menu includes persistent personal best and the latest 20 runs across modes. Open a run to resume it or review results. The active game also restores after relaunch using the existing room navigation recovery.

## Hearts and progression

Three different wrong tiles consume one heart. The first two show crosses and a 1/3 or 2/3 mistake counter. The third shows “Three mistakes. One heart lost,” resets the counter, and retries the current level with a different pattern after 1.5 seconds. Correct tiles show checkmarks and never add mistakes. Three lost hearts end the run.

Clearing a level resets mistakes and advances after 800 ms. Repeated taps cannot add mistakes or points. A turn's level and retry number travel with every selection so delayed packets cannot modify the next turn. Early taps and taps after finishing are ignored by the server; tiles outside the grid are rejected.

A confirmed **Forgot the pattern? Retry for 1 heart** action provides an interruption recovery path. It explicitly spends a heart, resets mistakes, and deals a new pattern at the same level. The feedback distinguishes this from three wrong selections; retries do not invent wrong-tap statistics.

| Levels | Grid | Lit tiles |
| --- | --- | --- |
| 1–2 | 3 × 3 | Level + 2 |
| 3–5 | 4 × 4 | Level + 2 |
| 6–9 | 5 × 5 | Level + 2 |
| 10–14 | 6 × 6 | Level + 2 |
| 15–20 | 7 × 7 | Level + 2 |
| 21+ | 8 × 8 | Level + 2, capped at 48 |

Observation starts at 1.5 seconds. Beyond level 46, it gradually shortens to a 600 ms minimum. Progression continues after the tile cap through fresh patterns. There are always at least three unlit tiles, and sampling never duplicates a tile. Successive retries cannot accidentally repeat an identical pattern.

The lavender grid uses white highlights, animated correct/incorrect tiles, tap feedback, heart loss feedback, reduced-motion support, and accessible row/column labels. Level, hearts, score, and timer remain pinned above the scrolling content on smaller iPhones.

## Fairness, timing, scoring, and storage

`packages/games/src/visual-memory.ts` defines immutable v1 rules, deterministic patterns, and scoring. A cryptographically random private room seed determines each level/retry. Everyone receives the same pattern for the same level and retry, regardless of their pace.

Scores are **1,000 per cleared level + 10 per correct tile in the current unfinished level − total wrong taps**, floored at zero. Completing a level replaces its partial tile points with 1,000. A retry resets partial points when the next pattern starts. Lost lives retain the unfinished attempt's partial score at elimination. This prevents farming points across retries. There are no client-reported scores, correctness flags, lives, elapsed times, or speed bonuses. Equal scores share a rank.

The existing `live_rooms` JSON aggregate stores the private seed, absolute deadlines, each player's progress, and results. Row locks serialize concurrent commands, finalization, and rematch creation. The scheduler resumes from persisted state after API restart. All HTTP responses, socket ACKs, and socket broadcasts are personalized: a player cannot receive someone else's highlighted pattern or selected tile positions. Own observation geometry is preloaded before its scheduled start; it disappears locally at the authoritative observation deadline. No seed or future level's pattern is returned.

The native client uses the existing authenticated HTTP and Swift Socket.IO transport. It hides highlights and disables input when inactive or disconnected. Backgrounding/reconnecting does not restart viewing time. A missed pattern can be retried for the clearly stated heart cost. Friendly competition still necessarily allows a modified client to record its own displayed pattern, as with the existing Counting Boxes geometry.

**No Visual Memory database migration, environment variable, external package, or web deployment is required.** Existing startup migrations still apply normally, including the separately existing ten-round migration. History uses the same room aggregates; personal best is calculated across all saved runs.

## Verification

Passed locally:

- `npm test`: all 55 tests, including 11 Visual Memory regressions and the existing Counting Boxes, auth, persistence, invitations, reveals, and ten-round tests.
- `npm run typecheck`: shared packages, API, tests, and existing web app.
- Native unit suite: 40 tests, including Visual Memory DTO/deadline/input tests and two actual native Swift Socket.IO matches (1v1 and three-player party).
- Native live checks verify equal patterns, private projections, independent hearts, clearing a level, elimination before others, final rankings, and shared rematches.
- Backend socket checks play eight authenticated Visual Memory guests to early completion and inspect every broadcast for pattern/selection leaks.
- Solo tests advance through 55 completed levels, verify original deadlines after service restart, and continue beyond a day without a solo deadline.
- Both Simulator UI tests passed on iPhone 17 Pro and the compact 375 × 667 iPhone Simulator. They verify entry, three explicit heart losses, Game Over, Play Again, relaunch recovery, personal-best results, and live game selection. The final compact run additionally asserts that the pinned hearts remain visible after scrolling to the retry control.
- Debug Simulator build and unsigned Release device compile. The original app bundle ID, development team, and existing build number are preserved.

Test results and screenshots are in ignored `apps/ios/build/VisualMemory*.xcresult` artifacts. The test companion runs an isolated in-memory API on port 4016, without reading `.env` or opening the existing persistent store.

Still manual before distribution: compare pacing with the missing recording; play on physical iPhones of different sizes; exercise weak cellular/Wi-Fi connections and interruption during observation; run a real 8-device party; and verify a signed TestFlight build against the updated Render API. A successful unsigned device compile does not sign or distribute a TestFlight build.

## Run locally in Xcode

1. If the local API is already running, let its existing watcher reload these changes or restart that process. Do not open a second API against the same persistent PGlite directory.
2. Otherwise, from the repository root:

   ```sh
   npm install
   npm run dev -w @brain/api
   ```

3. Open `apps/ios/BrainBattle.xcodeproj`. Select **BrainBattle**, **Debug**, and an iPhone Simulator; Build and Run. All new source files are already registered in the project.
4. Debug defaults to `http://localhost:4000`. If previously configured for a different API, update **Profile → Development server settings**.
5. Open **Games → Play Visual Memory**. For live testing, run another Simulator with a different guest, create a Visual Memory room, join its code, mark everyone Ready, and start as host. A party needs at least three players.

To reproduce isolated automated native checks:

```sh
npx tsx scripts/visual-memory-fixture.ts
# In another terminal:
xcodebuild -project apps/ios/BrainBattle.xcodeproj -scheme BrainBattle \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath apps/ios/build/VisualMemory \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -only-testing:BrainBattleTests/VisualMemoryTests \
  -only-testing:BrainBattleTests/VisualMemoryIntegrationTests \
  -only-testing:BrainBattleUITests/VisualMemoryUITests test
```

Keep Simulator signing enabled for Keychain access. The companion can be stopped with Ctrl-C; its data is disposable.

## Deployment

**Render needs an API redeployment before a distributed iOS build can play Visual Memory.** Release retains the existing hosted API origin. Deploy the backend before distributing the new client; older clients continue to default to Counting Boxes. A new signed iOS build is needed to expose the native feature. No deployment or GitHub push was performed.
