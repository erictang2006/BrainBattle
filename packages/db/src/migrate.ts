import { config } from 'dotenv';
import { resolve } from 'node:path';
import { openDatabase, projectRoot } from './index.js';
config({ path: `${projectRoot}.env` });
const database = await openDatabase({
  url: process.env.DATABASE_URL,
  directory: resolve(projectRoot, process.env.PGLITE_DIRECTORY ?? '.data/brain-battle'),
});
await database.close();
console.log('All pending migrations applied.');
