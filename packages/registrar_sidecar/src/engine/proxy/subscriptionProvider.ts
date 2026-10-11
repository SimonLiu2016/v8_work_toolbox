import { IProxyProvider, ProxyInfo } from './types';
import { ProxyConfig } from '../../types/index';
import { goProxyCore } from './goProxyCore';
import { fetchSubscription, parseSubscription, ParsedProxy } from './subscriptionParser';

const SOURCE_ID = 'subscription';
const REFRESH_INTERVAL_MS = 30 * 60 * 1000;

// Protocols that go-proxy-core supports
const SUPPORTED_PROTOCOLS = new Set([
  'shadowsocks', 'vmess', 'vless', 'trojan', 'wireguard',
  'shadowsocks', 'snell', 'socks5', 'http',
]);

export class SubscriptionProxyProvider implements IProxyProvider {
  private proxies: ParsedProxy[] = [];
  private currentIndex = 0;
  private refreshTimer: NodeJS.Timeout | null = null;
  private initialized = false;
  private refreshInterval: number = REFRESH_INTERVAL_MS;

  async initialize(config: ProxyConfig): Promise<void> {
    this.refreshInterval = (config.refreshInterval || 30) * 60 * 1000;

    if (!config.subscriptionUrl) {
      throw new Error('Subscription URL is required');
    }

    await this.refreshSubscription(config.subscriptionUrl);
    this.startAutoRefresh(config.subscriptionUrl);
    this.initialized = true;
  }

  async getNextProxy(): Promise<ProxyInfo | null> {
    if (this.proxies.length === 0) return null;

    const proxy = this.proxies[this.currentIndex % this.proxies.length];
    this.currentIndex = (this.currentIndex + 1) % this.proxies.length;

    await this.setActiveProxy(proxy);

    return {
      host: proxy.server,
      port: proxy.port,
    };
  }

  reportFailure(proxy: ProxyInfo): void {
    const idx = this.proxies.findIndex(
      p => p.server === proxy.host && p.port === proxy.port
    );
    if (idx !== -1) {
      this.proxies.splice(idx, 1);
      if (this.currentIndex >= this.proxies.length) {
        this.currentIndex = 0;
      }
    }
  }

  async destroy(): Promise<void> {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  getProxyCount(): number {
    return this.proxies.length;
  }

  getProxies(): ParsedProxy[] {
    return [...this.proxies];
  }

  getCurrentProxyName(): string | null {
    if (this.proxies.length === 0) return null;
    const idx = (this.currentIndex - 1 + this.proxies.length) % this.proxies.length;
    return this.proxies[idx]?.name || null;
  }

  getCurrentProxyId(): string | null {
    if (this.proxies.length === 0) return null;
    const idx = (this.currentIndex - 1 + this.proxies.length) % this.proxies.length;
    return this.proxies[idx]?.id || null;
  }

  async refresh(url?: string): Promise<number> {
    if (!url) return this.proxies.length;
    await this.refreshSubscription(url);
    return this.proxies.length;
  }

  private async refreshSubscription(url: string): Promise<void> {
    console.log(`[SubscriptionProvider] Fetching subscription: ${url}`);
    const content = await fetchSubscription(url);
    console.log(`[SubscriptionProvider] Got content length: ${content.length}`);
    const newProxies = parseSubscription(content);
    console.log(`[SubscriptionProvider] Parsed ${newProxies.length} proxies`);
    if (newProxies.length > 0) {
      this.proxies = newProxies;
      this.currentIndex = 0;
    } else {
      console.warn(`[SubscriptionProvider] No valid proxies found in subscription`);
    }
  }

  async syncToGoProxyCore(): Promise<void> {
    await goProxyCore.removeProxySource(SOURCE_ID).catch(() => {});

    const supportedProxies = this.proxies
      .filter(p => SUPPORTED_PROTOCOLS.has(p.type))
      .map(p => ({
        id: p.id,
        name: p.name,
        type: p.type,
        server: p.server,
        port: p.port,
        config: p.config,
      }));

    if (supportedProxies.length > 0) {
      await goProxyCore.addProxySource(SOURCE_ID, 'Clash Subscription', supportedProxies);
    }
  }

  private async setActiveProxy(proxy: ParsedProxy): Promise<void> {
    await goProxyCore.setCurrentProxy(SOURCE_ID, {
      id: proxy.id,
      name: proxy.name,
      type: proxy.type,
      server: proxy.server,
      port: proxy.port,
      config: proxy.config,
    });
  }

  private startAutoRefresh(url: string): void {
    this.refreshTimer = setInterval(() => {
      this.refreshSubscription(url);
    }, this.refreshInterval);
  }
}
