import { spawn } from 'child_process';
import * as path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function runSelfCheck() {
  console.log('[Sidecar Self-Check] Starting sidecar self-check test...');
  const cliPath = path.join(__dirname, 'cli.ts');
  const child = spawn('npx', ['tsx', cliPath], {
    stdio: ['pipe', 'pipe', 'inherit'],
  });

  let readyReceived = false;
  let pongReceived = false;

  child.stdout.on('data', (data) => {
    const lines = data.toString().split('\n').filter(Boolean);
    for (const line of lines) {
      console.log('[Sidecar Output]:', line);
      try {
        const msg = JSON.parse(line);
        if (msg.type === 'ready') {
          readyReceived = true;
          // Send ping
          const pingCmd = JSON.stringify({ id: 'test-1', action: 'ping' }) + '\n';
          child.stdin.write(pingCmd);
        }
        if (msg.type === 'pong' && msg.data?.id === 'test-1') {
          pongReceived = true;
          console.log('[Sidecar Self-Check] ✅ Ping/Pong test passed!');
          child.kill('SIGTERM');
        }
      } catch (e) {
        // Non-JSON output
      }
    }
  });

  child.on('exit', (code) => {
    console.log(`[Sidecar Self-Check] Child process exited with code ${code}`);
    if (readyReceived && pongReceived) {
      console.log('[Sidecar Self-Check] 🎉 ALL TESTS PASSED!');
      process.exit(0);
    } else {
      console.error('[Sidecar Self-Check] ❌ Test failed: ready or pong not received');
      process.exit(1);
    }
  });
}

runSelfCheck();
