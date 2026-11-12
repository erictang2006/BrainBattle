# Counting Boxes v2 — sparse grid and quick counting

Implemented November 11–12, 2026. New matches and rematches use `counting-boxes@2`. Stored v1 matches continue to use their original deterministic generator, 8-second display, 12-second answer window, and scoring. No schema migration or historical-row rewrite is needed: the existing match rule-version field selects the engine.

## Gameplay

| Rounds | Difficulty | Total cubes | Observe     | Answer    |
| ------ | ---------- | ----------- | ----------- | --------- |
| 1–2    | Easy       | 3–5         | 3 seconds   | 6 seconds |
| 3–4    | Medium     | 6–10        | 2.5 seconds | 6 seconds |
| 5      | Hard       | 11–16       | 2 seconds   | 5 seconds |

The placement area is a maximum 5×5 grid, not 25 mandatory cubes. Seeded generation selects sparse ground positions and supported vertical additions. Some columns are isolated; others form adjacent groups. Heights are capped at two for Easy and three for Medium/Hard. A visibility constraint avoids a taller column completely covering another on the same projected diagonal. Supporting cubes can still be occluded and inferred.

Coordinates are generated on the server from a private per-round seed and the stored version. Both participants receive the identical puzzle. v1 and v2 have separate deterministic golden fixtures. Count ranges and time values are centralized in the v2 engine; changing published values requires another rules version rather than editing saved-match behavior.

Native graphics retain Core Animation `CATransformLayer`, fixed isometric orientation, distinct faces, and stable geometry-aware framing. v2 adds a subtle ground grid. Normal gameplay has no rotation/reset controls, automatic spin, or moving-cube mode. The web renderer and SVG fallback also support the sparse grid and stationary presentation.

## Input and progression

- Quick Count starts at **0**, with a prominent **+1**, smaller **−1**, and **Clear**.
- Counting works during observation and answer time. The same count remains when cubes disappear.
- Type Answer selects the compact keypad. Switching methods preserves the same bounded answer value; backspace/clear cannot produce a negative count.
- Native input uses subtle selection haptics. No software keyboard is required.
- Done becomes available after the cubes disappear. The server still rejects early submissions.
- Own draft counts are stored locally per player/match/round (and API origin on iOS). Relaunch restores the draft without restarting the server clock. Only the player's entered count is stored, never a private seed or answer key.
- After finalization, a server-derived one-second feedback gate prevents starting the next round too early. The gate uses the existing submitted timestamp; retries and refreshes cannot bypass or reset it. The client enables Next Round at the returned `feedbackUntil`.

v2 keeps 1,000 points for a correct answer plus up to 500 for speed, normalized over that round's actual 5- or 6-second answer window. Wrong, null, early-invalid, or expired answers receive no scored success. Final scores/winners and opponent-result visibility remain server-authoritative. A rematch is a new v2 match even when created from a completed v1 match.

## Architecture changes

- `packages/games`: immutable v1 implementation plus separate v2 generator/rules/scorer and version registry.
- `packages/shared`: public round timing/difficulty metadata, optional grid size, own feedback boundary; no private answer fields.
- `apps/api/src/service.ts`: version-specific start/expiry/score calculations and feedback enforcement using existing persisted attempts.
- `apps/ios`: v1/v2 DTO support, metadata-driven countdown/ready labels, shared quick/keypad state, draft persistence, stationary ground-grid rendering.
- `apps/web`: timing metadata, shared Quick Count/Type Answer, saved draft, stationary R3F/SVG grid, renderer code preloading before play.

The Social Rivalry home, dismiss preferences, guest/Keychain identity, invitation ownership, atomic claims, one-attempt constraint, submission UUID replay protection, and database directory lock remain intact. The existing API process is reused; `.env`, `.data`, and recovery backups are not reset or rewritten.

## Reference review

Both supplied three-minute Simulator recordings were sampled and inspected before implementation. They show Brain Battle's home, open-battle list, and current ready screen; the sampled sequences do not show the original online reference game. The written specification supplies the sparse-grid, timing, stationary-camera, and +1 interaction requirements implemented here.

## Validation and remaining limits

- All 20 Vitest tests passed: v1/v2 deterministic fixtures and geometry, five-round authorization/idempotency/expiry behavior, v2 scoring/feedback timing, native/web authentication compatibility, and persistence/clock recovery. The legacy API suite explicitly creates stored-v1 fixtures in its isolated test database; it does not rewrite real matches.
- TypeScript checks and production Next.js build passed. The two real-browser tests passed on the final web/backend code, including identical puzzles for desktop/mobile guests, reload, final results/rematch, and Socket.IO authorization.
- 18 Swift unit tests passed, including shared rapid counting/typing, draft restoration, metadata-driven short clocks, and keeping finalized rounds visible until explicit Next Round.
- Native UI scenarios were exercised across focused runs: acceptance/final comparison, correct feedback, open-battle dismissal, home, five-round share/rematch, renderer hiding/relaunch, home tabs/large text, and Quick Count/switching/relaunch. Initial runs exposed an API watcher reload during connection and older automation overrunning the short windows; the affected tests were rerun after the backend stabilized and the scenarios were separated. A real timeout-feedback round-selection issue was fixed and covered by a unit regression.
- An unsigned Release iPhone-target compile succeeded; this does not establish physical-device execution or haptic feel. Hosted Supabase/PostgreSQL were not exercised.

Machine-local evidence is under the ignored `apps/ios/build/CountingBoxesV2-*.xcresult` bundles and `/private/tmp/brain-v2-*.log`. In particular, `CountingBoxesV2-Verified` contains the full-run UI results (one connection failure), `CountingBoxesV2-Interaction` contains the passing five-round share/rematch flow, and `CountingBoxesV2-CountVerified` contains the passing quick-count/input-switch/relaunch scenario. Test result history is retained rather than treating the earlier failed runs as passes.

For local review, keep the existing API process running, build the BrainBattle scheme in Xcode, and create a **new** challenge or solo practice match to see v2. Opening an older match correctly shows the original v1 puzzles and timers. Public deployment, registered-account recovery, live rooms, additional mini-games, and TestFlight remain separate work.

### Final compact-device limitation

The iPhone SE Quick Count/switching/relaunch test passed before a final responsive-height adjustment. Screenshot review then found +1 partly covered by Done; the puzzle panel was reduced for short viewports, and the existing frame assertion verified that +1 is wholly above Done. The latest compact run passed all 18 units but its two long UI scenarios failed after a prolonged Simulator stall/real deadline expiry. Those whole scenarios are not reported as passes for the final compact layout.

A final short compact rerun could not execute: automatic permission approval review timed out twice before the Simulator restart command ran. No Simulator data was erased. The existing app's final Debug build succeeded; the generic Release compile and main-Simulator feature checks had succeeded earlier. Manually rerun the compact UI checks after Simulator is responsive to complete this last validation step. Physical-iPhone execution and haptic feel remain unverified.
