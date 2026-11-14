import { expect, it } from 'vitest';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { sql } from 'drizzle-orm';
import { openDatabase } from '@brain/db';
import { PGlite } from '@electric-sql/pglite';
import { LiveService } from '../apps/api/src/live-service.js';
import { GameService } from '../apps/api/src/service.js';
it('retains profile, puzzle and original deadlines across a database restart and runs migrations once', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'brain-battle-test-'));
  let database = await openDatabase({ directory: join(directory, 'postgres') });
  try {
    const playerId = randomUUID(),
      now = 1_800_000_000_000;
    const service = new GameService(database.db, 'http://localhost:3000', () => now);
    await expect(openDatabase({ directory: join(directory, 'postgres') })).rejects.toThrow(
      'already in use',
    );
    await service.profile(playerId);
    await service.rename(playerId, 'Persistent Player');
    const match = await service.create(playerId, 'challenge');
    const original = await service.start(match.id, playerId, 1);
    const live = new LiveService(database.db, () => now);
    const guest = randomUUID();
    await service.profile(guest);
    const room = await live.create(playerId);
    await live.join(room.code, guest);
    await live.watch(room.code, playerId, 'a');
    await live.watch(room.code, guest, 'b');
    for (const id of [playerId, guest])
      await live.command(room.code, id, { action: 'ready', ready: true });
    const originalLive = await live.command(room.code, playerId, { action: 'start' });
    await database.close();
    database = await openDatabase({ directory: join(directory, 'postgres') });
    const resumed = await new GameService(
      database.db,
      'http://localhost:3000',
      () => now + 1000,
    ).view(match.id, playerId);
    const restoredLive = await new LiveService(database.db, () => now + 1000).view(
      room.code,
      guest,
    );
    expect(restoredLive.round).toEqual(originalLive.round);
    expect(restoredLive.roundCount).toBe(5);
    expect(resumed.you.name).toBe('Persistent Player');
    expect(resumed.inviteUrl).toBe(original.inviteUrl);
    expect(resumed.rounds[0]).toEqual(original.rounds[0]);
    const journal = await database.db.execute(sql`SELECT version FROM brain_migrations`);
    expect(journal.rows).toEqual([{ version: 1 }, { version: 2 }, { version: 3 }, { version: 4 }]);
  } finally {
    await database.close();
    await rm(directory, { recursive: true, force: true });
  }
});

it('upgrades a v1 database additively without replacing existing profiles', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'brain-upgrade-test-'));
  const path = join(directory, 'postgres');
  const original = new PGlite(path);
  const player = randomUUID();
  try {
    await original.exec(
      await readFile(
        new URL('../packages/db/migrations/0001_initial.sql', import.meta.url),
        'utf8',
      ),
    );
    await original.exec(
      'CREATE TABLE brain_migrations(version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()); INSERT INTO brain_migrations(version) VALUES (1)',
    );
    await original.query('INSERT INTO profiles(id,name,created_at) VALUES ($1,$2,$3)', [
      player,
      'Original Player',
      123,
    ]);
  } finally {
    await original.close();
  }
  const upgraded = await openDatabase({ directory: path });
  try {
    const profile = await upgraded.db.execute(sql`SELECT name FROM profiles WHERE id = ${player}`);
    expect(profile.rows).toEqual([{ name: 'Original Player' }]);
    expect(
      (await upgraded.db.execute(sql`SELECT version FROM brain_migrations ORDER BY version`)).rows,
    ).toEqual([{ version: 1 }, { version: 2 }, { version: 3 }, { version: 4 }]);
    expect(
      (await upgraded.db.execute(sql`SELECT count(*)::int AS total FROM live_rooms`)).rows,
    ).toEqual([{ total: 0 }]);
  } finally {
    await upgraded.close();
    await rm(directory, { recursive: true, force: true });
  }
});
