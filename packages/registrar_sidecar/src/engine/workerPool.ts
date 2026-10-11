import { TaskConfig, AccountRecord, TaskStats, LogEntry } from '../types/index';
import { runSingleRegistration, classifyFailure, FailureType } from './browser';
import { ProxyManager } from './proxy/manager';
import { ProxyInfo } from './proxy/types';
import { goProxyCore } from './proxy/goProxyCore';

// ──────────────────────────────────────────────────────────────
// Backoff thresholds & failure tracking
// ──────────────────────────────────────────────────────────────

const BACKOFF_THRESHOLDS = [
  { failures: 5, delayMs: 30_000, label: '30秒' },
  { failures: 8, delayMs: 120_000, label: '2分钟' },
  { failures: 10, delayMs: 0, label: '停止' }, // 0 = stop worker
] as const;

// Track failure types across all workers for smart auto-stop
const FAILURE_TYPE_LIMITS: Partial<Record<FailureType, number>> = {
  proxy_unavailable: 3,   // Stop all after 3 proxy failures (key expired etc)
  page_blank: 5,          // Stop all after 5 blank pages (systemic detection)
  page_blocked: 5,        // Stop all after 5 blocked pages
  network_error: 8,       // Tolerate more network errors
};

export class WorkerPoolManager {
  private isRunning = false;
  private config: TaskConfig;
  private stats: TaskStats = {
    total: 0,
    running: 0,
    success: 0,
    failed: 0,
    captchaSolved: 0,
    smsUsed: 0
  };

  private proxyManager: ProxyManager | null = null;
  private logListeners: ((log: LogEntry) => void)[] = [];
  private statsListeners: ((stats: TaskStats) => void)[] = [];
  private accountListeners: ((acc: AccountRecord) => void)[] = [];

  // Failure type tracking for smart auto-stop
  private failureTypeCounts: Record<string, number> = {};

  constructor(config: TaskConfig) {
    this.config = config;
    this.proxyManager = new ProxyManager(config.proxyConfig);
  }

  public updateConfig(newConfig: TaskConfig) {
    this.config = newConfig;
    if (this.proxyManager) {
      this.proxyManager.updateConfig(newConfig.proxyConfig);
    } else {
      this.proxyManager = new ProxyManager(newConfig.proxyConfig);
    }
  }

  public onLog(listener: (log: LogEntry) => void) {
    this.logListeners.push(listener);
  }

  public onStats(listener: (stats: TaskStats) => void) {
    this.statsListeners.push(listener);
  }

  public onAccount(listener: (acc: AccountRecord) => void) {
    this.accountListeners.push(listener);
  }

  private emitLog(message: string, level: 'info' | 'warn' | 'error' | 'success' = 'info', workerId: number = 0) {
    const entry: LogEntry = {
      id: Math.random().toString(36).substring(2, 9),
      timestamp: new Date().toLocaleTimeString('zh-CN'),
      level,
      workerId,
      message
    };
    console.log(`[WORKER_POOL_LOG][${level.toUpperCase()}] ${message}`);
    this.logListeners.forEach(l => l(entry));
  }

  private emitStats() {
    this.statsListeners.forEach(l => l({ ...this.stats }));
  }

  public async start() {
    if (this.isRunning) {
      this.emitLog('检测到已有正在运行的任务队列，重置运行状态...', 'warn');
      this.isRunning = false;
      await new Promise(r => setTimeout(r, 400));
    }

    this.isRunning = true;
    this.emitLog('>>> 任务队列启动，正在分配并发线程...', 'info');

    // 启动代理核心（仅 subscription 模式）
    if (this.config.proxyConfig.mode === 'subscription') {
      try {
        this.emitLog('正在启动代理核心 (go-proxy-core)...', 'info');
        await goProxyCore.start();
        this.emitLog('代理核心启动成功', 'success');
        // 同步节点到代理核心
        if (this.proxyManager) {
          await this.proxyManager.syncNodes();
          this.emitLog('节点列表已同步到代理核心', 'info');
        }
      } catch (err: any) {
        this.emitLog(`代理核心启动失败: ${err?.message || err}`, 'error');
      }
    }

    try {
      // 当配置了恢复邮箱时，限制并发为 1 以避免验证码混淆
      let concurrency = Math.max(1, this.config.concurrency || 3);
      if (this.config.recoveryEmail && this.config.imapAuth) {
        concurrency = 1;
        this.emitLog('已配置安全邮箱绑定，并发自动限制为 1', 'info');
      }
      const workerPromises: Promise<void>[] = [];

      for (let i = 1; i <= concurrency; i++) {
        workerPromises.push(this.runWorkerLoop(i));
      }

      await Promise.all(workerPromises);
    } catch (err: any) {
      this.emitLog(`任务队列全局异常: ${err?.message || err}`, 'error');
    } finally {
      this.isRunning = false;
      this.emitLog('>>> 所有并发任务循环已停止', 'info');
    }
  }

