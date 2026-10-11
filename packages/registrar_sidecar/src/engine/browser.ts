import { chromium, Page, BrowserContext } from 'patchright';
import { generateRandomProfile, Profile } from './profile';
import { TaskConfig, AccountRecord } from '../types/index';
import { getPhoneNumber, waitForSMSCode } from './sms/smsActivate';
import { fetchMicrosoftCode, ImapConfig } from './email/qqMailImap';
import { ProxyInfo } from './proxy/types';
import { randInt, randomSleep, humanType, humanClick, humanScroll, pick } from './helpers';
import { USER_AGENTS, VIEWPORTS, LOCALE_TZ_PAIRS, generateHTTPHeaders, buildStealthScript } from './stealth';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// ──────────────────────────────────────────────────────────────
// Failure type classification
// ──────────────────────────────────────────────────────────────

export type FailureType =
  | 'proxy_unavailable'    // 代理API返回400/无法连接
  | 'page_blank'           // 页面空白（可能被风控拦截）
  | 'page_blocked'         // 明确的风控封锁页面
  | 'captcha_failed'       // 验证码未解出
  | 'network_error'        // 网络超时/DNS解析失败
  | 'timeout'              // 注册流程超时
  | 'unknown';             // 未知错误

export interface FailureInfo {
  type: FailureType;
  message: string;
  retryable: boolean;
  shouldStopAll: boolean; // true = 停止所有worker（如代理key过期）
}

/**
 * Classify an error into a FailureType with retry/stop recommendations.
 */
export function classifyFailure(error: any, page?: Page | null): FailureInfo {
  const msg = (error?.message || String(error)).toLowerCase();

  // Proxy-related errors
  if (msg.includes('400') || msg.includes('invalid_key') || msg.includes('invalid_parameter')) {
    return {
      type: 'proxy_unavailable',
      message: '代理API Key无效或已过期，请检查配置',
      retryable: false,
      shouldStopAll: true
    };
  }
  if (msg.includes('econnrefused') || msg.includes('econnreset') || msg.includes('proxy') && msg.includes('fail')) {
    return {
      type: 'proxy_unavailable',
      message: '代理服务器连接失败',
      retryable: true,
      shouldStopAll: false
    };
  }

  // Network errors
  if (msg.includes('enotfound') || msg.includes('etimedout') || msg.includes('network') || msg.includes('dns')) {
    return {
      type: 'network_error',
      message: '网络连接错误',
      retryable: true,
      shouldStopAll: false
    };
  }

  // Page state errors
  if (msg.includes('blank') || msg.includes('空白') || msg.includes('页面未加载')) {
    return {
      type: 'page_blank',
      message: '页面未正常加载（可能被风控拦截）',
      retryable: true,
      shouldStopAll: false
    };
  }

  if (msg.includes('封锁') || msg.includes('blocked') || msg.includes('creation blocked')) {
    return {
      type: 'page_blocked',
      message: 'Microsoft 风控封锁',
      retryable: true,
      shouldStopAll: false
    };
  }

  // Captcha errors
  if (msg.includes('验证码') || msg.includes('captcha') || msg.includes('arkose')) {
    return {
      type: 'captcha_failed',
      message: '验证码未成功解出',
      retryable: true,
      shouldStopAll: false
    };
  }

  // Timeout
  if (msg.includes('timeout') || msg.includes('超时') || msg.includes('未到达成功状态')) {
    return {
      type: 'timeout',
      message: '注册流程超时',
      retryable: true,
      shouldStopAll: false
    };
  }

  return {
    type: 'unknown',
    message: error?.message || '未知错误',
    retryable: true,
    shouldStopAll: false
  };
}

/**
 * Detect blank or error pages early by checking page content.
 */
