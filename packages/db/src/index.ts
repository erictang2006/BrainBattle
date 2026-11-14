import { PGlite } from '@electric-sql/pglite';
import { drizzle as embeddedDrizzle, type PgliteDatabase } from 'drizzle-orm/pglite';
import { drizzle as postgresDrizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { mkdir, readFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as schema from './schema.js';
import { lockDirectory } from './directory-lock.js';
export * from './schema.js';
export type Database = PgliteDatabase<typeof schema>;
export const projectRoot = fileURLToPath(new URL('../../../', import.meta.url));
const journal =
  'CREATE TABLE IF NOT EXISTS brain_migrations (version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())';
export async function openDatabase(options: { url?: string; directory?: string } = {}) {
  const migrations = await Promise.all(
    [
      '0001_initial.sql',
      '0002_live_rooms.sql',
      '0003_untimed_answers.sql',
      '0004_ten_rounds.sql',
    ].map(async (file, index) => ({
      version: index + 1,
      sql: await readFile(new URL(`../migrations/${file}`, import.meta.url), 'utf8'),
    })),
  );
  if (options.url) {
    const client = postgres(options.url, { max: 10, prepare: false });
    // Drizzle's query builder is shared; both drivers use the same PostgreSQL schema and SQL.
    const db = postgresDrizzle(client, { schema }) as unknown as Database;
    await client.unsafe(journal);
    await client.begin(async (tx) => {
      await tx.unsafe('LOCK TABLE brain_migrations IN EXCLUSIVE MODE');
      for (const migration of migrations) {
        const applied =
          await tx`SELECT version FROM brain_migrations WHERE version = ${migration.version}`;
        if (!applied.length) {
          await tx.unsafe(migration.sql);
          await tx`INSERT INTO brain_migrations (version) VALUES (${migration.version})`;
        }
      }
    });
    return { db, close: () => client.end() };
  }
  if (options.directory) await mkdir(dirname(options.directory), { recursive: true });
  const release = options.directory ? await lockDirectory(options.directory) : async () => {};
  const client = new PGlite(options.directory);
  try {
    await client.exec(journal);
    await client.transaction(async (tx) => {
      for (const migration of migrations) {
        const applied = await tx.query('SELECT version FROM brain_migrations WHERE version = $1', [
          migration.version,
        ]);
        if (!applied.rows.length) {
          await tx.exec(migration.sql);
          await tx.query('INSERT INTO brain_migrations (version) VALUES ($1)', [migration.version]);
        }
      }
    });
    return {
      db: embeddedDrizzle(client, { schema }),
      close: async () => {
        try {
          await client.close();
        } finally {
          await release();
        }
      },
    };
  } catch (error) {
    await release();
    throw error;
  }
}
