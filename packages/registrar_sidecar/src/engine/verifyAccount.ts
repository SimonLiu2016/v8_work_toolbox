import { chromium, BrowserContext } from 'patchright';
import { pick } from './helpers';
import { USER_AGENTS, VIEWPORTS, LOCALE_TZ_PAIRS } from './stealth';

export interface VerifyResult {
  success: boolean;
  reason?: string;
}

export async function verifyAccount(
  email: string,
  password: string,
  proxyUrl?: string,
  logCallback?: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<VerifyResult> {
  const log = logCallback || (() => {});

  let browser: any = null;
  let context: BrowserContext | null = null;

  try {
    const userAgent = pick(USER_AGENTS);
    const viewport = pick(VIEWPORTS);
    const localeTz = pick(LOCALE_TZ_PAIRS);

    const launchOptions: any = {
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-blink-features=AutomationControlled',
        '--disable-infobars',
      ]
    };

    if (proxyUrl) {
      launchOptions.proxy = { server: proxyUrl };
    }

    browser = await chromium.launch(launchOptions);
    context = await browser.newContext({
      viewport,
      userAgent,
      locale: localeTz.locale,
      timezoneId: localeTz.tz,
      colorScheme: 'light',
    });

    const page = await context!.newPage();

    log('正在导航到 Outlook 登录页面...', 'info');
    await page.goto('https://outlook.live.com', { waitUntil: 'networkidle', timeout: 15000 });

    // Click sign in
    const signInBtn = page.locator('a:has-text("Sign in"), a:has-text("登录")');
    if (await signInBtn.count() > 0) {
      await signInBtn.first().click();
      await page.waitForTimeout(2000);
    }

    // Enter email
    const emailInput = page.locator('input[type="email"], input[name="loginfmt"]');
    await emailInput.waitFor({ timeout: 10000 });
    await emailInput.fill(email);
    await page.locator('input[type="submit"], #idSIButton9').click();
    await page.waitForTimeout(2000);

    // Enter password
    const passwordInput = page.locator('input[type="password"], input[name="passwd"]');
    if (await passwordInput.count() === 0) {
      const errorText = await page.locator('.otrm-error-msg, #usernameError').textContent().catch(() => '');
      if (errorText) {
        return { success: false, reason: errorText.trim() };
      }
      return { success: false, reason: '未找到密码输入框，可能账号不存在' };
    }

    await passwordInput.fill(password);
    await page.locator('input[type="submit"], #idSIButton9').click();
    await page.waitForTimeout(3000);

    // Check result
    const url = page.url();
    if (url.includes('owa') || url.includes('/mail') || url.includes('inbox')) {
      return { success: true };
    }

    // Check for errors
    const errorEl = page.locator('.otrm-error-msg, #passwordError, #resetPasswordError, .error-text');
    if (await errorEl.count() > 0) {
      const errorText = await errorEl.first().textContent().catch(() => '');
      return { success: false, reason: errorText?.trim() || '登录失败' };
    }

    // Check for "Stay signed in?" page
    const staySignedIn = page.locator('#idBtn_Background, button:has-text("Yes"), button:has-text("是")');
    if (await staySignedIn.count() > 0) {
      return { success: true };
    }

    return { success: false, reason: '登录后未进入邮箱主页' };
  } catch (err: any) {
    return { success: false, reason: err.message || '验证过程出错' };
  } finally {
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
  }
}
