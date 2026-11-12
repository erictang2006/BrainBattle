import { expect, test, type Page } from '@playwright/test';
import type { MatchView, Puzzle } from '@brain/shared';

test('two independent guests complete the challenge, with desktop and mobile layouts', async ({
  browser,
}) => {
  const desktop = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  const phone = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
  });
  const a = await desktop.newPage(),
    b = await phone.newPage();
  const errors: string[] = [];
  for (const page of [a, b]) page.on('pageerror', (e) => errors.push(e.message));
  await a.goto('/');
  await expect(a.getByRole('heading', { name: 'Small games. Big brain energy.' })).toBeVisible();
  await a.screenshot({ path: 'test-results/home-desktop.png', fullPage: true });
  await b.goto('/');
  await expect(b.getByRole('heading', { name: 'Small games. Big brain energy.' })).toBeVisible();
  await b.screenshot({ path: 'test-results/home-mobile.png', fullPage: true });
  expect(await b.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  );
  await a.getByRole('button', { name: 'Challenge a friend', exact: true }).click();
  await expect(a.getByRole('heading', { name: 'Counting Boxes', exact: true })).toBeVisible();
  const matchUrl = a.url();
  const puzzles: Puzzle[] = [];
  async function play(page: Page, isHost: boolean) {
    for (let round = 1; round <= 5; round++) {
      const responsePromise = page.waitForResponse(
        (r) => r.url().endsWith(`/rounds/${round}/start`) && r.request().method() === 'POST',
      );
      await page.getByRole('button', { name: `Start round ${round}`, exact: true }).click();
      const started = (await (await responsePromise).json()) as MatchView;
      const puzzle = started.rounds[round - 1].puzzle!;
      expect(puzzle?.cubes.length).toBeGreaterThan(0);
      if (isHost) puzzles.push(puzzle);
      else expect(puzzle).toEqual(puzzles[round - 1]);
      await expect(page.locator('canvas')).toBeVisible();
      if (round === 1) {
        await page.waitForTimeout(350); // Allow the first WebGL frame to reach the screenshot.
        await page.screenshot({
          path: `test-results/game-${isHost ? 'desktop' : 'mobile'}.png`,
          fullPage: true,
        });
        // A refresh retrieves the original clock and puzzle instead of granting more time.
        await page.reload();
        // The original display deadline remains in force after reloading.
      }
      await page.getByRole('button', { name: 'Type Answer', exact: true }).click();
      const input = page.getByLabel('YOUR CUBE COUNT');
      await expect(input).toBeVisible({ timeout: 12_000 });
      await input.fill(String(puzzle.cubes.length));
      await page.getByRole('button', { name: 'Done', exact: true }).click();
      if (round < 5) {
        await expect(page.getByRole('heading', { name: 'You’ve got a good eye.' })).toBeVisible();
        await page.getByRole('button', { name: 'Next round' }).click();
      }
    }
  }
  await play(a, true);
  await expect(a.getByRole('heading', { name: 'Your score is set.' })).toBeVisible();
  const invitation = await a.getByLabel('Challenge invitation link').inputValue();
  await b.goto(invitation);
  await b.getByRole('button', { name: 'Challenge accepted', exact: true }).click();
  await expect(b.getByRole('heading', { name: 'Counting Boxes', exact: true })).toBeVisible();
  await play(b, false);
  await expect(b.getByRole('heading', { name: 'The results are in.' })).toBeVisible();
  await expect(a.getByRole('heading', { name: 'The results are in.' })).toBeVisible({
    timeout: 8000,
  });
  expect(await b.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(
    true,
  );
  await a.screenshot({ path: 'test-results/results-desktop.png', fullPage: true });
  await b.screenshot({ path: 'test-results/results-mobile.png', fullPage: true });
  const final = await a.request.get(new URL(matchUrl).pathname.replace('/match/', '/api/matches/'));
  expect((await final.json()).complete).toBe(true);
  await a.getByRole('button', { name: 'Create a rematch' }).click();
  await expect(a).not.toHaveURL(matchUrl);
  await expect(a.getByRole('button', { name: 'Start round 1', exact: true })).toBeVisible();
  expect(errors).toEqual([]);
  await desktop.close();
  await phone.close();
});
