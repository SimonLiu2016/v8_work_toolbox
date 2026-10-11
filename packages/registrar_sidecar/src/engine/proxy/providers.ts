import axios from 'axios';
import { ProxyConfig } from '../../types/index';
import { IProxyProvider, ProxyInfo } from './types';

/**
 * 静态代理轮询驱动
 */
export class StaticProxyProvider implements IProxyProvider {
  private config!: ProxyConfig;
  private parsedProxies: ProxyInfo[] = [];
  private index = 0;

  async initialize(config: ProxyConfig): Promise<void> {
    this.config = config;
    this.parsedProxies = [];
    this.index = 0;

    const list = config.staticList || [];
    for (const item of list) {
      const parsed = this.parseProxyString(item.trim());
      if (parsed) {
        this.parsedProxies.push(parsed);
      }
    }
    console.log(`[Proxy] StaticProxyProvider 初始化，成功解析 ${this.parsedProxies.length} 个静态代理。`);
  }

  async getNextProxy(): Promise<ProxyInfo | null> {
    if (this.parsedProxies.length === 0) return null;
    const proxy = this.parsedProxies[this.index % this.parsedProxies.length];
    this.index++;
    return proxy;
  }

  reportFailure(proxy: ProxyInfo): void {
    console.log(`[Proxy] 静态代理汇报失效: ${proxy.host}:${proxy.port}`);
  }

  /**
   * 解析各种格式的代理字符串，例如：
   * - 1.2.3.4:8888
   * - http://1.2.3.4:8888
   * - http://user:pass@1.2.3.4:8888
   * - socks5://user:pass@1.2.3.4:8888
   */
  private parseProxyString(str: string): ProxyInfo | null {
    if (!str) return null;
    try {
      let workingStr = str;
      if (!str.startsWith('http://') && !str.startsWith('https://') && !str.startsWith('socks5://')) {
        workingStr = 'http://' + str;
      }
      
      const parsedUrl = new URL(workingStr);
      const host = parsedUrl.hostname;
      const port = parseInt(parsedUrl.port);
      if (!host || !port || isNaN(port)) return null;

      const username = parsedUrl.username ? decodeURIComponent(parsedUrl.username) : undefined;
      const password = parsedUrl.password ? decodeURIComponent(parsedUrl.password) : undefined;

      return { host, port, username, password };
    } catch (e) {
      // 降级使用正则简单分割 host:port
      const parts = str.replace(/^(http:\/\/|https:\/\/|socks5:\/\/)/i, '').split('@');
      const ipPort = parts[parts.length - 1].split(':');
      if (ipPort.length === 2) {
        const host = ipPort[0];
        const port = parseInt(ipPort[1]);
        if (host && port && !isNaN(port)) {
          if (parts.length > 1) {
            const authParts = parts[0].split(':');
            return {
              host,
              port,
              username: authParts[0] ? decodeURIComponent(authParts[0]) : undefined,
              password: authParts[1] ? decodeURIComponent(authParts[1]) : undefined
            };
          }
          return { host, port };
        }
      }
      console.warn(`[Proxy] 无法解析的代理配置字符串: ${str}`);
      return null;
    }
  }
}

/**
 * 固定隧道代理驱动
 */
export class TunnelProxyProvider implements IProxyProvider {
  private config!: ProxyConfig;

  async initialize(config: ProxyConfig): Promise<void> {
    this.config = config;
    console.log(`[Proxy] TunnelProxyProvider 初始化，隧道主机: ${config.tunnelHost}:${config.tunnelPort}`);
  }

  async getNextProxy(): Promise<ProxyInfo | null> {
    if (!this.config.tunnelHost || !this.config.tunnelPort) {
      console.error('[Proxy] 隧道代理配置不完整！');
      return null;
    }
    return {
      host: this.config.tunnelHost,
      port: this.config.tunnelPort,
      username: this.config.authKey || undefined,
      password: this.config.authPwd || undefined
    };
  }

  reportFailure(proxy: ProxyInfo): void {
    console.log(`[Proxy] 隧道代理汇报失效: ${proxy.host}:${proxy.port}`);
  }
}

/**
 * 动态 API 提取代理驱动（如青果网络及通用 API 提取）
 */
export class QingguoApiProxyProvider implements IProxyProvider {
  private config!: ProxyConfig;
  private pool: ProxyInfo[] = [];
  private isFetching = false;
  private lastFetchTime = 0;

  async initialize(config: ProxyConfig): Promise<void> {
    this.config = config;
    this.pool = [];
    console.log(`[Proxy] QingguoApiProxyProvider 初始化，准备首轮拉取代理 IP。`);
    await this.refillPool();
  }

