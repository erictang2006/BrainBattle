# Brain Battle

A playable Counting Boxes vertical slice: a guest creates a five-round challenge, plays, shares a single-use invitation, and a second guest plays the same puzzles. Both players receive the final comparison. Solo practice is also playable.

The native iOS client now lives in [`apps/ios`](apps/ios/README.md). It uses SwiftUI, native Core Animation 3D graphics, URLSession, and Keychain with the same Fastify game service. The existing web application remains available and interoperable with iOS challenges.

To let friends install and play on their iPhones, follow the [native-only TestFlight guide](TESTFLIGHT.md): the hosted API, native codes, Release configuration, signing and uploads. No website deployment is required for the iOS beta.

For a detailed implementation outline, architecture, API/database reference, teammate setup, validation history, and remaining work, see [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md).

For this workspace's local data-store recovery and preserved backups, see the [recovery note](apps/ios/RECOVERY-NOTE.md).

## Run locally

Requires Node.js 22+ and npm. No cloud services or Docker are required for local development.

```sh
npm install
cp .env.example .env
npm run db:migrate
npm run dev
```

Open **http://localhost:3000**. Fastify listens on `127.0.0.1:4000`; Next.js proxies `/api` and `/socket.io`. Use `localhost:3000`, matching `WEB_ORIGIN`, when opening the frontend.

To try the complete flow:

1. Choose **Challenge a friend**. Optionally edit your guest name from the home screen header.
2. Complete five rounds. New matches use sparse 5×5 v2 puzzles: rounds 1–2 have 3 seconds to observe and 6 to answer, rounds 3–4 have 2.5/6 seconds, and round 5 has 2/5 seconds. Count with +1 or type an answer. Existing v1 matches retain 8/12 seconds.
3. Copy the invitation link. Open it in a private window, another browser, or another device connected to a deployment. A second tab in the same browser uses the same guest identity.
4. Accept and complete the identical five puzzles. Both result screens update automatically. Rematch creates fresh puzzles and a fresh invitation.

Local profiles, matches, seeds, attempts, and deadlines persist in `.data/brain-battle`, an embedded PostgreSQL database powered by PGlite. Guest identity is stored in a signed, HttpOnly, SameSite cookie. Keep `.data` and `SESSION_SECRET` to retain local sessions; losing cookies loses access to an anonymous profile.

## Workspaces

| Directory         | Responsibility                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `apps/web`        | Next.js App Router, Tailwind CSS, responsive home/invitation/play/results screens, React Three Fiber renderer |
| `apps/api`        | Fastify routes, authentication, transactional challenge service, Socket.IO subscriptions                      |
| `packages/shared` | Zod request/event schemas, public DTOs, protocol constants                                                    |
| `packages/games`  | Pure, versioned mini-game interface, registry, seeded generator and scoring                                   |
| `packages/db`     | PostgreSQL schema, Drizzle connections, SQL migrations, local PGlite adapter                                  |
| `tests`           | Vitest engine/API/persistence tests and Playwright browser tests                                              |

Authoritative state lives in the database and game service. React state controls the current panel, shared counting/keypad draft, and countdown display. Neither React nor sockets decide scores or winners.

## Rules and fairness

- Default matches contain five Counting Boxes rounds, using `counting-boxes@2`. Stored `counting-boxes@1` matches retain their original generation, clocks, and scoring. Later games can register another rules implementation and renderer. Old rules versions must remain available for stored matches.
- The server generates a cryptographic random seed for each round. Both players receive the same deterministic cube coordinates. v2 uses sparse positions on a 5×5 grid, isolated cubes, small groups, and supported stacks; v1 retains the original rising heightfield.
- Seeds and explicit answer keys never appear in API responses or socket messages. Puzzle coordinates are sent only during that player's display window. The public score/winner fields are projections of stored attempts.
- Starting a round persists that player's display deadline and answer deadline. Retrying, refreshing, switching tabs, or reconnecting retrieves the original clock. A new round cannot start before the previous attempt is finalized.
- A correct answer scores 1,000 points plus up to 500 for speed, measured from the end of the display window to server receipt. Incorrect or expired attempts score zero. Network transit consumes part of the answer window.
- The `(match, round, player)` primary key enforces one attempt. Match row locks serialize start/submit/claim operations. Repeated submissions return the first finalized result, even if the retry body changes. Submission UUIDs cannot be reused in another round or match by the same player.
- A player's own result is shown after their attempt is final. An opponent's round result is revealed only after both corresponding attempts are final. Opponent totals and the winner appear only after all ten attempts are final. No answer key is released afterward either.
- Invitations contain 192 bits of randomness, can be claimed by one other player, and expire 48 hours after match creation. The match has the same expiry; starting late never extends it. Claim retries by the two existing participants reopen the match.
- Timeout finalization is lazy: the next authenticated read or action records a zero. No background scheduler is required. An expired match with unplayed rounds remains incomplete and declares no winner.
- Socket.IO authenticates the session, authorizes each watched match, and emits only `{ matchId }` invalidations. The browser then fetches its authorized projection. HTTP polling also refreshes results if the socket connection fails.

## PostgreSQL and Supabase

Set `DATABASE_URL` to use a PostgreSQL server instead of PGlite. For example:

```sh
docker run --name brain-battle-db -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=brain_battle -p 5432:5432 -d postgres:17
```

```dotenv
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/brain_battle
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-publishable-or-anon-key
SESSION_SECRET=replace-with-at-least-32-random-characters
```

