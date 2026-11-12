# Local development database recovery — November 6, 2026

During native integration work, a second API process was started before detecting that the existing API was already listening on port 4000. Both instances opened the original PGlite NodeFS directory. The local store subsequently failed to reopen with an invalid WAL checkpoint. This was an implementation-session mistake, not a required migration for iOS.

The original `.data/brain-battle` directory was **not reset or deleted**. A full preserved copy also remains at `.data/recovery-backup-20261106-original`. Recovery was performed only on independent copies under `/private/tmp`, using the proposed upstream PostgreSQL 17 PGlite WAL-recovery utility from [PGlite PR #994](https://github.com/electric-sql/pglite/pull/994).

Recovered rows were exported and logically imported into a newly initialized database at `.data/brain-battle-restored-20261106`:

| Table    | Rows recovered |
| -------- | -------------: |
| profiles |             10 |
| matches  |              9 |
| rounds   |             45 |
| attempts |             23 |

The import passed all schema foreign keys, unique constraints and checks. Every recovered match has five rounds, and no recovered attempt belongs to a nonparticipant. The local `.env` now selects the new store with `PGLITE_DIRECTORY=.data/brain-battle-restored-20261106`; other environment settings were retained. The existing API watcher recovered and serves this store. Neither schema nor game rules changed as part of recovery.

This verifies the recovered rows' structural consistency, **not completeness of the damaged WAL**. Recent uncheckpointed writes may be absent, including integration-test matches created during this session. Keep the original and backup for any further recovery investigation. Do not reset them or replace them with an empty database.

The database connector now takes an exclusive, PID-owned local-directory lock before opening persistent PGlite storage. A second API or migration process is rejected before touching the store. Locks from exited processes can be reclaimed; the persistence test verifies duplicate opens are rejected and a clean close/reopen preserves data. Socket.IO is closed in Fastify's `preClose` hook to drain connections before backend shutdown.

PostgreSQL deployments continue to use their existing server/transaction concurrency and do not use this local filesystem lock. This recovery was specific to the local PGlite store.