  async getNextProxy(): Promise<ProxyInfo | null> {
    const minSize = this.config.minPoolSize !== undefined ? this.config.minPoolSize : 2;
    // 异步补充代理池
    if (this.pool.length <= minSize) {
      this.refillPool().catch(err => console.error('[Proxy] 自动刷新代理池异常:', err));
    }

    // 如果为空，阻塞等待一次
    if (this.pool.length === 0) {
      await this.refillPool();
    }

    if (this.pool.length === 0) {
      console.warn('[Proxy] 代理池为空，且 API 未提取到可用 IP。');
      return null;
    }

    const proxy = this.pool.shift() || null;
    return proxy;
  }

  reportFailure(proxy: ProxyInfo): void {
    console.log(`[Proxy] 动态代理汇报失效: ${proxy.host}:${proxy.port}`);
    // 从代理池中彻底过滤该 IP
    this.pool = this.pool.filter(p => !(p.host === proxy.host && p.port === proxy.port));
  }

  /**
   * 拉取并补充代理池
   */
  private async refillPool(): Promise<void> {
    if (this.isFetching) return;

    const now = Date.now();
    // 限制两次请求 API 时间间隔不低于 5 秒，防止过频请求被提供商拦截
    if (now - this.lastFetchTime < 5000) {
      console.log(`[Proxy] 距离上次拉取仅过去 ${now - this.lastFetchTime}ms，节流锁定中...`);
      return;
    }

    this.isFetching = true;
    try {
      const url = this.config.apiUrl;
      if (!url) {
        throw new Error('API 提取链接为空！');
      }

      // 构建带查询参数的 URL（青果 API 要求 key 参数）
      const apiUrl = new URL(url);
      if (this.config.authKey) {
        apiUrl.searchParams.set('key', this.config.authKey);
      }
      if (this.config.extractNum && this.config.extractNum > 0) {
        apiUrl.searchParams.set('num', String(this.config.extractNum));
      }
      apiUrl.searchParams.set('type', 'json');

      console.log(`[Proxy] 正在请求 API 链接获取代理 IP... (${apiUrl.pathname}?key=***)`);
      const response = await axios.get(apiUrl.toString(), {
        timeout: 8000,
        headers: { 'User-Agent': 'Mozilla/5.0' }
      });

      const responseData = response.data;
      let extracted: { ip: string; port: number }[] = [];

      if (responseData && typeof responseData === 'object') {
        // 检查 API 错误码
        if (responseData.code && responseData.code !== 0 && responseData.code !== '0') {
          const errMsg = responseData.message || responseData.msg || JSON.stringify(responseData);
          throw new Error(`API 返回错误: ${errMsg}`);
        }

        // 青果 JSON 格式： { code: 0, msg: "...", data: [ { ip: "...", port: 123 }, ... ] }
        if (Array.isArray(responseData.data)) {
          extracted = responseData.data.map((item: any) => ({
            ip: item.ip,
            port: parseInt(item.port)
          }));
        } else if (Array.isArray(responseData)) {
          // 通用普通数组结构
          extracted = responseData
            .map((item: any) => {
              if (item && item.ip && item.port) {
                return { ip: item.ip, port: parseInt(item.port) };
              }
              return null;
            })
            .filter(Boolean) as any;
        }
      } else if (typeof responseData === 'string') {
        // 纯文本换行格式（IP:PORT 一行一个）
        const lines = responseData.split('\n').map((l: string) => l.trim()).filter(Boolean);
        for (const line of lines) {
          const parts = line.split(':');
          if (parts.length >= 2) {
            const port = parseInt(parts[1]);
            if (parts[0] && port && !isNaN(port)) {
              extracted.push({ ip: parts[0], port });
            }
          }
        }
      }

      if (extracted.length > 0) {
        const newProxies: ProxyInfo[] = extracted.map(item => ({
          host: item.ip,
          port: item.port,
          username: this.config.authKey || undefined,
          password: this.config.authPwd || undefined,
          createdAt: Date.now()
        }));

        this.pool.push(...newProxies);
        this.lastFetchTime = Date.now();
        console.log(`[Proxy] 代理拉取成功！新增 IP 数量: ${newProxies.length}，当前池总数: ${this.pool.length}`);
      } else {
        console.warn('[Proxy] API 返回未包含可解析的 IP 数据，原始返回:', typeof responseData === 'object' ? JSON.stringify(responseData) : responseData);
      }
    } catch (e: any) {
      console.error('[Proxy] 提取 API 代理 IP 失败:', e.message || e);
    } finally {
      this.isFetching = false;
    }
  }
}
