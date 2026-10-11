import net from 'net';

const TIMEOUT_MS = 5000;

const cache = new Map<string, { latency: number; timestamp: number }>();
const CACHE_TTL = 60_000;

interface ProxyNode {
  id: string;
  server: string;
  port: number;
}

interface SpeedTestResult {
  id: string;
  latency: number | null;
}

export async function batchTestProxySpeed(nodes: ProxyNode[]): Promise<SpeedTestResult[]> {
  const results = await Promise.allSettled(
    nodes.map(async (node) => {
      const latency = await testProxySpeed(node.server, node.port);
      return { id: node.id, latency };
    })
  );

  return results.map((result, index) => {
    if (result.status === 'fulfilled') {
      return result.value;
    }
    return { id: nodes[index].id, latency: null };
  });
}

export async function testProxySpeed(proxyHost: string, proxyPort: number): Promise<number | null> {
  const cacheKey = `${proxyHost}:${proxyPort}`;
  const cached = cache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.latency;
  }

  return new Promise((resolve) => {
    const start = Date.now();
    const socket = net.createConnection({ host: proxyHost, port: proxyPort }, () => {
      const latency = Date.now() - start;
      socket.destroy();
      cache.set(cacheKey, { latency, timestamp: Date.now() });
      resolve(latency);
    });

    socket.on('error', () => resolve(null));
    socket.setTimeout(TIMEOUT_MS, () => {
      socket.destroy();
      resolve(null);
    });
  });
}
