import type { Profile } from '@brain/shared';
let sessionRequest: Promise<Profile> | null = null;
export function ensureSession() {
  sessionRequest ??= api<Profile>('/session', 'POST').finally(() => {
    sessionRequest = null;
  });
  return sessionRequest;
}
export async function api<T>(path: string, method = 'GET', body?: unknown): Promise<T> {
  const response = await fetch(`/api${path}`, {
    method,
    credentials: 'same-origin',
    cache: 'no-store',
    headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error ?? 'Something went wrong. Please try again.');
  return data as T;
}
