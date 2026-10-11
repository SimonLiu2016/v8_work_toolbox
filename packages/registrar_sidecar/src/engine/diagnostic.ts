/**
 * 独立诊断工具 - 可单独运行测试代理、页面加载、验证码模块
 *
 * 使用方式:
 *   npx tsx electron/engine/diagnostic.ts
 *   npx tsx electron/engine/diagnostic.ts --proxy-only
 *   npx tsx electron/engine/diagnostic.ts --page-only
 */

import axios from 'axios';
import { chromium } from 'patchright';

// ──────────────────────────────────────────────────────────────
// Proxy Diagnosis
// ──────────────────────────────────────────────────────────────

interface ProxyDiagnosisResult {
  apiUrl: string;
  keyValid: boolean;
  paramsAccepted: boolean;
  proxyCount: number;
  rawResponse: string;
  error?: string;
}

export async function diagnoseProxy(
  apiUrl: string,
  authKey: string,
  authPwd: string,
  extractNum: number = 1
): Promise<ProxyDiagnosisResult> {
  console.log('\n═══════════════════════════════════════════════');
  console.log('  代理 API 诊断');
  console.log('═══════════════════════════════════════════════');
  console.log(`  API URL:  ${apiUrl}`);
  console.log(`  Auth Key: ${authKey ? authKey.substring(0, 4) + '***' : '(空)'}`);
  console.log(`  提取数量: ${extractNum}`);

  const result: ProxyDiagnosisResult = {
    apiUrl,
    keyValid: false,
    paramsAccepted: false,
    proxyCount: 0,
    rawResponse: ''
  };

  if (!apiUrl) {
    result.error = 'API URL 未配置';
    console.log(`  ❌ ${result.error}`);
    return result;
  }

  if (!authKey) {
    result.error = 'Auth Key 未配置';
    console.log(`  ❌ ${result.error}`);
    return result;
  }

  try {
    // Build URL with correct parameters
    const url = new URL(apiUrl);
    url.searchParams.set('key', authKey);
    url.searchParams.set('num', String(extractNum));
    url.searchParams.set('type', 'json');

    console.log(`  请求: GET ${url.pathname}?key=${authKey.substring(0, 4)}***&num=${extractNum}&type=json`);

    const response = await axios.get(url.toString(), {
      timeout: 10000,
      headers: { 'User-Agent': 'Mozilla/5.0' }
    });

    result.rawResponse = typeof response.data === 'string'
      ? response.data.substring(0, 500)
      : JSON.stringify(response.data).substring(0, 500);

    console.log(`  HTTP Status: ${response.status}`);
    console.log(`  Response: ${result.rawResponse}`);

    const data = response.data;

    if (data && typeof data === 'object') {
      // Check for API errors
      if (data.code && data.code !== 0 && data.code !== '0') {
        result.error = `API 错误: ${data.message || data.msg || data.code}`;
        result.keyValid = data.code !== 'INVALID_KEY';
        result.paramsAccepted = data.code !== 'INVALID_PARAMETER';
        console.log(`  ❌ ${result.error}`);
        console.log(`  Key 有效: ${result.keyValid}, 参数正确: ${result.paramsAccepted}`);
        return result;
      }

      result.keyValid = true;
      result.paramsAccepted = true;

      // Extract proxies
      let proxies: any[] = [];
      if (Array.isArray(data.data)) {
        proxies = data.data;
      } else if (Array.isArray(data)) {
        proxies = data;
      }

      result.proxyCount = proxies.length;
      if (proxies.length > 0) {
        console.log(`  ✅ 代理拉取成功！数量: ${proxies.length}`);
        proxies.forEach((p: any, i: number) => {
          console.log(`     [${i + 1}] ${p.ip}:${p.port}`);
        });
      } else {
        console.log(`  ⚠️ API 返回成功但未包含代理 IP`);
      }
    } else if (typeof data === 'string') {
      // Plain text format
      const lines = data.split('\n').filter((l: string) => l.trim());
      result.proxyCount = lines.length;
      result.keyValid = true;
      result.paramsAccepted = true;
      console.log(`  ✅ 代理拉取成功（纯文本格式）！数量: ${lines.length}`);
      lines.forEach((line: string, i: number) => {
        console.log(`     [${i + 1}] ${line.trim()}`);
      });
    }
  } catch (err: any) {
    const status = err.response?.status;
    const data = err.response?.data;
    result.error = err.message;

    if (status) {
      console.log(`  ❌ HTTP ${status}: ${err.message}`);
      if (data) {
        const detail = typeof data === 'string' ? data : JSON.stringify(data);
        console.log(`     响应: ${detail.substring(0, 300)}`);
      }
    } else {
      console.log(`  ❌ 请求失败: ${err.message}`);
    }
  }

  console.log('═══════════════════════════════════════════════\n');
  return result;
}