  public stop() {
    this.isRunning = false;
    this.emitLog('收到停止命令，等待当前在途任务结束...', 'warn');
    // 关闭代理核心（如果正在运行）
    if (goProxyCore.isRunning()) {
      this.emitLog('正在关闭代理核心...', 'info');
      goProxyCore.stop().catch(err => {
        this.emitLog(`代理核心关闭失败: ${err?.message || err}`, 'error');
      });
    }
  }

  /**
   * Extract failure type from errorLog string like "[proxy_unavailable] xxx: yyy"
   */
  private extractFailureType(errorLog: string): string {
    const match = errorLog.match(/^\[([a-z_]+)\]/);
    return match ? match[1] : 'unknown';
  }

  private async runWorkerLoop(workerId: number) {
    let consecutiveFailures = 0;

    while (this.isRunning) {
      // Check total registration limit
      if (this.config.maxTotalRegistrations && this.config.maxTotalRegistrations > 0) {
        const totalCompleted = this.stats.success + this.stats.failed;
        if (totalCompleted >= this.config.maxTotalRegistrations) {
          this.emitLog(`Worker #${workerId}: 已达到总注册上限 (${this.config.maxTotalRegistrations})，停止任务`, 'info', workerId);
          break;
        }
      }

      try {
        this.stats.total++;
        this.stats.running++;
        this.emitStats();

        const proxy: ProxyInfo | null = this.proxyManager ? await this.proxyManager.getNextProxy() : null;
        if (this.config.proxyConfig.mode === 'subscription' && proxy) {
          this.emitLog(`Worker #${workerId}: 切换到新节点 ${proxy.host}:${proxy.port}`, 'info', workerId);
        }
        const accountResult = await runSingleRegistration(
          workerId,
          this.config,
          proxy || undefined,
          (msg, lvl) => this.emitLog(msg, lvl, workerId)
        );

        this.stats.running--;
        if (accountResult.status === 'SUCCESS') {
          this.stats.success++;
          consecutiveFailures = 0;
          this.accountListeners.forEach(l => l(accountResult));
        } else {
          this.stats.failed++;
          consecutiveFailures++;

          // Classify the failure type from errorLog
          const failureType = this.extractFailureType(accountResult.errorLog || '');
          this.failureTypeCounts[failureType] = (this.failureTypeCounts[failureType] || 0) + 1;

          this.emitLog(`Worker #${workerId}: 失败类型 [${failureType}]，累计 ${this.failureTypeCounts[failureType]} 次`, 'warn', workerId);

          // Smart auto-stop: check if we should stop all workers
          const limit = FAILURE_TYPE_LIMITS[failureType as FailureType];
          if (limit && this.failureTypeCounts[failureType] >= limit) {
            this.emitLog(`Worker #${workerId}: ⚠️ 失败类型 [${failureType}] 已达到上限 (${limit}次)，自动停止所有任务`, 'error', workerId);
            this.isRunning = false;
            break;
          }

          if (proxy && this.proxyManager) {
            this.proxyManager.reportFailure(proxy);
          }
        }

        this.emitStats();
      } catch (err: any) {
        this.stats.running = Math.max(0, this.stats.running - 1);
        this.stats.failed++;
        consecutiveFailures++;
        this.emitStats();
        this.emitLog(`Worker #${workerId} 遇到致命未捕获异常: ${err?.message || err}`, 'error', workerId);
      }

      // Backoff logic based on consecutive failures
      if (consecutiveFailures > 0 && this.isRunning) {
        const threshold = [...BACKOFF_THRESHOLDS].reverse().find(t => consecutiveFailures >= t.failures);
        if (threshold) {
          if (threshold.delayMs === 0) {
            // Stop this worker
            this.emitLog(`Worker #${workerId}: 连续失败 ${consecutiveFailures} 次，停止该 Worker`, 'warn', workerId);
            break;
          } else {
            this.emitLog(`Worker #${workerId}: 连续失败 ${consecutiveFailures} 次，暂停 ${threshold.label} 后重试`, 'warn', workerId);
            await new Promise(r => setTimeout(r, threshold.delayMs));
            continue;
          }
        }
      }

      // Normal delay between task runs
      if (this.isRunning) {
        await new Promise(r => setTimeout(r, 2000));
      }
    }
  }
}
