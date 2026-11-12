# Counting Boxes — native gameplay polish

> Historical document. The current default is the implemented [Counting Boxes v2](COUNTING_BOXES_V2.md), with sparse 3–16-cube puzzles and faster timing. Its fixed five-round progression supersedes the earlier difficulty proposal; v1 behavior remains available for stored matches.

Implemented November 9, 2026. This is a presentation and interaction update to the existing native app, with the soft pastel design retained.

## Implemented

- Kept the native Core Animation `CATransformLayer` renderer and its six transformed faces per cube.
- Replaced the small fixed framing scale with geometry-aware framing. Public cube corners are projected across the bounded rotation range, producing a stable fit without zoom changes as the player rotates. Camera orientation remains consistent; no automatic spin or reveal animation consumes display time.
- Improved face shading and edge contrast, with larger, more legible stacks and 44-point rotation/reset controls.
- Added a compact five-round progress strip that distinguishes completed correct and missed attempts using server feedback.
- Added a circular countdown with monospaced seconds, a peach urgency state, and light haptics during the final three seconds. Only the small countdown ticks; the cube scene stays outside `TimelineView`.
- Kept cube removal immediate at the persisted display boundary. Heading/numeric transitions animate independently; there is no outgoing cube fade that would keep geometry visible into answer time.
- Focused timed play on the puzzle or answer. Matchup/share details are deferred until outside the timed phase.
- Added a pastel answer panel, responsive numeric keypad, pressed states, edit haptics, and a submit action pinned above the bottom safe area. The input remains scrollable on compact screens and at large text sizes.
- Added success/miss/timeout feedback, server-returned points, and a clear next-round action, without revealing the expected count.
- Redesigned results with an outcome emblem, player score cards, own accuracy, per-round points, protected opponent results, sharing, and the existing rematch flow.
- Respected Reduce Motion for rotation/press/content animations and retained native accessibility labels.

## Rules and security are unchanged

The server still owns `counting-boxes@1`, private seeds, deterministic generation, 8-second display, 12-second answer window, scoring, invitation claims, attempts, and match finalization. No backend, web, schema, `.env`, or recovery-backup changes were required.

The new progress ring is presentation only: it uses the stored deadlines and v1 display duration. It does not create another clock or reset a deadline. Refresh, foreground recovery, and app relaunch use the same attempts. Keypad changes do not alter the existing submission UUID/idempotency behavior.

Own feedback uses the server's attempt result. Opponent totals and the winner remain hidden until match completion; round results follow the server's per-round finalization flags. Results never include private seeds or expected answers.

## Source map

- `BrainBattle/Games/CountingBoxes/CubeSceneView.swift`: existing native renderer, stable framing, face styling, rotation controls.
- `BrainBattle/Design/GameplayComponents.swift`: progress strip, small countdown view, keypad button style.
- `BrainBattle/Views/MatchView.swift`: focused timed layout, immediate phase boundary, sticky submit, keypad, feedback, progression.
- `BrainBattle/Views/ResultsView.swift`: completed/waiting/solo results and rematch.
- `BrainBattle/Models/APIModels.swift`: clamped, read-only v1 countdown progress.
- Native unit/UI tests: deadline progress, actual cube rendering/hiding, keypad edits, submit reachability, relaunch, and the existing complete challenge flow.

## Difficulty is a separate proposal

Easy/Medium/Hard are not implemented or selectable in this update. See [COUNTING_BOXES_DIFFICULTY_PROPOSAL.md](COUNTING_BOXES_DIFFICULTY_PROPOSAL.md) for target cube counts/times and the required server, migration, versioning, and client compatibility work. Existing matches must remain on unchanged v1 rules.

## Executed verification

- **13 native unit tests passed**, including countdown progress at display/answer/deadline boundaries and existing DTO, credential, history, and submission-retry tests.
- **All 5 existing native UI regression tests passed** on the iPhone 17 Pro Simulator: complete two-player acceptance/results, recent-history/rematch navigation, five-round play/share/rematch, render/relaunch, and home/large text.
- **An additional correct-answer UI test passed** on the iPhone 17 Pro. It counts the fixture host's public render coordinates, then plays the identical first puzzle as the native guest. The server validates the answer; the test verifies “Spot on!” and Next Round. No private seed or expected-answer endpoint is used. There are now six UI tests in the target; the new test was run separately from the five-test regression run.
- **Compact iPhone SE (3rd generation) render/input test passed:** visible cube faces, hidden geometry at answer time, keypad entry/clear, reachable pinned submit, next round, and round-two rendering after relaunch.
- **3 existing Vitest game-engine tests passed** using `npm test -- tests/games.test.ts`, preserving v1 determinism, geometry, and scoring checks.
- **Unsigned Release compile for an iPhone target succeeded.** This is not physical-device execution. Haptic feel and actual phone performance still need a device check.
- Reviewed captured cube, waiting-result, final-comparison, answer-entry, and correct-feedback screens. Swift formatting/lint checks cover the changed native sources.

The initial UI run found that a container accessibility identifier masked the Next Round button identifier. It was removed, and the corrected compact and full regression runs passed. Artifacts are under the ignored `build/GameplayPolish-Verified.xcresult`, `build/GameplayPolish-Compact-Verified.xcresult`, `build/GameplayPolish-CorrectFeedback.xcresult`, and `build/GameplayPolish-FinalUnits.xcresult`, with exported screenshots in matching `*-images` folders.

No live database reset, manual migration, configuration overwrite, or second API process was used. Normal integration tests create their own ordinary profiles/challenges through the API. The full backend/browser suites and hosted Supabase/PostgreSQL integration were not rerun for this native presentation change.
