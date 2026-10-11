export interface AccountRecord {
  id: string;
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  birthDate: string;
  recoveryEmail?: string;
  recoveryPhone?: string;
  proxyUsed?: string;
  status: 'SUCCESS' | 'FAILED' | 'REGISTERING';
  createdAt: string;
  errorLog?: string;
  verified?: boolean;
  verifiedAt?: string;
}

export type ProxyMode = 'none' | 'static' | 'api' | 'tunnel' | 'subscription';
export type ProxyProviderType = 'custom' | 'qingguo';

export interface ProxyConfig {
  mode: ProxyMode;
  provider: ProxyProviderType;
  staticList: string[];
  authKey: string;
  authPwd: string;
  apiUrl: string;
  extractNum: number;
  minPoolSize: number;
  tunnelHost: string;
  tunnelPort: number;
  subscriptionUrl: string;
  refreshInterval: number;
}

export type CaptchaMode = 'capsolver' | 'ai_vision' | 'hybrid';

export interface TaskConfig {
  concurrency: number;
  targetDomain: 'outlook.com' | 'hotmail.com';
  proxyList: string[];
  proxyConfig: ProxyConfig;
  captchaMode: CaptchaMode;
  capSolverApiKey: string;
  aiVisionApiKey: string;
  aiVisionModel: string;
  aiVisionEndpoint: string;
  smsApiKey: string;
  smsCountry: string;
  maxRetries: number;
  maxTotalRegistrations?: number;
  verifyAfterRegister: boolean;
  recoveryEmail: string;
  imapServer: string;
  imapPort: number;
  imapUser: string;
  imapAuth: string;
}

export interface LogEntry {
  id: string;
  timestamp: string;
  level: 'info' | 'warn' | 'error' | 'success';
  workerId: number;
  message: string;
}

export interface TaskStats {
  total: number;
  running: number;
  success: number;
  failed: number;
  captchaSolved: number;
  smsUsed: number;
}

export interface AppState {
  isRunning: boolean;
  config: TaskConfig;
  stats: TaskStats;
  logs: LogEntry[];
  accounts: AccountRecord[];
}

export interface ElectronAPI {
  startTasks: (config: TaskConfig) => void;
  stopTasks: () => void;
  saveSettings: (config: TaskConfig) => Promise<boolean>;
  getSettings: () => Promise<TaskConfig | null>;
  getAccounts: () => Promise<AccountRecord[]>;
  deleteAccount: (id: string) => Promise<AccountRecord[]>;
  clearAccounts: () => Promise<AccountRecord[]>;
  exportAccounts: (format: 'csv' | 'json' | 'txt', maskPasswords?: boolean) => Promise<boolean>;
  testImap: () => Promise<{ success: boolean; message: string; code?: string }>;
  getSubscriptionNodes: () => Promise<{ nodes: any[]; currentId: string | null; currentName: string | null }>;
  refreshSubscription: () => Promise<{ success: boolean; message: string; count?: number }>;
  testProxySpeed: (host: string, port: number) => Promise<{ success: boolean; latency: number | null }>;
  batchTestProxySpeed: (nodes: { id: string; server: string; port: number }[]) =>
    Promise<{ success: boolean; results: { id: string; latency: number | null }[] }>;
  getProxyStats: () => Promise<any>;
  onLog: (cb: (log: LogEntry) => void) => () => void;
  onStats: (cb: (stats: TaskStats) => void) => () => void;
  onAccountAdded: (cb: (acc: AccountRecord) => void) => () => void;
}
