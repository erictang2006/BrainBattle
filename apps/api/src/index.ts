import { config } from 'dotenv';
import { resolve } from 'node:path';
import { openDatabase, projectRoot } from '@brain/db';
import { createApp } from './app.js';
config({ path: `${projectRoot}.env` });
const production = process.env.NODE_ENV === 'production';
if (production && !process.env.DATABASE_URL) throw new Error('Production requires DATABASE_URL.');
const database = await openDatabase({
  url: process.env.DATABASE_URL,
  directory: resolve(projectRoot, process.env.PGLITE_DIRECTORY ?? '.data/brain-battle'),
});
const { app } = await createApp({
  db: database.db,
  secret: process.env.SESSION_SECRET ?? 'local-development-only-change-before-deploying',
  origin: process.env.WEB_ORIGIN ?? 'http://localhost:3000',
  production,
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseKey: process.env.SUPABASE_ANON_KEY,
  logger: true,
});
await app.listen({ port: Number(process.env.PORT ?? 4000), host: process.env.HOST ?? '127.0.0.1' });
for (const signal of ['SIGTERM', 'SIGINT'])
  process.once(signal, async () => {
    await app.close();
    await database.close();
    process.exit(0);
  });
