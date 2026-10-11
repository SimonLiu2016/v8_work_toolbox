import { Page } from 'patchright';
import { TaskConfig } from '../../types/index';
import { solveWithCapSolver } from './capsolver';
import { solveWithAIVision } from './aiVision';

export interface SolveResult {
  success: boolean;
  token?: string;
  method: 'capsolver' | 'ai_vision';
  error?: string;
}

const AI_MAX_RETRIES = 10;

/**
 * Attempt AI vision captcha solving with up to AI_MAX_RETRIES retries.
 * Each retry re-captures the screenshot and re-sends to the AI model,
 * with a short delay between attempts.
 */
async function solveWithAIVisionRetry(
  page: Page,
  config: TaskConfig,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<SolveResult> {
  let lastResult: SolveResult | null = null;

  for (let attempt = 1; attempt <= AI_MAX_RETRIES; attempt++) {
    if (attempt > 1) {
      logCallback(`AI 视觉识别第 ${attempt}/${AI_MAX_RETRIES} 次重试...`, 'warn');
      // Brief pause before retry to allow page state to settle
      await page.waitForTimeout(1500 + Math.floor(Math.random() * 1000));
    }

    const result = await solveWithAIVision(page, config, logCallback);
    if (result.success) {
      return result;
    }

    lastResult = result;
    logCallback(`AI 视觉识别第 ${attempt} 次尝试失败: ${result.error || '未知原因'}`, 'warn');
  }

  return lastResult || { success: false, method: 'ai_vision', error: `AI 视觉识别连续 ${AI_MAX_RETRIES} 次均未成功` };
}

export async function solveCaptcha(
  page: Page,
  config: TaskConfig,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<SolveResult> {
  const mode = config.captchaMode || 'hybrid';

  if (mode === 'capsolver') {
    logCallback('使用打码平台 API (CapSolver) 开始破解人机验证...', 'info');
    return await solveWithCapSolver(page, config.capSolverApiKey, logCallback);
  }

  if (mode === 'ai_vision') {
    logCallback('使用 AI 视觉模型 (Multimodal Vision API) 分析图片解题...', 'info');
    return await solveWithAIVisionRetry(page, config, logCallback);
  }

  // Hybrid Mode: Try AI Vision first (with retries); fallback to CapSolver if AI fails or key missing
  logCallback('使用混合策略模式：优先使用 AI 视觉模型分析...', 'info');
  if (config.aiVisionApiKey) {
    const aiResult = await solveWithAIVisionRetry(page, config, logCallback);
    if (aiResult.success) {
      logCallback('AI 视觉模型成功破解验证码！', 'success');
      return aiResult;
    }
    logCallback(`AI 视觉破解 ${AI_MAX_RETRIES} 次均未成功 (${aiResult.error || '未确定'})，自动降级切换至打码平台 API...`, 'warn');
  } else {
    logCallback('未配置 AI Vision API Key，直接切至打码平台 API...', 'warn');
  }

  if (config.capSolverApiKey) {
    return await solveWithCapSolver(page, config.capSolverApiKey, logCallback);
  }

  return {
    success: false,
    method: 'ai_vision',
    error: '缺少有效打码平台或 AI 视觉 API Key'
  };
}
