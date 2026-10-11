import axios from 'axios';
import { Page } from 'patchright';
import { TaskConfig } from '../../types/index';
import { SolveResult } from './index';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

export async function solveWithAIVision(
  page: Page,
  config: TaskConfig,
  logCallback: (msg: string, level?: 'info' | 'warn' | 'error' | 'success') => void
): Promise<SolveResult> {
  const apiKey = config.aiVisionApiKey;
  let endpoint = (config.aiVisionEndpoint || 'https://api.openai.com/v1/chat/completions').trim();
  const model = config.aiVisionModel || 'claude-3-5-sonnet-20241022';

  if (!apiKey) {
    return { success: false, method: 'ai_vision', error: 'AI Vision API Key 未配置' };
  }

  // Detect whether endpoint is Anthropic protocol
  const isAnthropic = endpoint.includes('/v1/messages') || endpoint.includes('/anthropic/') || model.includes('claude') || model.includes('mimo');

  if (isAnthropic) {
    if (!endpoint.includes('/v1/messages')) {
      endpoint = endpoint.replace(/\/+$/, '') + '/v1/messages';
    }
  } else {
    if (!endpoint.endsWith('/chat/completions') && !endpoint.includes('/v1/chat/completions')) {
      endpoint = endpoint.replace(/\/+$/, '') + '/v1/chat/completions';
    }
  }

  try {
    logCallback('寻找页面中的验证码图片组件并捕获截图...', 'info');

    // Find captcha container or iframe
    const captchaFrame = page.frame({ url: /arkoselabs|funcaptcha/ });
    const targetElement = captchaFrame ? await captchaFrame.$('body') : await page.$('.challenge-container, iframe');

    let base64Image = '';
    if (targetElement) {
      const buffer = await targetElement.screenshot({ type: 'png' });
      base64Image = buffer.toString('base64');
    } else {
      // Fallback: Full page screenshot
      const buffer = await page.screenshot({ type: 'png' });
      base64Image = buffer.toString('base64');
    }

    // Save captcha screenshot to disk for inspection
    try {
      const saveDir = path.join(os.homedir(), 'Desktop', 'captcha_screenshots');
      if (!fs.existsSync(saveDir)) {
        fs.mkdirSync(saveDir, { recursive: true });
      }
      const ts = new Date().toISOString().replace(/[:.]/g, '-');
      const savePath = path.join(saveDir, `captcha_${ts}.png`);
      fs.writeFileSync(savePath, Buffer.from(base64Image, 'base64'));
      logCallback(`验证码截图已保存至: ${savePath}`, 'info');
    } catch (saveErr: any) {
      logCallback(`验证码截图保存失败: ${saveErr.message}`, 'warn');
    }

    logCallback(`截取验证码图片成功 (${base64Image.length} B)，发送至 ${isAnthropic ? 'Anthropic' : 'OpenAI'} API: ${endpoint} (模型: ${model})...`, 'info');

    const promptText = `你是一个专业的图形人机验证码分析助手。请仔细观察这张验证码图片。
图片中通常包含题目指令（如"使用箭头旋转物体与手势方向一致"或"选中包含2个相同图案的格子"或"按住按钮/长按图标完成验证"）。
请分析出正确的点击、旋转或长按步骤。

请直接以 JSON 格式输出结果，不要包含任何 markdown 块或多余文字，格式为：
{
  "confidence": 0.95,
  "actionType": "rotate" | "click_option" | "press_and_hold",
  "clickIndex": 1, 
  "rightArrowClicks": 2,
  "explanation": "简要解题说明"
}`;

    let aiText = '';

    if (isAnthropic) {
      // Anthropic /v1/messages Protocol
      const payload = {
        model,
        max_tokens: 400,
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'image',
                source: {
                  type: 'base64',
                  media_type: 'image/png',
                  data: base64Image
                }
              },
              {
                type: 'text',
                text: promptText
              }
            ]
          }
        ]
      };

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01'
      };
      if (apiKey.startsWith('sk-')) {
        headers['x-api-key'] = apiKey;
      } else {
        headers['Authorization'] = `Bearer ${apiKey}`;
        headers['x-api-key'] = apiKey;
      }

      const res = await axios.post(endpoint, payload, { headers, timeout: 25000 });
      aiText = res.data.content?.[0]?.text || '';
    } else {
      // OpenAI /v1/chat/completions Protocol
      const payload = {
        model,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: promptText },
              {
                type: 'image_url',
                image_url: { url: `data:image/png;base64,${base64Image}` }
              }
            ]
          }
        ],
        max_tokens: 300,
        temperature: 0.1
      };

      const res = await axios.post(endpoint, payload, {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json'
        },
        timeout: 25000
      });
      aiText = res.data.choices?.[0]?.message?.content || '';
    }
    logCallback(`AI 响应原文本: ${aiText.substring(0, 200)}${aiText.length > 200 ? '...' : ''}`, 'info');

    // Guard: empty response
    if (!aiText || aiText.trim().length === 0) {
      logCallback('AI 返回了空内容，无法解析验证码结果', 'warn');
      return { success: false, method: 'ai_vision', error: 'AI 返回空响应，可能是模型不支持图片或请求被拒绝' };
    }

    // Robust JSON extraction: strip markdown fences, then try to find a JSON object
    let cleanJson = aiText
      .replace(/```json\s*/gi, '')
      .replace(/```\s*/g, '')
      .trim();

    // If the cleaned text isn't valid JSON directly, try to extract the first {...} block
    if (!cleanJson.startsWith('{')) {
      const jsonMatch = cleanJson.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        cleanJson = jsonMatch[0];
      } else {
        logCallback(`AI 响应中未找到有效的 JSON 结构: ${cleanJson.substring(0, 120)}`, 'warn');
        return { success: false, method: 'ai_vision', error: 'AI 响应不包含可解析的 JSON 结构' };
      }
    }

    let result: any;
    try {
      result = JSON.parse(cleanJson);
    } catch (parseErr: any) {
      logCallback(`AI 响应 JSON 解析失败: ${parseErr.message}，原文: ${cleanJson.substring(0, 120)}`, 'warn');
      return { success: false, method: 'ai_vision', error: `AI 响应 JSON 格式错误: ${parseErr.message}` };
    }

    if (result.confidence && result.confidence < 0.6) {
      logCallback(`AI 视觉识别置信度过低 (${result.confidence}): ${result.explanation}`, 'warn');
      return { success: false, method: 'ai_vision', error: 'AI 识别置信度低于阈值' };
    }

    logCallback(`AI 识别成功 (${result.explanation})，正在模拟执行浏览器交互...`, 'info');

    // Execute actions on page
    const isPressAndHold = result.actionType === 'press_and_hold' || 
      (typeof result.explanation === 'string' && (
        result.explanation.includes('按住') ||
        result.explanation.includes('长按') ||
        result.explanation.includes('press') ||
        result.explanation.includes('hold')
      ));

    if (isPressAndHold) {
      logCallback('AI 判定需执行长按 (Press and hold) 操作...', 'info');
      const targetBtn = captchaFrame
        ? await captchaFrame.$('button, [aria-label*="Press"], [data-theme="home.verifyButton"], a.challenge-option, img[role="button"]')
        : await page.$('button:has-text("Press and hold"), button:has-text("按住"), [aria-label*="Press"]');
      
      if (targetBtn) {
        const box = await targetBtn.boundingBox();
        if (box) {
          const x = box.x + box.width / 2;
          const y = box.y + box.height / 2;
          await page.mouse.move(x, y);
          await page.waitForTimeout(200);
          await page.mouse.down();
          await page.waitForTimeout(8500);
          await page.mouse.up();
        } else {
          await targetBtn.click();
        }
      }
    } else if (result.actionType === 'rotate' && result.rightArrowClicks > 0) {
      const rightArrow = captchaFrame ? await captchaFrame.$('button[aria-label*="Right"], .right-arrow') : await page.$('.right-arrow');
      if (rightArrow) {
        for (let i = 0; i < result.rightArrowClicks; i++) {
          await rightArrow.click();
          await new Promise(r => setTimeout(r, 600));
        }
        const submitBtn = captchaFrame ? await captchaFrame.$('button[type="submit"], .game-submit') : await page.$('.game-submit');
        if (submitBtn) await submitBtn.click();
      }
    } else if (result.actionType === 'click_option' && result.clickIndex !== undefined) {
      const options = captchaFrame ? await captchaFrame.$$('a.challenge-option, img[role="button"]') : await page.$$('.challenge-option');
      if (options[result.clickIndex]) {
        await options[result.clickIndex].click();
      }
    }

    await new Promise(r => setTimeout(r, 2500));

    // Post-execution check: verify if captcha container is still visible
    const stillActive = captchaFrame
      ? await captchaFrame.$('button, .challenge-container')
      : await page.$('.challenge-container, iframe[src*="arkoselabs"], iframe[src*="funcaptcha"]');
    
    if (stillActive && await stillActive.isVisible()) {
      logCallback('提示: 模拟点击/长按后验证码依然存在，可能未成功识别或需要下一题', 'warn');
      return { success: false, method: 'ai_vision', error: '验证码依然存在（未能成功通过或需多图连续解题）' };
    }

    return { success: true, method: 'ai_vision' };
  } catch (err: any) {
    const status = err.response?.status;
    let errMsg = err.message;
    if (status === 404) {
      errMsg = `Endpoint 地址 404 无法找到 (${endpoint})。请检查【系统配置】中填写的 API Endpoint 是否拼写正确或包含正确路径 (/v1/chat/completions)`;
    } else if (status === 401) {
      errMsg = `API Key 无效或未授权 (HTTP 401)。请检查【系统配置】中的 AI API Key 是否准确`;
    }
    logCallback(`AI 视觉识别解析异常: ${errMsg}`, 'error');
    return { success: false, method: 'ai_vision', error: errMsg };
  }
}
