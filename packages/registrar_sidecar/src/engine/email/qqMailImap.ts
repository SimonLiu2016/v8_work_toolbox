import { ImapFlow } from 'imapflow';

export interface ImapConfig {
  server: string;
  port: number;
  user: string;
  auth: string;
}

/**
 * 测试 IMAP 连接和验证码获取
 */
export async function testImapConnection(explicitConfig?: Partial<ImapConfig>, emailAddress?: string): Promise<{ success: boolean; message: string; code?: string }> {
  console.log('[IMAP_TEST] 开始测试...');

  if (!explicitConfig || !explicitConfig.auth) {
    return { success: false, message: 'IMAP 授权码未配置' };
  }

  const config: ImapConfig = {
    server: explicitConfig.server || 'imap.qq.com',
    port: explicitConfig.port || 993,
    user: explicitConfig.user || '',
    auth: explicitConfig.auth,
  };

  console.log(`[IMAP_TEST] 配置: ${config.user}@${config.server}:${config.port}`);

  const code = await fetchMicrosoftCode(config, 30, emailAddress);

  if (code) {
    return { success: true, message: `成功获取验证码: ${code}`, code };
  } else {
    return { success: false, message: '未获取到验证码' };
  }
}

/**
 * 通过 IMAP 连接 QQ 邮箱，搜索 Microsoft 发送的验证码邮件并提取数字验证码。
 * 参照 smsActivate.ts 纯函数模式。
 *
 * @param config IMAP 配置
 * @param timeoutSec 超时时间（秒）
 * @param emailAddress 当前注册的邮箱地址，用于匹配验证码邮件
 */