async function detectPageState(
  page: Page,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<'ok' | 'blank' | 'blocked' | 'error'> {
  try {
    const url = page.url();
    const title = await page.title().catch(() => '');
    const bodyText = await page.evaluate(() => document.body?.innerText?.trim() || '').catch(() => '');
    const bodyLength = bodyText.length;

    // Blank page detection
    if (bodyLength < 10 && !url.includes('signup.live.com')) {
      logCallback(`[PageState] 页面内容过少 (${bodyLength} chars)，URL: ${url}`, 'warn');
      return 'blank';
    }

    // Blocked page detection
    const blockedPatterns = [
      '已封锁', 'blocked', '封鎖', '访问被拒绝', 'access denied',
      'too many requests', '请稍后再试', 'try again later',
      'service unavailable', '503', '429'
    ];
    const lowerBody = bodyText.toLowerCase();
    for (const pattern of blockedPatterns) {
      if (lowerBody.includes(pattern)) {
        logCallback(`[PageState] 检测到拦截页面: "${pattern}"`, 'warn');
        return 'blocked';
      }
    }

    // Error page detection
    if (title.toLowerCase().includes('error') || title.toLowerCase().includes('错误')) {
      logCallback(`[PageState] 检测到错误页面: "${title}"`, 'warn');
      return 'error';
    }

    return 'ok';
  } catch (e) {
    return 'ok';
  }
}

/**
 * Saves a full-page error screenshot to ~/Desktop/error_screenshots/
 * whenever an exception or risk block occurs during registration.
 */
async function saveErrorScreenshot(
  page: Page | null,
  email: string,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<void> {
  if (!page || page.isClosed()) return;
  try {
    const saveDir = path.join(os.homedir(), 'Desktop', 'error_screenshots');
    if (!fs.existsSync(saveDir)) {
      fs.mkdirSync(saveDir, { recursive: true });
    }
    const ts = new Date().toISOString().replace(/[:.]/g, '-');
    const safeEmail = email.replace(/[@.]/g, '_');
    const savePath = path.join(saveDir, `error_${safeEmail}_${ts}.png`);
    await page.screenshot({ path: savePath, fullPage: true });
    logCallback(`📸 异常界面截图已成功保存至桌面: ${savePath}`, 'warn');
  } catch (err: any) {
    logCallback(`保存异常截图失败: ${err?.message || err}`, 'warn');
  }
}

// ──────────────────────────────────────────────────────────────
// Arkose / FunCaptcha press-and-hold handler
// ──────────────────────────────────────────────────────────────

/**
 * Searches all frames (including deeply nested subframes) for PerimeterX / Arkose /
 * FunCaptcha verification buttons or "Press and hold" elements and executes simulated long press.
 *
 * PerimeterX captcha pattern: press once, hold for 5s, release, wait for confirmation,
 * then press again if prompted. Multiple attempts may be needed.
 */
async function tryPressAndHoldCaptcha(
  page: Page,
  workerId: number,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<boolean> {
  // Wait for PerimeterX frames to load (about:blank subframes need time to render)
  let aboutBlankCount = 0;
  for (let wait = 0; wait < 5; wait++) {
    aboutBlankCount = page.frames().filter(f => f.url() === 'about:blank').length;
    if (aboutBlankCount >= 2) break;
    await page.waitForTimeout(2000);
  }
  logCallback(`Worker #${workerId}: 帧数: ${page.frames().length} (about:blank: ${aboutBlankCount})`, 'info');

  // Find the hsprotect.net iframe and inspect its #px-captcha element
  const pxFrame = page.frames().find(f => f.url().includes('hsprotect'));
  if (pxFrame) {
    const pxInfo = await pxFrame.evaluate(() => {
      const el = document.getElementById('px-captcha');
      if (!el) return { found: false as const, innerHTML: '', childCount: 0, rect: { x: 0, y: 0, w: 0, h: 0 } };
      return {
        found: true as const,
        innerHTML: el.innerHTML.substring(0, 1000),
        childCount: el.children.length,
        rect: (() => { const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; })(),
      };
    }).catch(() => ({ found: false, innerHTML: '', childCount: 0, rect: { x: 0, y: 0, w: 0, h: 0 } }));
    logCallback(`Worker #${workerId}: #px-captcha: found=${pxInfo.found} children=${pxInfo.childCount} innerHTML=${(pxInfo.innerHTML || '').substring(0, 200)}`, 'info');
  } else {
    logCallback(`Worker #${workerId}: 未找到 hsprotect iframe`, 'warn');
  }

  logCallback(`Worker #${workerId}: 🎯 使用 CDP 鼠标事件 + 微动模拟执行 Press and hold...`, 'info');

  // Diagnostic: dump all iframe positions on the main page
  const iframePositions = await page.evaluate(() => {
    const iframes = document.querySelectorAll('iframe');
    return Array.from(iframes).map((iframe, i) => {
      const r = iframe.getBoundingClientRect();
      return `[${i}] src=${iframe.src || '(empty)'} (${Math.round(r.x)},${Math.round(r.y)}) ${Math.round(r.width)}x${Math.round(r.height)}`;
    });
  }).catch(() => []);
  logCallback(`Worker #${workerId}: 主页 iframe 列表: ${iframePositions.join(' | ')}`, 'info');

  const cdp = await page.context().newCDPSession(page);

  for (let attempt = 1; attempt <= 8; attempt++) {
    const holdTime = randInt(8000, 12000);
    logCallback(`Worker #${workerId}: 第 ${attempt} 次按压 (hold=${holdTime}ms)...`, 'info');

    // Primary: search about:blank frames for the PerimeterX button
    // The button is a <p> with cursor:pointer, text "Press and hold", inside an about:blank frame
    // Use elementHandle.boundingBox() which returns main-page viewport coords (frame-aware).
    let btnBox: { x: number; y: number; width: number; height: number } | null = null;
    let btnHandle: any = null;
    for (const frame of page.frames()) {
      if (frame.url() !== 'about:blank') continue;
      try {
        const allEls = await frame.$$('p, span, div, button, a').catch(() => []);
        for (const e of allEls) {
          const info = await e.evaluate((elem: Element) => {
            const text = (elem.textContent || '').trim();
            if (!text.toLowerCase().includes('hold') && !text.toLowerCase().includes('press')) return null;
            if (text.length > 40) return null;
            const cs = getComputedStyle(elem);
            return {
              text: text.substring(0, 60),
              tag: elem.tagName.toLowerCase(),
              cursor: cs.cursor,
              w: Math.round(elem.getBoundingClientRect().width),
              h: Math.round(elem.getBoundingClientRect().height),
            };
          }).catch(() => null);
          if (info && info.w > 30 && info.h > 10 && info.h < 80) {
            // boundingBox() returns main-page viewport coordinates (handles frame offsets)
            btnBox = await e.boundingBox().catch(() => null);
            btnHandle = e;
            if (btnBox) {
              logCallback(`Worker #${workerId}: 找到按钮 <${info.tag}> "${info.text}" 视口(${Math.round(btnBox.x)},${Math.round(btnBox.y)}) ${Math.round(btnBox.width)}x${Math.round(btnBox.height)} cursor=${info.cursor}`, 'info');
            }
            break;
          }
        }
        if (btnBox) break;
      } catch (e) {}
    }

    // Fallback: search hsprotect iframe for #px-captcha (boundingBox returns main-page coords)
    if (!btnBox) {
      const hf = page.frames().find(f => f.url().includes('hsprotect'));
      if (hf) {
        const pxCapEl = await hf.$('#px-captcha').catch(() => null);
        if (pxCapEl) {
          btnBox = await pxCapEl.boundingBox().catch(() => null);
          if (btnBox) {
            logCallback(`Worker #${workerId}: #px-captcha 坐标 (${Math.round(btnBox.x)},${Math.round(btnBox.y)}) ${Math.round(btnBox.width)}x${Math.round(btnBox.height)}`, 'info');
          }
        }
      }
    }

    // Last resort: find instruction text and click below it
    if (!btnBox) {
      for (const frame of page.frames()) {
        try {
          const allEls = await frame.$$('*').catch(() => []);
          for (const el of allEls) {
            const text = await el.evaluate((e: Element) => (e.textContent || '').trim()).catch(() => '');
            if (text.toLowerCase().includes('press and hold the button')) {
              const box = await el.boundingBox().catch(() => null);
              if (box && box.width > 50) {
                btnBox = { x: box.x, y: box.y + box.height + 10, width: box.width, height: 40 };
                logCallback(`Worker #${workerId}: 基于提示文本定位 (${Math.round(btnBox.x)},${Math.round(btnBox.y)}) ${Math.round(btnBox.width)}x${Math.round(btnBox.height)}`, 'info');
                break;
              }
            }
          }
          if (btnBox) break;
        } catch (e) {}
      }
    }

    if (!btnBox || btnBox.width === 0) {
      logCallback(`Worker #${workerId}: 未找到按钮，跳过本次按压`, 'warn');
      await page.waitForTimeout(randInt(3000, 5000));
      continue;
    }

    const cx = btnBox.x + btnBox.width / 2;
    const cy = btnBox.y + btnBox.height / 2;
    logCallback(`Worker #${workerId}: 目标坐标 (${Math.round(cx)},${Math.round(cy)}) size=${Math.round(btnBox.width)}x${Math.round(btnBox.height)}`, 'info');

    // Strategy 1: Use Playwright's element click with delay (handles frame routing automatically)
    // This is the most reliable approach — Playwright resolves frame offsets internally
    if (btnHandle) {
      try {
        logCallback(`Worker #${workerId}: 使用 Playwright element.click({ delay: ${holdTime} }) 按压...`, 'info');

        // Move mouse naturally to the button first
        const steps = randInt(5, 8);
        const startX = cx + randInt(-200, 200);
        const startY = cy + randInt(-150, 150);
        for (let s = 0; s <= steps; s++) {
          const t = s / steps;
          const ease = t * t * (3 - 2 * t);
          const mx = startX + (cx - startX) * ease + randInt(-2, 2);
          const my = startY + (cy - startY) * ease + randInt(-2, 2);
          await cdp.send('Input.dispatchMouseEvent', {
            type: 'mouseMoved', x: mx, y: my, button: 'none',
          });
          await page.waitForTimeout(randInt(20, 60));
        }

        // Playwright click with delay holds mousedown for the specified duration
        await btnHandle.click({ delay: holdTime, timeout: holdTime + 5000 });
        logCallback(`Worker #${workerId}: element.click 完成, 等待验证结果...`, 'info');
      } catch (clickErr) {
        logCallback(`Worker #${workerId}: element.click 失败: ${clickErr}, 回退到 CDP...`, 'warn');

        // Fallback: CDP mouse events with corrected viewport coordinates
        await cdp.send('Input.dispatchMouseEvent', {
          type: 'mousePressed', x: cx, y: cy, button: 'left', clickCount: 1,
        });
        logCallback(`Worker #${workerId}: mousePressed (CDP), 保持按住 ${holdTime}ms...`, 'info');

        const moveInterval = randInt(80, 150);
        const holdMoves = Math.floor(holdTime / moveInterval);
        for (let m = 0; m < holdMoves; m++) {
          await page.waitForTimeout(moveInterval);
          await cdp.send('Input.dispatchMouseEvent', {
            type: 'mouseMoved',
            x: cx + (Math.random() * 4 - 2),
            y: cy + (Math.random() * 4 - 2),
            button: 'left',
          });
        }
        const remaining = holdTime - holdMoves * moveInterval;
        if (remaining > 0) await page.waitForTimeout(remaining);

        await cdp.send('Input.dispatchMouseEvent', {
          type: 'mouseReleased', x: cx, y: cy, button: 'left', clickCount: 1,
        });
        logCallback(`Worker #${workerId}: mouseReleased (CDP), 等待验证结果...`, 'info');
      }
    } else {
      // No element handle — use CDP directly with viewport coords from boundingBox()
      logCallback(`Worker #${workerId}: 使用 CDP 鼠标事件按压...`, 'info');

      const steps = randInt(5, 8);
      const startX = cx + randInt(-200, 200);
      const startY = cy + randInt(-150, 150);
      for (let s = 0; s <= steps; s++) {
        const t = s / steps;
        const ease = t * t * (3 - 2 * t);
        const mx = startX + (cx - startX) * ease + randInt(-2, 2);
        const my = startY + (cy - startY) * ease + randInt(-2, 2);
        await cdp.send('Input.dispatchMouseEvent', {
          type: 'mouseMoved', x: mx, y: my, button: 'none',
        });
        await page.waitForTimeout(randInt(20, 60));
      }

      await cdp.send('Input.dispatchMouseEvent', {
        type: 'mousePressed', x: cx, y: cy, button: 'left', clickCount: 1,
      });
      logCallback(`Worker #${workerId}: mousePressed, 保持按住 ${holdTime}ms (含微动)...`, 'info');

      const moveInterval = randInt(80, 150);
      const holdMoves = Math.floor(holdTime / moveInterval);
      for (let m = 0; m < holdMoves; m++) {
        await page.waitForTimeout(moveInterval);
        await cdp.send('Input.dispatchMouseEvent', {
          type: 'mouseMoved',
          x: cx + (Math.random() * 4 - 2),
          y: cy + (Math.random() * 4 - 2),
          button: 'left',
        });
      }
      const remaining = holdTime - holdMoves * moveInterval;
      if (remaining > 0) await page.waitForTimeout(remaining);

      await cdp.send('Input.dispatchMouseEvent', {
        type: 'mouseReleased', x: cx, y: cy, button: 'left', clickCount: 1,
      });
      logCallback(`Worker #${workerId}: mouseReleased, 等待验证结果...`, 'info');
    }

    await page.waitForTimeout(randInt(3000, 5000));

    const title = await page.title().catch(() => '');
    logCallback(`Worker #${workerId}: 当前标题: "${title}"`, 'info');
    if (title.includes('blocked') || title.includes('封鎖')) {
      logCallback(`Worker #${workerId}: ⚠️ Microsoft 风控封锁`, 'warn');
      await cdp.detach().catch(() => {});
      return false;
    }
    if (!title.includes('prove') && !title.includes('human') && !title.includes('验证')) {
      logCallback(`Worker #${workerId}: ✅ 验证码验证完成！`, 'success');
      await cdp.detach().catch(() => {});
      return true;
    }
  }

  await cdp.detach().catch(() => {});
  logCallback(`Worker #${workerId}: 多轮按压后仍在验证页面`, 'warn');
  return false;
}

// ──────────────────────────────────────────────────────────────
// Recovery email binding (post-registration)
// ──────────────────────────────────────────────────────────────

async function bindRecoveryEmail(
  page: Page,
  config: TaskConfig,
  workerId: number,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void,
  registeredEmail?: string
): Promise<string> {
  if (!config.recoveryEmail || !config.imapAuth) {
    logCallback(`Worker #${workerId}: 未配置恢复邮箱或 IMAP 授权码，跳过绑定`, 'info');
    return '';
  }

  const maxWait = 120000; // 2 分钟超时
  const startTime = Date.now();

  try {
    logCallback(`Worker #${workerId}: 🔗 开始绑定安全邮箱 ${config.recoveryEmail}...`, 'info');

    // 等待页面加载稳定
    await page.waitForTimeout(3000);

    // 处理可能出现的隐私协议 / Personal data export consent 页面
    // 尝试多种选择器匹配 Continue 按钮
    const continueSelectors = [
      'button:has-text("Continue")',
      'button:has-text("继续")',
      '#acceptButton',
      'input[value="Continue"]',
      'input[value="继续"]',
      'a:has-text("Continue")',
      'a:has-text("继续")',
      '#idBtn_Background',
      'button#idBtn_Background',
    ];

    let clickedContinue = false;
    for (const selector of continueSelectors) {
      try {
        const btn = await page.$(selector);
        if (btn && await btn.isVisible().catch(() => false)) {
          const btnText = await btn.textContent().catch(() => selector);
          logCallback(`Worker #${workerId}: 检测到协议/隐私页面，点击 "${btnText}"...`, 'info');
          await btn.click().catch(() => {});
          clickedContinue = true;
          await page.waitForTimeout(5000); // 等待页面跳转
          break;
        }
      } catch {
        // 忽略选择器错误
      }
    }

    // 检测当前页面状态
    let url = page.url();
    let bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 1500) || '').catch(() => '');

    logCallback(`Worker #${workerId}: 当前页面: ${url}`, 'info');
    logCallback(`Worker #${workerId}: 页面文本(前300字): ${bodyText.substring(0, 300)}`, 'info');

    // 如果点击 Continue 后页面还没跳转，再等待
    if (clickedContinue && !bodyText.includes('email') && !bodyText.includes('邮箱') && !url.includes('proofs')) {
      logCallback(`Worker #${workerId}: 等待页面跳转...`, 'info');
      await page.waitForTimeout(5000);
      url = page.url();
      bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 1500) || '').catch(() => '');
      logCallback(`Worker #${workerId}: 跳转后页面: ${url}`, 'info');
      logCallback(`Worker #${workerId}: 跳转后文本(前300字): ${bodyText.substring(0, 300)}`, 'info');
    }

    // 检查是否需要再次点击 Continue（有些页面有多层确认）
    if (!bodyText.includes('email') && !bodyText.includes('邮箱') && !url.includes('proofs')) {
      for (const selector of continueSelectors) {
        try {
          const btn = await page.$(selector);
          if (btn && await btn.isVisible().catch(() => false)) {
            logCallback(`Worker #${workerId}: 再次检测到 Continue 按钮，点击...`, 'info');
            await btn.click().catch(() => {});
            await page.waitForTimeout(5000);
            break;
          }
        } catch {
          // 忽略
        }
      }
    }

    // 重新获取页面状态
    url = page.url();
    bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 1500) || '').catch(() => '');
    logCallback(`Worker #${workerId}: 最终页面: ${url}`, 'info');
    logCallback(`Worker #${workerId}: 最终文本(前300字): ${bodyText.substring(0, 300)}`, 'info');

    // 检查是否在恢复邮箱页面
    const isOnRecoveryPage = bodyText.includes('email address') || bodyText.includes('邮箱地址') ||
      bodyText.includes('recovery') || bodyText.includes('proofs') || url.includes('proofs');

    if (!isOnRecoveryPage) {
      // 不在恢复邮箱页面，尝试导航
      logCallback(`Worker #${workerId}: 当前不在恢复邮箱页面，尝试导航...`, 'info');
      await page.goto('https://account.live.com/proofs/Add', { waitUntil: 'domcontentloaded', timeout: 15000 }).catch(() => {});
      await page.waitForTimeout(5000);

      // 重新检测页面
      url = page.url();
      bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 1500) || '').catch(() => '');
      logCallback(`Worker #${workerId}: 导航后页面: ${url}`, 'info');
      logCallback(`Worker #${workerId}: 导航后文本(前300字): ${bodyText.substring(0, 300)}`, 'info');

      // 可能又出现 Continue 按钮
      for (const selector of continueSelectors) {
        try {
          const btn = await page.$(selector);
          if (btn && await btn.isVisible().catch(() => false)) {
            logCallback(`Worker #${workerId}: 导航后检测到 Continue 按钮，点击...`, 'info');
            await btn.click().catch(() => {});
            await page.waitForTimeout(5000);
            break;
          }
        } catch {
          // 忽略
        }
      }

      // 再次获取页面状态
      url = page.url();
      bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 1500) || '').catch(() => '');
      logCallback(`Worker #${workerId}: 再次导航后页面: ${url}`, 'info');
      logCallback(`Worker #${workerId}: 再次导航后文本(前300字): ${bodyText.substring(0, 300)}`, 'info');
    }

    // 查找并填写安全邮箱输入框
    // 尝试多种选择器，包括 Microsoft 特有的 input 布局
    const emailInputSelectors = [
      'input[type="email"]',
      'input[name="proofEmail"]',
      'input[name="email"]',
      'input[placeholder*="email"]',
      'input[placeholder*="Email"]',
      'input[placeholder*="邮箱"]',
      'input[aria-label*="email"]',
      'input[aria-label*="Email"]',
      'input[type="text"]',
    ];

    let emailInput = null;
    for (const selector of emailInputSelectors) {
      try {
        const input = await page.$(selector);
        if (input && await input.isVisible().catch(() => false)) {
          emailInput = input;
          logCallback(`Worker #${workerId}: 使用选择器 "${selector}" 找到邮箱输入框`, 'info');
          break;
        }
      } catch {
        // 忽略
      }
    }

    if (emailInput) {
      // 检查输入框当前值
      const currentValue = await emailInput.inputValue().catch(() => '');
      logCallback(`Worker #${workerId}: 找到邮箱输入框，当前值: "${currentValue}"，填写 ${config.recoveryEmail}...`, 'info');

      // 清空并填写恢复邮箱
      await emailInput.click().catch(() => {});
      await page.waitForTimeout(500);
      await emailInput.fill('').catch(() => {});
      await page.waitForTimeout(300);
      await page.keyboard.type(config.recoveryEmail, { delay: randInt(50, 120) });
      await page.waitForTimeout(500);

      // 点击下一步 - 尝试多种按钮选择器
      const nextBtnSelectors = [
        'button[type="submit"]',
        'input[type="submit"]',
        'button:has-text("Next")',
        'button:has-text("下一步")',
        'button:has-text("Send")',
        'button:has-text("发送")',
        'button:has-text("Verify")',
        'button:has-text("验证")',
        'button:has-text("Continue")',
        'button:has-text("继续")',
        '#idBtn_Background',
        'input[id="idBtn_Background"]',
      ];

      let nextBtn = null;
      for (const selector of nextBtnSelectors) {
        try {
          const btn = await page.$(selector);
          if (btn && await btn.isVisible().catch(() => false)) {
            nextBtn = btn;
            logCallback(`Worker #${workerId}: 使用选择器 "${selector}" 找到下一步按钮`, 'info');
            break;
          }
        } catch {
          // 忽略
        }
      }

      if (nextBtn) {
        const btnText = await nextBtn.textContent().catch(() => '');
        logCallback(`Worker #${workerId}: 点击按钮: "${btnText}"`, 'info');
        await nextBtn.click().catch(() => {});
        logCallback(`Worker #${workerId}: 已提交邮箱，等待验证码输入页面...`, 'info');
        await page.waitForTimeout(5000);
      } else {
        logCallback(`Worker #${workerId}: 未找到下一步按钮`, 'warn');
        await page.screenshot({ path: `/Users/simon/Desktop/recovery_email_debug_${workerId}.png` }).catch(() => {});
      }
    } else {
      logCallback(`Worker #${workerId}: 未找到邮箱输入框，当前页面可能不是恢复邮箱设置页面`, 'warn');
      // 截图以便调试
      await page.screenshot({ path: `/Users/simon/Desktop/recovery_email_debug_${workerId}.png` }).catch(() => {});
      return '';
    }

    // 查找验证码输入框
    const codeInputSelectors = [
      'input[name="code"]',
      'input[name="verificationCode"]',
      'input[placeholder*="code"]',
      'input[placeholder*="Code"]',
      'input[placeholder*="验证码"]',
      'input[aria-label*="code"]',
      'input[aria-label*="Code"]',
      'input[type="text"]',
      'input[type="number"]',
    ];

    let codeInput = null;
    for (const selector of codeInputSelectors) {
      try {
        const input = await page.$(selector);
        if (input && await input.isVisible().catch(() => false)) {
          codeInput = input;
          logCallback(`Worker #${workerId}: 使用选择器 "${selector}" 找到验证码输入框`, 'info');
          break;
        }
      } catch {
        // 忽略
      }
    }

    if (!codeInput) {
      logCallback(`Worker #${workerId}: 未找到验证码输入框，当前页面: ${page.url()}`, 'warn');
      // 截图以便调试
      await page.screenshot({ path: `/Users/simon/Desktop/recovery_code_debug_${workerId}.png` }).catch(() => {});
      return '';
    }

    logCallback(`Worker #${workerId}: 验证码输入框已出现，开始从 QQ 邮箱收取验证码...`, 'info');

    // 通过 IMAP 从 QQ 邮箱收取验证码
    const imapConfig: ImapConfig = {
      server: config.imapServer,
      port: config.imapPort,
      user: config.imapUser,
      auth: config.imapAuth,
    };

    const remainingTime = Math.max(1, Math.floor((maxWait - (Date.now() - startTime)) / 1000));
    const code = await fetchMicrosoftCode(imapConfig, Math.min(remainingTime, 60), registeredEmail);

    if (!code) {
      logCallback(`Worker #${workerId}: 未能从 QQ 邮箱获取验证码`, 'warn');
      return '';
    }

    logCallback(`Worker #${workerId}: 获取到验证码: ${code}，正在填写...`, 'info');

    // 填写验证码
    await codeInput.click().catch(() => {});
    await page.waitForTimeout(300);
    await codeInput.fill('').catch(() => {});
    await page.keyboard.type(code, { delay: randInt(50, 120) });
    await page.waitForTimeout(500);

    // 提交验证码
    const submitBtnSelectors = [
      'button[type="submit"]',
      'input[type="submit"]',
      'button:has-text("Next")',
      'button:has-text("下一步")',
      'button:has-text("Verify")',
      'button:has-text("验证")',
      'button:has-text("Confirm")',
      'button:has-text("确认")',
      'button:has-text("Submit")',
      'button:has-text("提交")',
      '#idBtn_Background',
    ];

    let submitBtn = null;
    for (const selector of submitBtnSelectors) {
      try {
        const btn = await page.$(selector);
        if (btn && await btn.isVisible().catch(() => false)) {
          submitBtn = btn;
          logCallback(`Worker #${workerId}: 使用选择器 "${selector}" 找到提交按钮`, 'info');
          break;
        }
      } catch {
        // 忽略
      }
    }

    if (submitBtn) {
      await submitBtn.click().catch(() => {});
      logCallback(`Worker #${workerId}: 已提交验证码，等待验证结果...`, 'info');
      await page.waitForTimeout(5000);
    } else {
      logCallback(`Worker #${workerId}: 未找到提交按钮`, 'warn');
    }

    // 检查是否绑定成功
    const finalUrl = page.url();
    const finalBody = await page.evaluate(() => document.body?.innerText?.substring(0, 500) || '').catch(() => '');

    if (finalBody.includes('success') || finalBody.includes('成功') || finalBody.includes('added') ||
        finalUrl.includes('proofs') || finalUrl.includes('security')) {
      logCallback(`Worker #${workerId}: ✅ 安全邮箱绑定成功！`, 'success');
      return config.recoveryEmail;
    }

    logCallback(`Worker #${workerId}: 安全邮箱绑定状态不确定，当前页面: ${finalUrl}`, 'warn');
    return config.recoveryEmail; // 乐观返回，因为验证码已提交

  } catch (err) {
    logCallback(`Worker #${workerId}: 安全邮箱绑定异常: ${err}`, 'warn');
    return '';
  }
}

