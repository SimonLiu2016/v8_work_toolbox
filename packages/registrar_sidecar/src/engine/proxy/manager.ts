import { ProxyConfig } from '../../types/index';
import { IProxyProvider, ProxyInfo } from './types';
import { StaticProxyProvider, TunnelProxyProvider, QingguoApiProxyProvider } from './providers';
import { SubscriptionProxyProvider } from './subscriptionProvider';

export class ProxyManager {
  private provider: IProxyProvider | null = null;
  private config!: ProxyConfig;

  constructor(config: ProxyConfig) {
    this.config = config;
    this.initializeProvider();
  }

  public updateConfig(config: ProxyConfig) {
    this.config = config;
    this.initializeProvider();
  }

  private initializeProvider() {
    const mode = this.config ? this.config.mode : 'none';
    console.log(`[ProxyManager] 正在创建代理 Provider，模式为: ${mode}`);

    switch (mode) {
      case 'static':
        this.provider = new StaticProxyProvider();
        break;
      case 'tunnel':
        this.provider = new TunnelProxyProvider();
        break;
      case 'api':
        this.provider = new QingguoApiProxyProvider();
        break;
      case 'subscription':
        this.provider = new SubscriptionProxyProvider();
        break;
      case 'none':
      default:
        this.provider = null;
        break;
    }

    // 延迟初始化：由外部（WorkerPool）在 go-proxy-core 启动后调用 syncNodes()
  }

  public async getNextProxy(): Promise<ProxyInfo | null> {
    if (!this.provider) return null;
    return await this.provider.getNextProxy();
  }

  public reportFailure(proxy: ProxyInfo) {
    if (this.provider) {
      this.provider.reportFailure(proxy);
    }
  }

  public async syncNodes(): Promise<void> {
    if (this.provider && this.provider instanceof SubscriptionProxyProvider) {
      await this.provider.syncToGoProxyCore();
    }
  }

  public isSubscriptionMode(): boolean {
    return this.config?.mode === 'subscription';
  }
}