export async function fetchMicrosoftCode(
  config: ImapConfig,
  timeoutSec: number = 60,
  emailAddress?: string
): Promise<string | null> {
  if (!config.auth || !config.user) return null;

  console.log(`[IMAP] 开始连接 ${config.server}:${config.port}，用户: ${config.user}`);
  if (emailAddress) {
    console.log(`[IMAP] 当前注册邮箱: ${emailAddress}`);
  }

  const client = new ImapFlow({
    host: config.server,
    port: config.port,
    secure: true,
    auth: {
      user: config.user,
      pass: config.auth,
    },
    logger: false,
    tls: { rejectUnauthorized: false },
  });

  try {
    await client.connect();
    console.log('[IMAP] 连接成功');
  } catch (err) {
    console.error('[IMAP] 连接失败:', err);
    return null;
  }

  const startTime = Date.now();
  const pollInterval = 3000;

  try {
    while (Date.now() - startTime < timeoutSec * 1000) {
      try {
        // 搜索 INBOX 中来自 Microsoft 的邮件
        const lock = await client.getMailboxLock('INBOX');
        try {
          // 搜索条件：主题包含 "security code"（不包括 seen: false，因为新邮件可能还未标记为未读）
          const searchResult = await client.search(
            {
              subject: 'Personal Microsoft account security code'
            },
            { uid: true }
          );

          const resultArray = Array.isArray(searchResult) ? searchResult : [];
          console.log(`[IMAP] INBOX 搜索结果: ${resultArray.length} 封邮件`);

          if (resultArray.length > 0) {
            // 获取最新的 5 封邮件
            const uidsToCheck = resultArray.slice(-5);
            console.log(`[IMAP] 检查最新 ${uidsToCheck.length} 封邮件`);

            for (const uid of uidsToCheck) {
              const msg = await client.fetchOne(uid, { source: true, internalDate: true }, { uid: true });

              if (msg && msg.source) {
                const source = typeof msg.source === 'string' ? msg.source : msg.source.toString();

                // 检查邮件时间（只处理最近 5 分钟内收到的邮件）
                if (msg.internalDate) {
                  const emailTime = new Date(msg.internalDate).getTime();
                  const fiveMinutesAgo = Date.now() - 5 * 60 * 1000;
                  if (emailTime < fiveMinutesAgo) {
                    console.log(`[IMAP] 邮件 ${uid}: 时间 ${new Date(emailTime).toLocaleString()}，超过 5 分钟，跳过`);
                    continue;
                  }
                  console.log(`[IMAP] 邮件 ${uid}: 时间 ${new Date(emailTime).toLocaleString()}，在 5 分钟内`);
                }

                // 提取邮件中的账号信息
                const emailInMessage = extractEmailFromMessage(source);
                console.log(`[IMAP] 邮件 ${uid}: 账号=${emailInMessage || '未识别'}`);

                // 如果指定了邮箱地址，检查是否匹配
                if (emailAddress && emailInMessage) {
                  if (!matchEmailPattern(emailAddress, emailInMessage)) {
                    console.log(`[IMAP] 邮件 ${uid}: 账号不匹配，跳过`);
                    continue;
                  }
                  console.log(`[IMAP] 邮件 ${uid}: 账号匹配！`);
                }

                // 提取验证码
                const code = extractVerificationCode(source);
                if (code) {
                  console.log(`[IMAP] 从邮件 ${uid} 提取到验证码: ${code}`);
                  await lock.release();
                  return code;
                }
              }
            }
          }
        } finally {
          lock.release();
        }

        // 同时搜索 JUNK 文件夹（验证码可能被过滤到垃圾箱）
        try {
          const junkLock = await client.getMailboxLock('JUNK');
          try {
            const junkResult = await client.search(
              {
                subject: 'Personal Microsoft account security code'
              },
              { uid: true }
            );

            const junkArray = Array.isArray(junkResult) ? junkResult : [];
            console.log(`[IMAP] JUNK 搜索结果: ${junkArray.length} 封邮件`);

            if (junkArray.length > 0) {
              // 获取最新的 5 封邮件
              const uidsToCheck = junkArray.slice(-5);
              console.log(`[IMAP] 检查 JUNK 最新 ${uidsToCheck.length} 封邮件`);

              for (const uid of uidsToCheck) {
                const msg = await client.fetchOne(uid, { source: true, internalDate: true }, { uid: true });

                if (msg && msg.source) {
                  const source = typeof msg.source === 'string' ? msg.source : msg.source.toString();

                  // 检查邮件时间（只处理最近 5 分钟内收到的邮件）
                  if (msg.internalDate) {
                    const emailTime = new Date(msg.internalDate).getTime();
                    const fiveMinutesAgo = Date.now() - 5 * 60 * 1000;
                    if (emailTime < fiveMinutesAgo) {
                      console.log(`[IMAP] JUNK 邮件 ${uid}: 时间 ${new Date(emailTime).toLocaleString()}，超过 5 分钟，跳过`);
                      continue;
                    }
                    console.log(`[IMAP] JUNK 邮件 ${uid}: 时间 ${new Date(emailTime).toLocaleString()}，在 5 分钟内`);
                  }

                  // 提取邮件中的账号信息
                  const emailInMessage = extractEmailFromMessage(source);
                  console.log(`[IMAP] JUNK 邮件 ${uid}: 账号=${emailInMessage || '未识别'}`);

                  // 如果指定了邮箱地址，检查是否匹配
                  if (emailAddress && emailInMessage) {
                    if (!matchEmailPattern(emailAddress, emailInMessage)) {
                      console.log(`[IMAP] JUNK 邮件 ${uid}: 账号不匹配，跳过`);
                      continue;
                    }
                    console.log(`[IMAP] JUNK 邮件 ${uid}: 账号匹配！`);
                  }

                  // 提取验证码
                  const code = extractVerificationCode(source);
                  if (code) {
                    console.log(`[IMAP] 从 JUNK 邮件 ${uid} 提取到验证码: ${code}`);
                    await junkLock.release();
                    return code;
                  }
                }
              }
            }
          } finally {
            junkLock.release();
          }
        } catch (err) {
          // JUNK 文件夹可能不存在，忽略
          console.log('[IMAP] JUNK 文件夹搜索失败:', err);
        }
      } catch (err) {
        console.error('[IMAP] 单次轮询失败:', err);
      }

      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      console.log(`[IMAP] 等待中... ${elapsed}/${timeoutSec}秒`);
      await new Promise((r) => setTimeout(r, pollInterval));
    }
  } finally {
    await client.logout().catch(() => {});
  }

  console.log('[IMAP] 超时，未找到验证码邮件');
  return null;
}