Enable **anonymous sign-ins** in the Supabase Auth dashboard. With both Supabase values configured, the backend calls `signInAnonymously()`, verifies sessions using `getUser()`, and refreshes them through HttpOnly cookies. The same authentication verification accepts registered Supabase users, but account registration/linking UI is still an MVP task. The anon key is not a service-role key. Supabase may be used for Auth with either local PostgreSQL or Supabase-hosted PostgreSQL.

The database URL is a **backend-only** credential, for a database owner/service role that can run migrations and access the tables. RLS is enabled with no browser policies: these tables, particularly round seeds, are never accessed directly from the browser or through Supabase's data API. Keep all database credentials on the server.

`npm run db:migrate` applies `packages/db/migrations/0001_initial.sql`. Startup also applies pending migrations. A `brain_migrations` journal records version 1; migration execution is transactional, and external PostgreSQL migration runners are serialized by a journal-table lock. Keep applied SQL files immutable; add new versions to the runner for future changes. Drizzle's TypeScript schema defines the application's queries; SQL migrations also include foreign keys, checks, indexes, and RLS.

For a production smoke run after configuring real services:

```sh
npm run build
NODE_ENV=production npm start
```

The frontend uses Next.js's supported Webpack production builder. The backend runs TypeScript via `tsx`; runtime tooling is included in dependencies. Production startup refuses local development authentication, the default session secret, and an absent PostgreSQL URL. Deploy these two Node processes behind HTTPS on one public origin and forward `/api` and `/socket.io` to Fastify. This repository is a local/server deployment foundation; it is not published to Sites hosting, whose Worker runtime does not support this Fastify/PostgreSQL architecture.

## Environment variables

Copy `.env.example` to the repository root. The API and Next configuration load it directly.

| Variable            | Default / purpose                                                                                |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| `NODE_ENV`          | `development`; `production` enforces cloud Auth, PostgreSQL, a custom secret, and secure cookies |
| `PORT`              | `4000`, backend port; frontend uses port 3000                                                    |
| `HOST`              | `127.0.0.1`, backend bind address                                                                |
| `WEB_ORIGIN`        | `http://localhost:3000`; exact allowed browser origin and invitation base URL                    |
| `API_URL`           | `http://127.0.0.1:4000`; Next.js server-to-server proxy target, read during build/configuration  |
| `SESSION_SECRET`    | Development fallback only; use 32+ random characters and retain across restarts                  |
| `DATABASE_URL`      | Omit for local PGlite; set for PostgreSQL and all production runs                                |
| `PGLITE_DIRECTORY`  | Optional local-only directory relative to the repository root; defaults to `.data/brain-battle`  |
| `SUPABASE_URL`      | Supabase project URL; configure together with the anon/publishable key                           |
| `SUPABASE_ANON_KEY` | Supabase public anon/publishable key; anonymous sign-ins must be enabled                         |

No secrets use a `NEXT_PUBLIC_` variable. Never commit `.env` or `.data`.

## Validation

```sh
npm test                 # Vitest: engine, API, authorization, replay/concurrency, persistence
npm run typecheck        # Backend, packages, tests, frontend
npm run build            # Type checks and production Next.js build
# With npm run dev in another terminal and Google Chrome installed:
npm run test:browser     # Two-guest desktop/mobile flow and authenticated Socket.IO behavior
```

Playwright uses installed Google Chrome (`channel: 'chrome'`). If unavailable, install Chrome or change `playwright.config.ts` to use Playwright's Chromium and run `npx playwright install chromium`. Screenshots/traces are written under the ignored `test-results` directory. The full browser flow takes roughly 90 seconds because it uses real server deadlines. Vitest uses isolated PostgreSQL-compatible PGlite databases and a controlled server clock; it does not contact Supabase or a network PostgreSQL service.

## Remaining MVP work and limitations

- Native live 1v1 and 3–8-player Party Mode now support five Counting Boxes rounds, ready lobbies, synchronized starts, standings and rematches. See [live multiplayer architecture and testing](apps/ios/LIVE_MULTIPLAYER.md). The web client retains its existing async/solo experience; live web screens remain future work.
- Reaction Time and Sequence Memory, mixed-game scheduling, and game-specific renderers/scoring. This slice uses Counting Boxes in every round.
- Registered-account sign-up, guest-to-account linking, recovery, and cross-device profile access.
- Production Supabase and external PostgreSQL integration testing, deployment, monitoring, backups, and authentication abuse controls such as Supabase CAPTCHA.
- Rematches currently create another claimable challenge; they do not automatically enroll the previous opponent. Expired unfinished challenges have no winner or notification email.
- A browser puzzle necessarily contains renderable geometry. API answers/seeds are protected, but developer tools or automation can count rendered objects. This is a friendly competition foundation, not a cheat-proof ranked system.
- The renderer uses WebGL with an isometric SVG fallback. Normal gameplay uses a stationary isometric view without rotation controls. Screen-reader labels/navigation exist, but spatial Counting Boxes itself has no equivalent nonvisual game mode yet.
- Run one Fastify instance initially. Multiple instances would need shared rate limiting and a Socket.IO adapter; database attempt/claim locks already live in PostgreSQL.

Implementation references: [Next.js App Router](https://nextjs.org/docs/app), [Supabase anonymous sign-ins](https://supabase.com/docs/guides/auth/auth-anonymous), [Drizzle migrations](https://orm.drizzle.team/docs/migrations), [React Three Fiber](https://r3f.docs.pmnd.rs/getting-started/introduction).

Current fast-game rules, version compatibility, input behavior, and verification: [Counting Boxes v2](apps/ios/COUNTING_BOXES_V2.md).
