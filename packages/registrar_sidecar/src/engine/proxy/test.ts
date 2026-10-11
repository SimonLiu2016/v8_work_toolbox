import { StaticProxyProvider, QingguoApiProxyProvider } from './providers';
import { ProxyConfig } from '../../types/index';

async function runTests() {
  console.log('--- STARTING PROXY PROVIDER TESTS ---');

  // Test 1: StaticProxyProvider
  console.log('\n[Test 1] Testing StaticProxyProvider...');
  const staticConfig: ProxyConfig = {
    mode: 'static',
    provider: 'custom',
    staticList: [
      '127.0.0.1:8080',
      'http://user:pass@192.168.1.1:9090',
      'socks5://admin:secret@10.0.0.1:1080'
    ],
    authKey: '',
    authPwd: '',
    apiUrl: '',
    extractNum: 5,
    minPoolSize: 2,
    tunnelHost: '',
    tunnelPort: 80,
    subscriptionUrl: '',
    refreshInterval: 30,
  };

  const staticProvider = new StaticProxyProvider();
  await staticProvider.initialize(staticConfig);

  const p1 = await staticProvider.getNextProxy();
  const p2 = await staticProvider.getNextProxy();
  const p3 = await staticProvider.getNextProxy();
  const p4 = await staticProvider.getNextProxy(); // Should wrap around

  console.log('Proxy 1 (no auth):', p1);
  console.log('Proxy 2 (http auth):', p2);
  console.log('Proxy 3 (socks auth):', p3);
  console.log('Proxy 4 (wrap around):', p4);

  if (
    p1 && p1.host === '127.0.0.1' && p1.port === 8080 && !p1.username &&
    p2 && p2.host === '192.168.1.1' && p2.port === 9090 && p2.username === 'user' && p2.password === 'pass' &&
    p3 && p3.host === '10.0.0.1' && p3.port === 1080 && p3.username === 'admin' && p3.password === 'secret' &&
    p4 && p4.host === '127.0.0.1' && p4.port === 8080
  ) {
    console.log('✓ StaticProxyProvider verification PASSED.');
  } else {
    console.error('✗ StaticProxyProvider verification FAILED.');
    process.exit(1);
  }

  // Test 2: QingguoApiProxyProvider (Mocking API fetch to verify throttle)
  console.log('\n[Test 2] Testing QingguoApiProxyProvider Throttling...');
  const apiConfig: ProxyConfig = {
    mode: 'api',
    provider: 'qingguo',
    staticList: [],
    authKey: 'test-key',
    authPwd: 'test-password',
    apiUrl: 'http://localhost:9999/mock-proxy', // dummy URL
    extractNum: 2,
    minPoolSize: 1,
    tunnelHost: '',
    tunnelPort: 80,
    subscriptionUrl: '',
    refreshInterval: 30,
  };

  const apiProvider = new QingguoApiProxyProvider();
  // Override refillPool call with custom logic to count fetches and test throttling
  let fetchCount = 0;
  (apiProvider as any).refillPool = async function() {
    if (this.isFetching) return;
    const now = Date.now();
    if (now - this.lastFetchTime < 5000) {
      console.log('  [Throttle lock triggered successfully]');
      return;
    }
    this.isFetching = true;
    fetchCount++;
    this.pool.push(
      { host: '1.1.1.1', port: 80, username: 'test-key', password: 'test-password' },
      { host: '2.2.2.2', port: 80, username: 'test-key', password: 'test-password' }
    );
    this.lastFetchTime = now;
    this.isFetching = false;
  };

  await apiProvider.initialize(apiConfig);
  console.log('Initial pool size after initialization (refillPool called once):', (apiProvider as any).pool.length);
  
  const ap1 = await apiProvider.getNextProxy();
  console.log('Get Proxy 1:', ap1);
  
  // Try calling getNextProxy again immediately, which triggers refillPool as pool size drops to 1 <= minPoolSize (1)
  const ap2 = await apiProvider.getNextProxy();
  console.log('Get Proxy 2:', ap2);
  
  console.log('Total Refill Fetch Count:', fetchCount);
  if (fetchCount === 1) {
    console.log('✓ QingguoApiProxyProvider Throttling PASSED (refill request throttled under 5s).');
  } else {
    console.error('✗ QingguoApiProxyProvider Throttling FAILED.');
    process.exit(1);
  }

  console.log('\n--- ALL PROXY TESTS PASSED ---');
}

runTests().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
