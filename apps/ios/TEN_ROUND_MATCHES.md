# Five- and ten-round Counting Boxes

Native Solo Practice, friend challenges, live 1v1 and Party Mode offer a **5 / 10
rounds** selector. Five remains the default. Ten rounds use:

| Rounds | Difficulty | Cubes | Viewing time |
| --- | --- | --- | --- |
| 1–3 | Easy | 3–5 | 3 seconds |
| 4–7 | Medium | 6–10 | 2.5 seconds |
| 8–10 | Hard | 11–16 | 2 seconds |

Answers remain untimed. Correct answers retain the existing 1,000 points plus up
to 500 for speed; cube-by-cube reveals remain available in every native mode.

Ten rounds use immutable **rules version 4**, composed from the existing difficulty
settings and scoring. Versions 1–3 and existing five-round matches are unchanged.
The server selects version 4 when `roundCount: 10` is requested, generates all
private seeds, validates submissions and controls progression. Async matches
derive their length from persisted round rows; live rooms retain their length in
the existing JSON aggregate. Invitations, final results, draft restoration and
rematches handle ten rounds. Native progress indicators use two rows of five.

Deployment requires the updated API and additive migration
`packages/db/migrations/0004_ten_rounds.sql`. It widens the existing round-number
constraint to ten and deletes no data. The database opener applies pending
migrations on startup, or run `npm run db:migrate` with the intended existing
environment. Do not run a second process against an open embedded database.
No migration was applied to production and no push/deployment was performed.

For local testing, restart the existing local API, open the BrainBattle scheme
in Xcode, run Debug, and select **10 rounds** on Home/Games or in Play Live.
Release builds need the updated Render backend before using ten rounds.

Regression coverage is in `tests/ten-rounds.test.ts`: deterministic generation,
3/4/3 progression, untimed scoring, native HTTP invitation redemption, all ten
async rounds, five-round compatibility and round bounds, ten-round duel/party
completion, authorized reveals and rematch length. The native creation smoke
`NativeBetaUITests.testLocalTenRoundOptions` uses a separate in-memory API on port
4014, not production. It checks ten-round Solo and Party creation rather than
playing ten rounds in the UI; full ten-round progression is tested on the server.

Validation completed: **44 backend tests, 33 native unit/integration tests, and
one Simulator creation smoke passed**. Typechecking and the unsigned iPhone
Release build passed. Initial checks caught a stale five-round bounds assertion,
a Swift share-text function-reference mismatch, and a live rematch that selected
five-round rules; those were fixed before the final passing runs. Physical-device
testing was not performed. Logs: `/tmp/brain-ten-{tests-final,swift-final,ui,types-final,release}.log`.
