# Social Rivalry home — implementation notes

Implemented November 9, 2026, as a redesign of the existing SwiftUI app.

## What changed

- Warm off-white, charcoal, lavender, peach, blue, green, and pink extend `BattleTheme`.
- Compact wordmark/avatar header and “Your next rival awaits.” introduction.
- Featured recent rivalry with real player names, head-to-head wins/draws, decorative orange cube artwork, and the existing server rematch operation.
- Honest first-rivalry, loading, partial-load, and error states.
- Your Turn cards for actual joined challenges where the current player still has playable rounds.
- Side-by-side Challenge a Friend and Play Live cards. Live remains explicitly coming soon.
- Completed recent battles with server-derived victory/defeat/draw badges; solo completions are labeled Practice.
- Open battles remain reachable so unfinished solo attempts, unclaimed challenges, and results awaiting an opponent are not lost.
- Home, Games, Friends, and Profile navigation. Games includes existing solo practice and challenges; Friends provides challenge links and explains that friend lists are coming later; Profile opens the existing settings editor.
- Native selection haptics, safe-area bottom navigation, accessible button labels, and vertical layouts for large accessibility text. Navigation labels and avatar initials have bounded scaling; content retains Dynamic Type.

The gameplay renderer, API, database schema, authentication transport, web client, scoring, and deadlines are unchanged. The small orange illustration is decorative SwiftUI Canvas artwork, independent of the scored Core Animation cube renderer.

## Data source and limits

`GET /api/matches` returns only the latest eight match summaries, with no winner or completion fields. `AppModel.refreshHome()` loads their existing authorized `GET /api/matches/:id` projections. Requests are ordered to avoid racing bearer-credential refreshes. Successful details are projected into `HomeBattle`, which does not retain puzzle geometry.

`HomeHistory` preserves newest-first order and derives:

- **Rivalry:** the opponent in the most recent completed challenge available, grouped by stable opponent ID rather than display name. Wins/losses/draws come only from finalized server winner fields. The card labels this recent history; it is not an all-time leaderboard.
- **Your Turn:** joined, supported, unexpired challenges with unfinished own rounds. Unclaimed links, expired games, and already-finished own attempts are excluded.
- **Recent Battles:** completed games with an explicit valid result, plus completed solo practice.
- **Open Battles:** playable unclaimed challenges/solo games and challenges waiting for an opponent to finish.

A partial history load is disclosed. No opponents, wins, notifications, friendships, or invitations are fabricated. The current API cannot supply an exhaustive inbox, lifetime rivalry statistics, or older paginated results. Adding those later should use deliberate API additions; this redesign requires no database migration.

Home refreshes on appearance, foregrounding, and pull-to-refresh. It is not an always-polling inbox. Scoring and protected opponent results remain entirely server-controlled.

## Dismissing open battles — November 11, 2026

Each Open Battles row has a close-circle **Dismiss** button and an immediate **Undo** action. Dismissal is saved in local preferences per API origin and player ID, so it survives relaunch without affecting another guest or development server. A dismissed challenge also stays hidden from Your Turn if it is later claimed.

Dismissal does not cancel the match, revoke its link, change its deadlines, or affect the opponent. Complete results and rivalry calculations still use the full loaded history. A dismissed battle that later completes can appear in Recent Battles normally. The preference is local to this iPhone; it is not a cross-device archive. No backend or database changes are required.

Verified November 11: Xcode build, all **15 unit tests**, and the selected **Dismiss/Undo/relaunch** and **home/tabs/large-text** UI tests passed. The new unit tests cover persistence, player/server isolation, later claims, restoration, and preservation of completed history. Evidence: ignored local `build/DismissBattles-20261111.xcresult`. Gameplay/backend suites were not rerun for this local home-preference change.

## Files

- `BrainBattle/Views/HomeView.swift`: screen composition, destinations, sheets, existing navigation/actions.
- `BrainBattle/Design/SocialComponents.swift`: `FeaturedRivalryCard`, `PendingChallengeCard`, `BattleActionCard`, `RecentBattleRow`, `BrainBattleTabBar`, decorative artwork.
- `BrainBattle/Design/Theme.swift`: extended palette and configurable avatars.
- `BrainBattle/Models/HomeHistory.swift`: safe home projections and recent-history grouping/filtering.
- `BrainBattle/ViewModels/AppModel.swift`: authorized detail loading and featured rematch action.
- `BrainBattleTests/HomeHistoryTests.swift`: finalization, identity grouping, expiry, pending filtering, and no fabricated results.
- `BrainBattleUITests/CountingBoxesUITests.swift`: tab/settings/invitation navigation, large text, plus real completed-history and featured-rematch assertions in the existing challenge flow.

The existing Xcode project includes the new files. No package dependencies were added.

## Development and verification

Keep the existing API running; do not start a second process against the same PGlite store. Tests create ordinary test challenges through the API. Do not replace `.env`, reset `.data`, or discard recovery backups. See [RECOVERY-NOTE.md](RECOVERY-NOTE.md).

Open `BrainBattle.xcodeproj`, select BrainBattle and an iPhone Simulator, and run. See [README.md](README.md) for CLI test commands and physical-device setup.

The supplied redesign attachment contained the written brief but no separate mockup image, so the implementation follows the specified hierarchy, palette, typography, and native interaction requirements.

### Executed checks — November 9, 2026

- Final Xcode Debug build and full test run: **12 unit tests and 5 UI tests passed**, with no failures, on the iPhone 17 Pro Simulator.
- Separate final iPhone 17 Simulator run: **home/tab navigation and largest accessibility-text test passed**.
- Generic physical-iPhone target: **unsigned Release build succeeded**. This does not verify installation or play on a physical phone.
- Reviewed captured home screenshots with empty rivalry history, a real completed rivalry, pending turns, and large text. Existing challenge acceptance, five-round play, native share sheet, result navigation, featured rematch, and cube rendering/relaunch checks passed.
- Result bundles: `build/SocialRivalryFinal.xcresult` and `build/SocialRivalryFinal-iPhone17.xcresult`; exported screenshots are in matching `build/*-images` directories. These are ignored machine-local artifacts.

Backend/browser suites were not rerun for this native-only change. Hosted Supabase/PostgreSQL and physical-device execution were not tested in this redesign task.
