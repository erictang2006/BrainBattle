/** Isolated local native test API. Uses an in-memory DB; never reads production or .env. */
import { openDatabase } from '@brain/db';
import { createApp } from '../apps/api/src/app.js';
const database = await openDatabase();
const { app } = await createApp({
  db: database.db,
  secret: 'isolated-visual-memory-simulator-test-secret',
  origin: 'http://127.0.0.1:4016',
});
await app.listen({ host: '127.0.0.1', port: 4016 });
process.stdout.write('Isolated Visual Memory test API listening on 4016\n');
async function close() {
  await app.close();
  await database.close();
}
process.on('SIGTERM', () => {
  void close();
});
process.on('SIGINT', () => {
  void close();
});