/**
 * 从邮件内容中提取邮箱地址
 * 邮件格式: "Please use the following security code for your personal Microsoft account jw**b@outlook.com."
 */
function extractEmailFromMessage(source: string): string | null {
  // 匹配邮箱地址格式（可能包含星号）
  const patterns = [
    /for your personal Microsoft account\s+([a-zA-Z0-9.*]+@[a-zA-Z0-9.*]+)/i,
    /for your account\s+([a-zA-Z0-9.*]+@[a-zA-Z0-9.*]+)/i,
    /account\s+([a-zA-Z0-9.*]+@[a-zA-Z0-9.*]+)/i,
  ];

  for (const pattern of patterns) {
    const match = source.match(pattern);
    if (match) {
      // 移除末尾的句号（如果有的话）
      let email = match[1];
      if (email.endsWith('.')) {
        email = email.slice(0, -1);
      }
      return email;
    }
  }

  return null;
}

/**
 * 模糊匹配邮箱地址
 * 邮件中的邮箱地址可能包含星号（如 jw**b@outlook.com）
 * 需要匹配真实邮箱地址（如 jw123b@outlook.com）
 *
 * @param realEmail 真实邮箱地址
 * @param patternEmail 模式邮箱地址（可能包含星号）
 */
function matchEmailPattern(realEmail: string, patternEmail: string): boolean {
  // 分离本地部分和域名
  const [realLocal, realDomain] = realEmail.split('@');
  const [patternLocal, patternDomain] = patternEmail.split('@');

  // 域名必须完全匹配
  if (realDomain.toLowerCase() !== patternDomain.toLowerCase()) {
    return false;
  }

  // 本地部分模糊匹配
  // 将模式转换为正则表达式
  // 例如: jw**b -> jw.*b（* 匹配任意多个字符）
  const regexPattern = patternLocal
    .replace(/[.+^${}()|[\]\\]/g, '\\$&') // 转义特殊字符（除了 *）
    .replace(/\*/g, '.*'); // 将 * 替换为 .*（匹配任意多个字符）

  const regex = new RegExp(`^${regexPattern}$`, 'i');
  return regex.test(realLocal);
}

/**
 * 从邮件源码中提取数字验证码（4-8 位纯数字）
 */
function extractVerificationCode(source: string): string | null {
  console.log('[IMAP] 开始提取验证码...');

  // 优先匹配 Microsoft 标准格式: "Security code: XXXXXX"
  const primaryPatterns = [
    /Security code:\s*(\d{4,8})/i,
    /验证码[：:]\s*(\d{4,8})/,
    /security code[^\d]*(\d{4,8})/i,
    /code[：:]\s*(\d{4,8})/i,
  ];

  for (const pattern of primaryPatterns) {
    const match = source.match(pattern);
    if (match) {
      console.log(`[IMAP] 使用模式 ${pattern} 提取到验证码: ${match[1]}`);
      return match[1];
    }
  }

  // 备用模式
  const fallbackPatterns = [
    /(?:verification|security|code)[^\d]*(\d{4,8})/i,
    /(\d{4,8})\s*(?:is your|是你的|your verification)/i,
    /(?:enter|input|输入)\s*(\d{4,8})/i,
    /<b>\s*(\d{4,8})\s*<\/b>/i,
    /<span[^>]*>\s*(\d{4,8})\s*<\/span>/i,
    // 通用：正文中独立的 6 位数字
    /\b(\d{6})\b/,
  ];

  for (const pattern of fallbackPatterns) {
    const match = source.match(pattern);
    if (match) {
      console.log(`[IMAP] 使用备用模式 ${pattern} 提取到验证码: ${match[1]}`);
      return match[1];
    }
  }

  console.log('[IMAP] 未找到验证码');
  return null;
}
