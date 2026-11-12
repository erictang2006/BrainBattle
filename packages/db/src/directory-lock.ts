import { open, readFile, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

/** PGlite NodeFS must never be opened by two OS processes at once. */
export async function lockDirectory(directory: string) {
  const path = `${directory}.brain-lock`;
  const owner = JSON.stringify({ pid: process.pid, nonce: randomUUID() });
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const file = await open(path, 'wx', 0o600);
      try {
        await file.writeFile(owner);
      } finally {
        await file.close();
      }
      return async () => {
        if ((await readFile(path, 'utf8').catch(() => null)) === owner) await unlink(path);
      };
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EEXIST') throw error;
      const existing = await readFile(path, 'utf8').catch(() => null);
      let pid: number | undefined;
      try {
        pid = JSON.parse(existing ?? '').pid;
      } catch {
        /* A partially written lock is occupied. */
      }
      if (pid && Number.isInteger(pid) && pid > 0) {
        try {
          process.kill(pid, 0);
        } catch (cause) {
          if (
            (cause as NodeJS.ErrnoException).code === 'ESRCH' &&
            (await readFile(path, 'utf8').catch(() => null)) === existing
          ) {
            await unlink(path).catch(() => undefined);
            continue;
          }
        }
      }
      throw new Error(
        `Local database is already in use (process ${pid ?? 'starting'}). Stop the existing API before opening ${directory}.`,
      );
    }
  }
  throw new Error('Could not acquire the local database lock.');
}
