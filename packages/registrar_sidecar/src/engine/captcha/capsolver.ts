import axios from 'axios';
import { Page } from 'patchright';
import { SolveResult } from './index';

const CAPSOLVER_API_URL = 'https://api.capsolver.com';

export async function solveWithCapSolver(
  page: Page,
  apiKey: string,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<SolveResult> {
  if (!apiKey) {
    return { success: false, method: 'capsolver', error: 'CapSolver API Key 未填写' };
  }

  try {
    // 1. Extract sitekey or iframe URL from page
    logCallback('寻找页面中的 FunCaptcha 验证组件...', 'info');
    
    // Look for iframe with arkose or funCaptcha sitekey
    const iframeElement = await page.$('iframe[src*="arkoselabs"], iframe[src*="funcaptcha"]');
    let sitekey = 'B7D8911C-A285-431D-A172-31E924E201AE'; // Default Microsoft Signup Arkose Public Key
    let blob = '';

    if (iframeElement) {
      const src = await iframeElement.getAttribute('src');
      if (src) {
        const urlParams = new URLSearchParams(src.split('?')[1] || '');
        if (urlParams.get('pk')) sitekey = urlParams.get('pk')!;
        if (urlParams.get('data')) blob = urlParams.get('data')!;
      }
    }

    logCallback(`提取到 SiteKey: ${sitekey.substring(0, 8)}... 向 CapSolver 提交任务`, 'info');

    // 2. Create CapSolver Task
    const createTaskRes = await axios.post(`${CAPSOLVER_API_URL}/createTask`, {
      clientKey: apiKey,
      task: {
        type: 'FunCaptchaTaskProxyLess',
        websiteURL: page.url(),
        websitePublicKey: sitekey,
        data: blob ? JSON.stringify({ blob }) : undefined
      }
    }, { timeout: 15000 });

    if (createTaskRes.data.errorId !== 0) {
      throw new Error(`CapSolver 创建任务失败: ${createTaskRes.data.errorDescription}`);
    }

    const taskId = createTaskRes.data.taskId;
    logCallback(`CapSolver 任务ID: ${taskId}，等待平台计算 Token...`, 'info');

    // 3. Poll for result
    let attempts = 0;
    while (attempts < 30) {
      await new Promise(res => setTimeout(res, 2000));
      attempts++;

      const resultRes = await axios.post(`${CAPSOLVER_API_URL}/getTaskResult`, {
        clientKey: apiKey,
        taskId
      }, { timeout: 10000 });

      if (resultRes.data.status === 'ready') {
        const token = resultRes.data.solution.token;
        logCallback('CapSolver 成功解题并获得 Token！正在注入页面...', 'success');

        // Inject token into page callback or hidden input
        await page.evaluate((tok: string) => {
          const win = window as any;
          if (typeof win.FunCaptchaComplete === 'function') {
            win.FunCaptchaComplete(tok);
          }
          const tokenInput = document.querySelector('input[name="verificationToken"]') as HTMLInputElement;
          if (tokenInput) tokenInput.value = tok;
        }, token);

        return { success: true, token, method: 'capsolver' };
      }

      if (resultRes.data.status === 'failed') {
        throw new Error(resultRes.data.errorDescription || 'CapSolver 破解失败');
      }
    }

    throw new Error('CapSolver 轮询等待超时');
  } catch (err: any) {
    logCallback(`CapSolver 发生错误: ${err.message}`, 'error');
    return { success: false, method: 'capsolver', error: err.message };
  }
}
