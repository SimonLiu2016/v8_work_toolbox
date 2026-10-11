import { ProxyConfig } from '../../types/index';

export interface ProxyInfo {
  host: string;
  port: number;
  username?: string;
  password?: string;
  failCount?: number;
  createdAt?: number;
}

export interface IProxyProvider {
  initialize(config: ProxyConfig): Promise<void>;
  getNextProxy(): Promise<ProxyInfo | null>;
  reportFailure(proxy: ProxyInfo): void;
}
