# Counting Boxes: submission repair and answer reveal

## Root cause

`MatchViewModel.submit()` required `round.remaining(...) > 0` before making an
HTTP request. For the existing untimed v3 rules, `deadline` is absent and
`remaining` intentionally returns zero. The screen enabled Done, but the model
silently returned. The same guard silently discarded taps at a legacy deadline.

The screen also combined the server clock with an older boundary snapshot,
whereas submission used only the server clock. Polling could clear submission
errors, and `yoursComplete` immediately replaced round-five feedback with results.

## Submission behavior

- The server adjudicates submissions; a local countdown cannot silently discard
  Done. No scoring, deadline, or rules-version changes are part of this repair.
- An in-flight guard prevents duplicate writes. Every uncertain retry, including
  after relaunch, retains both the original submission UUID and captured answer.
  Input stays locked while that outcome is unknown.
- On failure the model fetches the authoritative match: a committed write whose
  response was lost becomes feedback, otherwise an actionable error remains.
  A definitive HTTP client rejection releases the pending answer for recovery.
- Polls started before submission cannot overwrite its response. Successful
  refreshes do not erase an unresolved submission error.
- Quick Count and Type Answer continue using the same answer. They stay disabled
  while the cubes are visible.
- Finalized round selection survives relaunch. Round five now shows its reveal
  before the player explicitly selects View results. Next still respects the
  server feedback window; starting the following round remains server-validated.

## Authorized reveal

The authenticated solo/async match response gains optional `round.reveal`:
`{ puzzle, correctAnswer, submittedAnswer }`. It is returned only after that
player's attempt has a persisted `submittedAt`, including a server-finalized
legacy timeout. It is absent from unfinished rounds, invitation previews and
outsider responses. Seeds remain private; opponent results retain their existing
finalization restrictions. No client-derived score or winner is accepted.

The displayed puzzle already includes the cube coordinates needed for rendering,
including supporting cubes. This change adds no solution field to that viewing
payload and does not cache it to build a local answer key. Reveal data is rebuilt
on the server from the saved seed and immutable game version after finalization.

The existing CATransformLayer renderer highlights a deterministic ordering of
every actual cube: supporting layers first, then back to front. Other faces fade
to a translucent purple ghost so supporting/interior cubes remain identifiable.
An increasing count accompanies the highlights. Normal pacing is 0.28 seconds
per cube, capped at five seconds for larger legacy structures. Skip immediately
shows the total. Reduce Motion skips counting and layer animations. Backgrounding
finishes the reveal rather than leaving a stalled animation.

After counting, the screen shows the server's correct answer, submitted answer,
correct/incorrect status and awarded score. Older servers without `reveal` retain
the previous feedback screen.

The reveal also runs in live 1v1 and Party Mode. Live responses include geometry
and the correct answer only when **every player** has a finalized attempt; early
submitters cannot obtain the shared solution. Newly submitted answers are saved
in the existing room JSON and included only with finalized results. Older stored
results without an answer remain compatible. No database migration is needed.
Live animations fit within the existing four-second server intermission (at most
three seconds, shortened on a late reconnect). The server continues scheduling
the next round. The final round reveals first, then offers View results.

## Files changed for this repair

- `BrainBattle/ViewModels/MatchViewModel.swift`
- `BrainBattle/Views/MatchView.swift`
- `BrainBattle/Models/APIModels.swift`
- `BrainBattle/Games/CountingBoxes/CubeSceneView.swift`
- `../../packages/shared/src/index.ts`
- `../api/src/service.ts`
- `BrainBattleTests/MatchViewModelTests.swift`
- `BrainBattleUITests/NativeBetaUITests.swift`
- `../../tests/reveal.test.ts`
- `../../tests/api.test.ts`
- `../../tests/native-auth.test.ts`
- This document.

Live coverage additionally changes `BrainBattle/Live/{LiveModels,LiveViews}.swift`,
`../api/src/live-service.ts`, `../../packages/shared/src/live.ts`,
`BrainBattleTests/LiveTests.swift`, `BrainBattleUITests/LiveUITests.swift`,
`../../tests/live.test.ts`, and `../../scripts/live-ui-fixture.ts`.

Other working-tree edits predate this repair. Backend/web architecture, secrets,
local databases, recovery backups and signing configuration are preserved.

## Local verification