// ──────────────────────────────────────────────────────────────
// Page Loading Diagnosis
// ──────────────────────────────────────────────────────────────

interface PageDiagnosisResult {
  url: string;
  loaded: boolean;
  title: string;
  bodyLength: number;
  hasForm: boolean;
  hasCaptcha: boolean;
  pageState: 'ok' | 'blank' | 'blocked' | 'error';
  error?: string;
}

export async function diagnosePage(
  proxyHost?: string,
  proxyPort?: number,
  proxyUser?: string,
  proxyPass?: string
): Promise<PageDiagnosisResult> {
  console.log('\n═══════════════════════════════════════════════');
  console.log('  页面加载诊断');
  console.log('═══════════════════════════════════════════════');
  console.log(`  目标: https://signup.live.com/`);
  console.log(`  代理: ${proxyHost ? `${proxyHost}:${proxyPort}` : '直连'}`);

  const result: PageDiagnosisResult = {
    url: '',
    loaded: false,
    title: '',
    bodyLength: 0,
    hasForm: false,
    hasCaptcha: false,
    pageState: 'error'
  };

  let browser = null;
  try {
    const launchOptions: any = {
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-blink-features=AutomationControlled',
        '--disable-infobars',
        '--no-first-run',
      ]
    };

    if (proxyHost && proxyPort) {
      launchOptions.proxy = {
        server: `http://${proxyHost}:${proxyPort}`,
        username: proxyUser || undefined,
        password: proxyPass || undefined
      };
    }

    console.log('  启动浏览器...');
    browser = await chromium.launch(launchOptions);

    const context = await browser.newContext({
      viewport: { width: 1366, height: 768 },
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
      locale: 'en-US',
    });

    const page = await context.newPage();

    console.log('  加载页面...');
    await page.goto('https://signup.live.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3000);

    result.url = page.url();
    result.title = await page.title();
    result.bodyLength = await page.evaluate(() => document.body?.innerText?.length || 0);

    console.log(`  URL: ${result.url}`);
    console.log(`  Title: ${result.title}`);
    console.log(`  Body 长度: ${result.bodyLength} chars`);

    // Check for form elements
    result.hasForm = await page.$('input[name="email"], input[name="MemberName"], input[type="email"]') !== null;
    result.hasCaptcha = await page.$('iframe[src*="arkoselabs"], iframe[src*="funcaptcha"], iframe[title*="Verification"]') !== null;

    console.log(`  注册表单: ${result.hasForm ? '✅ 存在' : '❌ 未找到'}`);
    console.log(`  验证码: ${result.hasCaptcha ? '⚠️ 存在' : '✅ 未出现'}`);

    // Determine page state
    if (result.bodyLength < 10) {
      result.pageState = 'blank';
      console.log('  状态: ❌ 空白页面');
    } else {
      const bodyText = await page.evaluate(() => document.body?.innerText?.toLowerCase() || '');
      const blockedPatterns = ['已封锁', 'blocked', '封鎖', '访问被拒绝', 'access denied', 'too many requests'];
      if (blockedPatterns.some(p => bodyText.includes(p))) {
        result.pageState = 'blocked';
        console.log('  状态: ❌ 被风控拦截');
      } else {
        result.pageState = 'ok';
        result.loaded = true;
        console.log('  状态: ✅ 页面正常加载');
      }
    }

    // Save screenshot for inspection
    const screenshotPath = '/tmp/diagnostic_page.png';
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.log(`  截图: ${screenshotPath}`);

  } catch (err: any) {
    result.error = err.message;
    console.log(`  ❌ 诊断失败: ${err.message}`);
  } finally {
    if (browser) await browser.close().catch(() => {});
  }

  console.log('═══════════════════════════════════════════════\n');
  return result;
}

// ──────────────────────────────────────────────────────────────
// CLI Entry Point
// ──────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const proxyOnly = args.includes('--proxy-only');
  const pageOnly = args.includes('--page-only');

  console.log('╔═══════════════════════════════════════════════╗');
  console.log('║     Hotmail Auto-Registrar 诊断工具          ║');
  console.log('╚═══════════════════════════════════════════════╝');

  // Default test config (can be overridden by env vars)
  const apiUrl = process.env.PROXY_API_URL || 'https://share.proxy.qg.net/get';
  const authKey = process.env.PROXY_AUTH_KEY || '';
  const authPwd = process.env.PROXY_AUTH_PWD || '';

  if (!proxyOnly) {
    await diagnosePage();
  }

  if (!pageOnly) {
    await diagnoseProxy(apiUrl, authKey, authPwd);
  }

  console.log('诊断完成。');
}

// Run if executed directly
main().catch(err => {
  console.error('诊断工具异常:', err);
  process.exit(1);
});
