import { Page } from 'patchright';

/** Random integer in [min, max] */
export function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/** Gaussian-ish random (Box-Muller, clamped to [min,max]) for natural variance */
export function gaussianDelay(mean: number, stddev: number, min: number, max: number): number {
  let u = 0, v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  let num = Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
  num = Math.round(mean + num * stddev);
  return Math.max(min, Math.min(max, num));
}

/** Sleep helper with random jitter */
export async function randomSleep(page: Page, minMs: number, maxMs: number): Promise<void> {
  await page.waitForTimeout(randInt(minMs, maxMs));
}

/** Pick a random element from an array */
export function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * Bezier curve point calculation for natural mouse movement.
 */
function bezierCurve(
  t: number,
  p0: { x: number; y: number },
  p1: { x: number; y: number },
  p2: { x: number; y: number },
  p3: { x: number; y: number }
): { x: number; y: number } {
  const u = 1 - t;
  const tt = t * t;
  const uu = u * u;
  const uuu = uu * u;
  const ttt = tt * t;
  return {
    x: uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x,
    y: uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y,
  };
}

/**
 * Move mouse along a bezier curve path for natural-looking movement.
 * Adds slight randomness to control points.
 */
export async function humanMouseMove(
  page: Page,
  fromX: number,
  fromY: number,
  toX: number,
  toY: number
): Promise<void> {
  const steps = randInt(15, 30);
  const midX = (fromX + toX) / 2 + randInt(-50, 50);
  const midY = (fromY + toY) / 2 + randInt(-30, 30);

  // Random control points for bezier curve
  const cp1 = {
    x: fromX + (midX - fromX) * 0.5 + randInt(-20, 20),
    y: fromY + (midY - fromY) * 0.5 + randInt(-20, 20),
  };
  const cp2 = {
    x: midX + (toX - midX) * 0.5 + randInt(-20, 20),
    y: midY + (toY - midY) * 0.5 + randInt(-20, 20),
  };

  const p0 = { x: fromX, y: fromY };
  const p3 = { x: toX, y: toY };

  for (let i = 0; i <= steps; i++) {
    const t = i / steps;
    const point = bezierCurve(t, p0, cp1, cp2, p3);
    await page.mouse.move(point.x, point.y);
    // Variable delay between steps (faster in middle, slower at start/end)
    const progress = i / steps;
    const speedFactor = Math.sin(progress * Math.PI); // Peak speed in middle
    const delay = Math.round(5 + (1 - speedFactor) * 15 + Math.random() * 5);
    await page.waitForTimeout(delay);
  }
}

/**
 * Type text with Gaussian-distributed per-character delays,
 * simulating natural typing rhythm with occasional micro-pauses.
 */
export async function humanType(page: Page, selector: string, text: string): Promise<void> {
  const el = await page.$(selector);
  if (!el) return;
  await el.focus();
  await page.waitForTimeout(randInt(100, 300));

  for (let i = 0; i < text.length; i++) {
    await page.keyboard.type(text[i], { delay: 0 });
    const charDelay = gaussianDelay(65, 25, 25, 180);
    await page.waitForTimeout(charDelay);

    // Occasional longer pauses (simulating thinking)
    if (Math.random() < 0.08) {
      await page.waitForTimeout(randInt(200, 600));
    }
  }
}

/**
 * Move mouse to element vicinity then click, simulating natural mouse behavior.
 * Uses bezier curve movement for realism.
 */
export async function humanClick(page: Page, selector: string): Promise<void> {
  const el = await page.$(selector);
  if (!el) {
    await page.click(selector).catch(() => {});
    return;
  }

  const box = await el.boundingBox();
  if (!box) {
    await el.click();
    return;
  }

  const targetX = box.x + box.width / 2 + randInt(-3, 3);
  const targetY = box.y + box.height / 2 + randInt(-3, 3);

  // Get current mouse position (approximate)
  const currentX = randInt(100, 500);
  const currentY = randInt(100, 400);

  // Move along bezier curve
  await humanMouseMove(page, currentX, currentY, targetX, targetY);
  await page.waitForTimeout(randInt(50, 150));
  await page.mouse.click(targetX, targetY);
}

/**
 * Simulate a small random scroll to mimic human reading behavior.
 */
export async function humanScroll(page: Page): Promise<void> {
  const scrollAmount = randInt(50, 200);
  await page.mouse.wheel(0, scrollAmount);
  await page.waitForTimeout(randInt(300, 800));
}