Latest completed checks: **40 backend tests passed**, **32 native unit/integration
tests passed**, **one five-round iPhone 17 Pro Simulator UI test passed**, TypeScript
typecheck passed (API/shared and web), and unsigned iPhone Release build passed.
The UI run exercised Skip four times and restored round-one feedback after
relaunch. Initial test-only failures (an accessibility-label assertion, XCTest
missing a short reveal, and an attempt to override SwiftUI's read-only Reduce
Motion environment property) were corrected; the final run passed. Reduce Motion
initial-count behavior has unit coverage; its Settings appearance was not manually
verified. Logs are in `/tmp/brain-reveal-{backend-tests,final-swift,types,release}.log`.

Run `npm test` and `npm run typecheck` from the repository root. Native regression
tests are in `MatchViewModelTests`; they cover untimed submissions, deadline races,
duplicate taps, slow writes, lost responses, stale polls, retry identity across
relaunch, rejected writes, shared answer state, feedback/final-round progression,
supporting-cube ordering and Reduce Motion's immediate final count.

`NativeBetaUITests.testLocalDoneRevealAndFiveRoundResults` is an opt-in Debug UI
regression requiring an **isolated in-memory API on port 4012**. It sets launch
arguments for that origin and does not call Render. It plays five rounds,
switches input methods, exercises reveal/skip when still available, relaunches
during feedback and reaches results. The test uses the same real server timing
as the app. Small reveals can complete before XCTest finishes its idle wait.

## Try it in Xcode

1. In a terminal at the repository root, run `npm run dev -w @brain/api` using
   the existing local configuration. Run only one API against the persistent
   local database. Restart an older running API to pick up this code.
2. Open `apps/ios/BrainBattle.xcodeproj`, select the **BrainBattle** scheme and an
   iPhone Simulator, and use Product > Run (Command-R), with Debug configuration.
3. Ensure the app's development API setting is `http://localhost:4000` (or your
   configured local API). Start Solo Practice or an async challenge.
4. Wait for cubes to disappear, enter a number, press Done, watch or skip the
   reveal, then select Next Round. Round five offers View results.
5. Reopen during feedback to check restoration. Disconnect the network during a
   submission to check the visible retry/refresh path. Enable Reduce Motion in
   Simulator Settings > Accessibility > Motion to inspect its appearance.

Release points at Render. Render must be redeployed to return the new reveal
payload; no deployment or push is performed here. This repair needs no database
migration. The earlier untimed-v3 work already in this working tree includes
`0003_untimed_answers.sql`; that additive migration is still required if that
earlier feature has not been deployed. Legacy v1/v2 deadlines are retained.

Physical-device testing, hosted verification of this new payload and TestFlight
upload are separate steps and are not claimed by local Simulator checks.

## Live and Party follow-up

The native reveal now covers all four Counting Boxes entry points: Solo Practice,
async friend challenges, live 1v1, and Party Mode. The live backend must also be
redeployed to supply `round.reveal` and finalized `submittedAnswer` fields. Do not
expect the new reveal when running a Release app against the older Render build.

Focused live tests cover withheld solutions after early submissions, immutable
duplicate answers, timeouts, restart/reconnect, all five rounds, and an eight-player
party with a forfeit. Live payload decoding uses the same cube reveal planner as
solo/async. Existing web consumers ignore the additional optional fields.

The opt-in native live UI regressions are `LiveUITests.testLocalRevealDuel` and
`testLocalRevealParty`. They require an isolated in-memory API on port **4013**
and `BRAIN_TEST_API=http://127.0.0.1:4013 node --import tsx scripts/live-ui-fixture.ts`
on port 4011. They must run in Debug. Launch arguments isolate development URLs
and restoration state; they do not clear existing app preferences or Keychain.
Temporary APIs need a consistent signing secret when reusing a test origin;
otherwise the previous test guest token is correctly rejected. Production guest
authentication behavior is unchanged.

Follow-up validation: all **40 backend tests passed**, the expanded **13 live
backend tests passed** again, **four Swift live tests passed**, and **both native
Simulator UI tests passed** (five-round 1v1 and eight-player party, including
reveals, final results and rematches). Typechecking and the unsigned iPhone
Release build passed. The first UI attempts failed at guest restoration because
an earlier temporary token had a different signing secret; the final isolated
origin run passed. No physical-phone testing, push, or Render deployment was done.
Logs: `/tmp/brain-live-reveal-{tests,privacy-final,swift,ui-isolated,types-final,release}.log`.
