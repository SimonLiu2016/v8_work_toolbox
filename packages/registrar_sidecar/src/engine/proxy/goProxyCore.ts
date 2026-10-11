import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import http from 'http';

const API_HOST = '127.0.0.1';
const API_PORT = 6162;
const HTTP_PROXY_PORT = 6160;
const MAX_RESTARTS = 3;

export interface GoProxyCoreConfig {
  httpPort: number;
  socks5Port: number;
  apiPort: number;
}

const defaultConfig: GoProxyCoreConfig = {
  httpPort: HTTP_PROXY_PORT,
  socks5Port: 6161,
  apiPort: API_PORT,
};

export class GoProxyCore {
  private process: ChildProcess | null = null;
  private restartCount = 0;
  private configDir: string = '';
  private running = false;

  async start(config: Partial<GoProxyCoreConfig> = {}): Promise<void> {
    if (this.running) return;

    const cfg = { ...defaultConfig, ...config };
    this.configDir = fs.mkdtempSync(path.join(os.tmpdir(), 'go-proxy-core-'));

    const configYaml = [
      `http_port: ${cfg.httpPort}`,
      `socks5_port: ${cfg.socks5Port}`,
      `api_port: ${cfg.apiPort}`,
      `dns_port: 53`,
      `dns_type: "fakeip"`,
      `doh_server: "https://1.1.1.1/dns-query"`,
      `log_level: "info"`,
    ].join('\n');

    fs.writeFileSync(path.join(this.configDir, 'config.yaml'), configYaml);

    const binPath = this.getBinaryPath();
    this.process = spawn(binPath, [], {
      cwd: this.configDir,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    this.process.on('error', (err) => {
      console.error('[GoProxyCore] Process error:', err.message);
      this.running = false;
    });

    this.process.on('exit', (code) => {
      console.log(`[GoProxyCore] Process exited with code ${code}`);
      this.running = false;
      if (code !== 0 && this.restartCount < MAX_RESTARTS) {
        this.restartCount++;
        console.log(`[GoProxyCore] Restarting (${this.restartCount}/${MAX_RESTARTS})...`);
        setTimeout(() => this.start(config), 1000);
      }
    });

    this.process.stderr?.on('data', (data) => {
      const msg = data.toString().trim();
      if (msg) console.log(`[GoProxyCore] ${msg}`);
    });

    await this.waitForReady();
    this.running = true;
    this.restartCount = 0;
    console.log('[GoProxyCore] Started successfully');
  }

  async stop(): Promise<void> {
    if (this.process) {
      this.process.kill('SIGTERM');
      this.process = null;
    }
    this.running = false;
    if (this.configDir) {
      try { fs.rmSync(this.configDir, { recursive: true, force: true }); } catch {}
      this.configDir = '';
    }
    console.log('[GoProxyCore] Stopped');
  }

  isRunning(): boolean {
    return this.running;
  }

  getProxyUrl(): string {
    return `http://${API_HOST}:${HTTP_PROXY_PORT}`;
  }

  private getBinaryPath(): string {
    const platform = os.platform();
    const ext = platform === 'win32' ? '.exe' : '';
    const devPath = path.join(__dirname, '..', '..', '..', 'resources', `go-proxy-core${ext}`);
    if (fs.existsSync(devPath)) return devPath;
    const prodPath = path.join(process.resourcesPath || '', `go-proxy-core${ext}`);
    if (fs.existsSync(prodPath)) return prodPath;
    throw new Error(`go-proxy-core binary not found at ${devPath}`);
  }

  private async waitForReady(timeoutMs = 10000): Promise<void> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      try {
        const status = await this.apiRequest('GET', '/status');
        if (status && status.running) return;
      } catch {}
      await new Promise(r => setTimeout(r, 300));
    }
    throw new Error('go-proxy-core did not start within timeout');
  }

  async apiRequest(method: string, endpoint: string, body?: any): Promise<any> {
    return new Promise((resolve, reject) => {
      const options: http.RequestOptions = {
        hostname: API_HOST,
        port: API_PORT,
        path: endpoint,
        method,
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000,
      };

      const req = http.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          try {
            resolve(data ? JSON.parse(data) : {});
          } catch {
            resolve(data);
          }
        });
      });

      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('Request timeout')); });

      if (body) req.write(JSON.stringify(body));
      req.end();
    });
  }

  async addProxySource(id: string, name: string, proxies: any[]): Promise<void> {
    await this.apiRequest('POST', '/proxy-sources', { id, name, type: 'custom', config: {}, proxies: {} });
    if (proxies.length > 0) {
      await this.apiRequest('PUT', `/proxy-sources/${id}/proxies`, proxies);
    }
  }

  async setCurrentProxy(sourceId: string, proxy: any): Promise<void> {
    await this.apiRequest('PUT', `/proxy-sources/${sourceId}/current-proxy`, proxy);
  }

  async removeProxySource(sourceId: string): Promise<void> {
    await this.apiRequest('DELETE', `/proxy-sources/${sourceId}`);
  }

  async getStatus(): Promise<any> {
    return this.apiRequest('GET', '/status');
  }

  async getProxySources(): Promise<any> {
    return this.apiRequest('GET', '/proxy-sources');
  }

  async getStats(): Promise<any> {
    return this.apiRequest('GET', '/stats');
  }
}

export const goProxyCore = new GoProxyCore();