// ──────────────────────────────────────────────────────────────
// Main registration function
// ──────────────────────────────────────────────────────────────

export async function runSingleRegistration(
  workerId: number,
  config: TaskConfig,
  proxy: ProxyInfo | undefined,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<AccountRecord> {
  const profile: Profile = generateRandomProfile(config.targetDomain);
  const fullEmail = `${profile.emailPrefix}@${config.targetDomain}`;
  const nowStr = new Date().toLocaleString('zh-CN');

  logCallback(`Worker #${workerId}: 开始尝试注册 ${fullEmail}...`, 'info');

  // Randomize browser environment per registration attempt
  const userAgent = pick(USER_AGENTS);
  const viewport = pick(VIEWPORTS);
  const localeTz = pick(LOCALE_TZ_PAIRS);

  let context: BrowserContext | null = null;
  let page: Page | null = null;
  let browser: any = null;
  try {

    const launchOptions: any = {
      headless: false,
      args: [
        '--no-sandbox',
        '--disable-blink-features=AutomationControlled',
        '--disable-infobars',
        '--no-first-run',
        `--window-size=${viewport.width},${viewport.height}`,
      ]
    };

    if (proxy) {
      const proxyUrl = config.proxyConfig.mode === 'subscription'
        ? 'http://127.0.0.1:6160'
        : `http://${proxy.host}:${proxy.port}`;
      logCallback(`Worker #${workerId}: 使用代理服务器 ${proxyUrl}`, 'info');
      launchOptions.proxy = {
        server: proxyUrl,
        username: proxy.username || undefined,
        password: proxy.password || undefined
      };
    }

    browser = await chromium.launch(launchOptions);

    context = await browser.newContext({
      viewport,
      userAgent,
      locale: localeTz.locale,
      timezoneId: localeTz.tz,
      extraHTTPHeaders: generateHTTPHeaders(userAgent, localeTz.locale),
      colorScheme: 'light',
      deviceScaleFactor: pick([1, 1, 2]),
    });

    page = await context!.newPage();

    // Inject comprehensive stealth overrides (with locale for fingerprint consistency)
    await page.addInitScript(buildStealthScript(userAgent, localeTz.locale));

    logCallback(`Worker #${workerId}: 正在打开 https://signup.live.com/ (UA: ...${userAgent.slice(-30)})...`, 'info');
    await page.goto('https://signup.live.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await randomSleep(page, 1200, 2500);

    // Early page state detection
    const pageState = await detectPageState(page, logCallback);
    if (pageState === 'blank') {
      throw new Error('页面空白：页面未正常加载，可能被风控拦截或代理不可用');
    }
    if (pageState === 'blocked') {
      throw new Error('风控拦截：检测到访问被拒绝或服务不可用页面');
    }
    if (pageState === 'error') {
      throw new Error('页面错误：检测到错误页面');
    }

    // Simulate human reading: small scroll on initial page load
    await humanScroll(page);

    const buttonSelector = 'button[type="submit"], button[data-testid="primaryButton"], input[type="submit"], button#iSignupAction';

    let captchaSolvedOrBypassed = false;
    let registeredSuccess = false;
    let recoveryEmailPrompt = false;

    // Adaptive step loop (handles changing Microsoft UI order dynamically)
    for (let step = 1; step <= 15; step++) {
      if (!context || page.isClosed()) break;

      // Periodic page state check (every 3 steps)
      if (step % 3 === 0) {
        const midState = await detectPageState(page, logCallback);
        if (midState === 'blank' || midState === 'blocked' || midState === 'error') {
          throw new Error(`流程中检测到异常页面状态: ${midState} (step ${step})`);
        }
      }

      // 1. Check CAPTCHA / Enforcement Frame (Arkose, FunCaptcha, PerimeterX/hsprotect)
      // Search across all frames for captcha indicators
      let hasCaptchaIframe = false;
      let hasCaptchaText = false;

      for (const frame of page.frames()) {
        try {
          // Check for captcha iframes
          const iframeEl = await frame.$('iframe[src*="arkoselabs"], iframe[src*="funcaptcha"], iframe[title*="Verification"], iframe[src*="hsprotect"], #enforcementFrame, #px-captcha').catch(() => null);
          if (iframeEl) {
            const isVisible = await iframeEl.isVisible().catch(() => false);
            if (isVisible) {
              hasCaptchaIframe = true;
              break;
            }
          }

          // Check for captcha text in this frame
          const frameText = await frame.evaluate(() => document.body?.innerText || '').catch(() => '');
          const lowerFrameText = frameText.toLowerCase();
          if (lowerFrameText.includes('press and hold') || lowerFrameText.includes('按住') ||
              lowerFrameText.includes('prove you') || lowerFrameText.includes('human challenge') ||
              lowerFrameText.includes('verify you')) {
            hasCaptchaText = true;
            logCallback(`Worker #${workerId}: 在帧中检测到验证码文本: "${frameText.substring(0, 100).trim()}"`, 'info');
            break;
          }
        } catch (e) {}
      }

      if (hasCaptchaIframe || hasCaptchaText) {
        logCallback(`Worker #${workerId}: 检测到人机验证组件，使用物理长按...`, 'warn');
        const holdResult = await tryPressAndHoldCaptcha(page, workerId, logCallback);
        captchaSolvedOrBypassed = holdResult;

        await randomSleep(page, 2500, 4000);
        continue;
      }

      // 2. Check Email input
      const emailInput = await page.$('input[name="email"], input[name="MemberName"], input[type="email"]');
      if (emailInput && await emailInput.isVisible()) {
        const val = await emailInput.inputValue();
        if (!val) {
          logCallback(`Worker #${workerId}: 模拟真人步调填写邮箱: ${fullEmail}`, 'info');
          await humanType(page, 'input[name="email"], input[name="MemberName"], input[type="email"]', fullEmail);
          await randomSleep(page, 400, 900);
          await humanClick(page, buttonSelector);
          await randomSleep(page, 2000, 3500);
          continue;
        }
      }

      // 3. Check Password input
      const pwdInput = await page.$('input[name="Password"], input[type="password"]');
      if (pwdInput && await pwdInput.isVisible()) {
        const val = await pwdInput.inputValue();
        if (!val) {
          logCallback(`Worker #${workerId}: 模拟真人步调设置强密码...`, 'info');
          await humanType(page, 'input[name="Password"], input[type="password"]', profile.password);
          await randomSleep(page, 300, 700);

          const iOptin = await page.$('input[name="iOptinEmail"], input[name="marketingOptIn"]');
          if (iOptin && await iOptin.isChecked()) {
            await iOptin.uncheck();
          }

          await randomSleep(page, 200, 500);
          await humanClick(page, buttonSelector);
          await randomSleep(page, 2000, 3500);
          continue;
        }
      }

      // 4. Check Birthdate
      const yearInput = await page.$('input[name="BirthYear"], input#BirthYear');
      if (yearInput && await yearInput.isVisible()) {
        const val = await yearInput.inputValue();
        if (!val) {
          logCallback(`Worker #${workerId}: 正在选择生日出生年月 (${profile.birthDate.year}-${profile.birthDate.month}-${profile.birthDate.day})...`, 'info');

          const monthEl = await page.$('button[name="BirthMonth"], #BirthMonthDropdown, label[for="BirthMonthDropdown"]');
          if (monthEl) {
            await humanClick(page, 'button[name="BirthMonth"], #BirthMonthDropdown, label[for="BirthMonthDropdown"]');
            await randomSleep(page, 300, 600);
            const options = await page.$$('div[role="option"], option');
            if (options.length > profile.birthDate.month) {
              await options[profile.birthDate.month].click({ force: true });
            }
          } else {
            const monthSelect = await page.$('select[name="BirthMonth"], select#BirthMonth');
            if (monthSelect) await monthSelect.selectOption(String(profile.birthDate.month));
          }

          await randomSleep(page, 200, 500);

          const dayEl = await page.$('button[name="BirthDay"], #BirthDayDropdown, label[for="BirthDayDropdown"]');
          if (dayEl) {
            await humanClick(page, 'button[name="BirthDay"], #BirthDayDropdown, label[for="BirthDayDropdown"]');
            await randomSleep(page, 300, 600);
            const dayOptions = await page.$$('div[role="option"], option');
            if (dayOptions.length > profile.birthDate.day) {
              await dayOptions[profile.birthDate.day].click({ force: true });
            }
          } else {
            const daySelect = await page.$('select[name="BirthDay"], select#BirthDay');
            if (daySelect) await daySelect.selectOption(String(profile.birthDate.day));
          }

          await randomSleep(page, 150, 400);
          await yearInput.focus();
          for (const ch of String(profile.birthDate.year)) {
            await page.keyboard.type(ch, { delay: 0 });
            await page.waitForTimeout(randInt(40, 200));
          }
          await randomSleep(page, 300, 700);
          await humanClick(page, buttonSelector);
          await randomSleep(page, 2000, 3500);
          continue;
        }
      }

      // 5. Check Names
      const fnInput = await page.$('input[name="firstNameInput"], input[name="FirstName"], input[id*="firstName"]');
      if (fnInput && await fnInput.isVisible()) {
        const val = await fnInput.inputValue();
        if (!val) {
          logCallback(`Worker #${workerId}: 模拟真人步调填写姓名 (${profile.firstName} ${profile.lastName})...`, 'info');
          await humanType(page, 'input[name="firstNameInput"], input[name="FirstName"], input[id*="firstName"]', profile.firstName);

          await randomSleep(page, 200, 500);

          const lnInput = await page.$('input[name="lastNameInput"], input[name="LastName"], input[id*="lastName"]');
          if (lnInput) {
            await humanType(page, 'input[name="lastNameInput"], input[name="LastName"], input[id*="lastName"]', profile.lastName);
          }

          await randomSleep(page, 400, 800);
          await humanClick(page, buttonSelector);
          await randomSleep(page, 2000, 3500);
          continue;
        }
      }

      // 6. Check Phone SMS
      const phoneInput = await page.$('input[name="PhoneNumber"], input[name="phoneInput"], #phoneInput');
      if (phoneInput && await phoneInput.isVisible()) {
        logCallback(`Worker #${workerId}: 检测到手机号 SMS 验证页面...`, 'warn');
        if (config.smsApiKey) {
          const order = await getPhoneNumber(config.smsApiKey, config.smsCountry);
          if (order) {
            logCallback(`Worker #${workerId}: 获取到接码号码 ${order.phone}，填入页面...`, 'info');
            await phoneInput.fill(order.phone);
            await randomSleep(page, 300, 600);
            await humanClick(page, 'input[type="submit"], #sendCode, button[type="submit"]');

            const code = await waitForSMSCode(config.smsApiKey, order.id, 60);
            if (code) {
              logCallback(`Worker #${workerId}: 接收到 SMS 验证码 ${code}，自动填入...`, 'success');
              await page.fill('input[name="PhoneCode"], #smsCode, input[type="text"]', code);
              await randomSleep(page, 200, 500);
              await humanClick(page, buttonSelector);
              await randomSleep(page, 1500, 2500);
              continue;
            } else {
              throw new Error('接码超时：未收到 SMS 验证码');
            }
          } else {
            throw new Error('SMS 接码平台无法分配到可用手机号');
          }
        } else {
          throw new Error('需要手机号验证，但系统未配置 SMS API Key');
        }
      }

      // 7. Check if Microsoft Risk Control Blocked Account
      const blockedText = await page.evaluate(() => {
        const text = document.body?.innerText || '';
        return text.includes('blocked') || text.includes('封鎖') || text.includes('已封锁');
      }).catch(() => false);

      if (blockedText) {
        logCallback(`Worker #${workerId}: ⚠️ 检测到 Microsoft 风控封锁页面，将保存截图并由 Worker 自动切换代理重试。`, 'warn');
        await saveErrorScreenshot(page, fullEmail, logCallback);
        await context.close().catch(() => {});
        return {
          id: Math.random().toString(36).substring(2, 10),
          email: fullEmail,
          password: profile.password,
          firstName: profile.firstName,
          lastName: profile.lastName,
          birthDate: `${profile.birthDate.year}-${profile.birthDate.month}-${profile.birthDate.day}`,
          proxyUsed: proxy ? `${proxy.host}:${proxy.port}` : '直连',
          status: 'FAILED',
          createdAt: nowStr,
          errorLog: 'Microsoft 风控封锁：已封锁建立账户 (Account creation blocked)'
        };
      }

      // 8. Check Stay signed in / Redirected Success
      const staySignedIn = await page.$('#acceptButton, input[value="Yes"], button:has-text("Yes"), input[value="是"]');
      if (staySignedIn && await staySignedIn.isVisible()) {
        await staySignedIn.click();
        registeredSuccess = true;
        break;
      }

      const url = page.url();
      if (url.includes('account.microsoft.com') || url.includes('outlook.live.com') ||
          url.includes('privacynotice') || url.includes('account.live.com')) {
        registeredSuccess = true;
        break;
      }

      // Also check body text for success indicators
      const bodyText = await page.evaluate(() => document.body?.innerText?.substring(0, 500) || '').catch(() => '');
      if (bodyText.includes('protect your account') || bodyText.includes('protecte') ||
          bodyText.includes('Welcome') || bodyText.includes('欢迎')) {
        registeredSuccess = true;
        break;
      }
      // Recovery email prompt is also a success signal, but we want to bind it
      if (bodyText.includes('recovery email') || bodyText.includes('recovery phone')) {
        registeredSuccess = true;
        recoveryEmailPrompt = true;
        break;
      }

      await randomSleep(page, 1000, 2000);
    }

    if (!registeredSuccess) {
      throw new Error('注册流程未到达成功状态（未能检测到保持登录页面或成功重定向，可能卡在未解出的验证码或异常阶段）');
    }

    logCallback(`Worker #${workerId}: 恭喜！${fullEmail} 账号自动化注册流程顺利完成！`, 'success');

    // 等待注册后页面加载（可能是隐私协议、recovery email 设置等）
    await page.waitForTimeout(5000);

    // 检测当前页面是否是 recovery email 设置页面
    let boundRecoveryEmail = '';
    if (config.recoveryEmail && config.imapAuth) {
      const postUrl = page.url();
      const postBody = await page.evaluate(() => document.body?.innerText?.substring(0, 1000) || '').catch(() => '');
      logCallback(`Worker #${workerId}: 注册后页面: ${postUrl}`, 'info');

      // 检测 recovery email 相关页面
      const isRecoveryPage = postBody.includes('recovery email') || postBody.includes('recovery phone') ||
        postBody.includes('protect your account') || postBody.includes('protecte') ||
        postUrl.includes('proofs') || postUrl.includes('recovery') || postUrl.includes('security');

      if (isRecoveryPage) {
        logCallback(`Worker #${workerId}: 检测到安全邮箱设置页面，开始绑定...`, 'info');
        boundRecoveryEmail = await bindRecoveryEmail(page, config, workerId, logCallback, fullEmail);
      } else {
        logCallback(`Worker #${workerId}: 当前页面不是安全邮箱设置页面，尝试导航到安全设置...`, 'info');
        boundRecoveryEmail = await bindRecoveryEmail(page, config, workerId, logCallback, fullEmail);
      }
    }

    await context?.close().catch(() => {});
    await browser?.close().catch(() => {});

    let verified: boolean | undefined;
    let verifiedAt: string | undefined;
    if (config.verifyAfterRegister) {
      logCallback(`Worker #${workerId}: 注册成功，正在验证账号...`, 'info');
      const proxyUrl = config.proxyConfig.mode === 'subscription'
        ? 'http://127.0.0.1:6160'
        : (proxy ? `http://${proxy.host}:${proxy.port}` : undefined);
      const { verifyAccount } = await import('./verifyAccount');
      const result = await verifyAccount(fullEmail, profile.password, proxyUrl, logCallback);
      verified = result.success;
      verifiedAt = new Date().toISOString();
      if (result.success) {
        logCallback(`Worker #${workerId}: 账号验证成功 ✓`, 'success');
      } else {
        logCallback(`Worker #${workerId}: 账号验证失败: ${result.reason}`, 'warn');
      }
    }

    return {
      id: Math.random().toString(36).substring(2, 10),
      email: fullEmail,
      password: profile.password,
      firstName: profile.firstName,
      lastName: profile.lastName,
      birthDate: `${profile.birthDate.year}-${profile.birthDate.month}-${profile.birthDate.day}`,
      recoveryEmail: boundRecoveryEmail || undefined,
      proxyUsed: proxy ? `${proxy.host}:${proxy.port}` : '直连',
      status: 'SUCCESS',
      createdAt: nowStr,
      verified,
      verifiedAt,
    };
  } catch (err: any) {
    await saveErrorScreenshot(page, fullEmail, logCallback);
    if (context) await context.close().catch(() => {});
    await browser?.close().catch(() => {});

    const failureInfo = classifyFailure(err, page);
    logCallback(`Worker #${workerId}: 注册过程出现异常 [${failureInfo.type}]: ${failureInfo.message}`, 'error');

    // Provide actionable error messages
    let actionableMessage = failureInfo.message;
    if (failureInfo.type === 'page_blocked') {
      actionableMessage = 'Microsoft 风控封锁：验证码通过但后端检测到自动化浏览器。建议：1) 使用代理更换IP 2) 增加注册间隔 3) 使用非headless模式';
    } else if (failureInfo.type === 'captcha_failed') {
      actionableMessage = '验证码未解出：PerimeterX Press and hold 验证码需要物理交互。建议：1) 检查验证码截图 2) 调整按压时长';
    }

    return {
      id: Math.random().toString(36).substring(2, 10),
      email: fullEmail,
      password: profile.password,
      firstName: profile.firstName,
      lastName: profile.lastName,
      birthDate: `${profile.birthDate.year}-${profile.birthDate.month}-${profile.birthDate.day}`,
      proxyUsed: proxy ? `${proxy.host}:${proxy.port}` : '直连',
      status: 'FAILED',
      createdAt: nowStr,
      errorLog: `[${failureInfo.type}] ${actionableMessage}: ${err.message}`
    };
  }
}
