import * as readline from 'readline';
import { WorkerPoolManager } from './engine/workerPool.js';
import { TaskConfig, LogEntry, TaskStats, AccountRecord } from './types/index.js';
import { testImapConnection } from './engine/email/qqMailImap.js';

let pool: WorkerPoolManager | null = null;

function sendEvent(type: string, data: any) {
  const payload = JSON.stringify({ type, data });
  process.stdout.write(payload + '\n');
}

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false,
});

rl.on('line', async (line: string) => {
  const trimmed = line.trim();
  if (!trimmed) return;

  try {
    const message = JSON.parse(trimmed);
    const { id, action, payload } = message;

    switch (action) {
      case 'ping': {
        sendEvent('pong', { id, timestamp: Date.now() });
        break;
      }

      case 'start': {
        const config: TaskConfig = payload;
        if (pool) {
          pool.stop();
        }

        pool = new WorkerPoolManager(config);

        pool.onLog((log: LogEntry) => {
          sendEvent('log', log);
        });

        pool.onStats((stats: TaskStats) => {
          sendEvent('stats', stats);
        });

        pool.onAccount((account: AccountRecord) => {
          sendEvent('account', account);
        });

        sendEvent('started', { id, concurrency: config.concurrency });
        // Start running asynchronously
        pool.start().catch((err: any) => {
          sendEvent('error', { id, message: err?.message || String(err) });
        });
        break;
      }

      case 'stop': {
        if (pool) {
          pool.stop();
          pool = null;
        }
        sendEvent('stopped', { id });
        break;
      }

      case 'testImap': {
        const res = await testImapConnection(payload, payload?.emailAddress);
        sendEvent('imapResult', { id, ...res });
        break;
      }

      default: {
        sendEvent('unknownAction', { id, action });
      }
    }
  } catch (err: any) {
    sendEvent('error', { message: err?.message || String(err) });
  }
});

process.on('SIGINT', () => {
  if (pool) pool.stop();
  process.exit(0);
});

process.on('SIGTERM', () => {
  if (pool) pool.stop();
  process.exit(0);
});

sendEvent('ready', { version: '1.0.0' });
