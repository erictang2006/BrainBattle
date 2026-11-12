# Counting Boxes difficulty — proposal only

> Historical document. The current default is the implemented [Counting Boxes v2](COUNTING_BOXES_V2.md), with sparse 3–16-cube puzzles and faster timing. Its fixed five-round progression supersedes the earlier difficulty proposal; v1 behavior remains available for stored matches.

**Not implemented.** The native gameplay polish does not change puzzle generation, rules versions, scoring, deadlines, match creation, the database, or the web client.

## Current contract: preserve `counting-boxes@1`

Existing matches have five rounds, an 8-second display and a 12-second answer window. Footprints grow from 3×3 to 4×4 later in the match. The server stores each round's seed and each player's actual deadlines. Correct answers earn 1,000 points plus up to 500 for speed, measured from display end to server receipt. Wrong/expired answers earn zero. Existing completed results and unfinished attempts must retain these rules.

## Proposed new difficulty settings

These are initial playtesting targets, not calibrated guarantees:

| New setting | Approximate cubes |    Display |     Answer | Suggested geometry                           |
| ----------- | ----------------: | ---------: | ---------: | -------------------------------------------- |
| Easy        |              8–16 | 10 seconds | 12 seconds | Compact supported stacks, e.g. 2×3 footprint |
| Medium      |             18–30 |  7 seconds | 12 seconds | 3×3 footprint with more vertical structure   |
| Hard        |             32–55 |  5 seconds | 12 seconds | 4×4 footprint, taller supported stacks       |

Within each band, increase complexity over the five rounds. Keep every cube supported and hidden support inferable from the shared fixed camera. Avoid arbitrary occlusion, floating cubes, or visually indistinguishable puzzles. Validate that the target counts can actually be constructed under the chosen heightfield constraints.

Legacy v1 is **not** silently relabeled Medium: its 8-second display differs from the proposed 7 seconds. Easy/Medium/Hard would be explicit settings for new matches under a new rules version.

## Required server and contract work before shipping

1. **Register a new immutable version.** Keep the existing v1 generator and scorer available, including its deterministic fixtures. A v2 implementation would resolve difficulty to fixed, versioned generation parameters and display duration. Server-generated seeds remain private.
2. **Validate selection at match creation.** Extend the strict Zod create request with an allowed difficulty field for the new version. Do not accept arbitrary cube counts, durations, seeds, scores, or winners. The host's choice applies to both players and all five rounds; guests cannot downgrade their own attempt.
3. **Persist the selection.** Add an additive migration for match difficulty (or a similarly small versioned configuration). Existing rows remain legacy v1; avoid rewriting seeds, attempts, scores, or deadlines. Add checks/default handling so a stored match always resolves to the same rules. Extend the explicit migration runner and Drizzle schema together. No migration is needed for the current UI-only improvements.
4. **Derive timing on the server.** Replace the start operation's global display-duration lookup with a lookup from the stored game/version/difficulty. Store `displayUntil` and `deadline` once as today. Apply match-expiry clamping, sequential-round enforcement, timeout finalization, authorization, and duplicate-submit behavior exactly as before. Retrying or reconnecting must never restart a clock.
5. **Expose safe presentation metadata.** Return difficulty and authoritative display/answer duration metadata in public projections and invitation previews. Keep seeds/answers private and send render coordinates only in the player's display window. Clients must not guess new durations from their selected UI control.
6. **Keep scoring unchanged initially.** Retain the 12-second answer window and existing correct-answer formula in the new version unless a separately approved scoring design changes it. Do not alter v1's use of the global answer window. Scores remain comparable within a challenge because both players have the same settings; future aggregate rankings should separate difficulty rather than assume equal effort across modes.
7. **Update both clients deliberately.** Swift's current support guard only accepts v1. Add v2 support, safe metadata decoding, difficulty labels/selection, and countdown presentation together. Update TypeScript DTOs and web support with backward-compatible legacy defaults. Do not let an old client accidentally play unknown rules using v1 timing labels.
8. **Define rematches.** Prefer retaining the previous challenge's difficulty for a rematch, with fresh seeds and invitation. Validate it on the server; show any choice to change difficulty before creating the new match.

## Verification for a future rules release

- Retain v1 deterministic golden output and scoring tests unchanged.
- Test v2 determinism for every difficulty/round, reachable cube-count ranges, supported geometry, camera readability, and input bounds.
- Test both players receive identical puzzles/settings while keeping independent persisted clocks.
- Exercise old match resume and completed-history reads before and after the additive migration.
- Repeat expiry clamping, early/late submission, one-attempt, concurrent claim, idempotency, and authorization tests for v2.
- Verify iOS/web challenge interoperability, invitations/rematches, and that no seed or explicit answer appears in public payloads.
- Playtest on a small iPhone and real hardware before fixing the final count ranges and viewing times.

There is no native difficulty picker in this UI pass because a local-only selector would misrepresent the actual server rules.
