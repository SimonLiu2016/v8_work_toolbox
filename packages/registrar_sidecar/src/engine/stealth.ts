import { pick } from './helpers';

// ──────────────────────────────────────────────────────────────
// Browser context randomization pools
// ──────────────────────────────────────────────────────────────

export const USER_AGENTS = [
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
];

export const VIEWPORTS = [
  { width: 1366, height: 768 },
  { width: 1440, height: 900 },
  { width: 1536, height: 864 },
  { width: 1920, height: 1080 },
  { width: 1600, height: 900 },
  { width: 1280, height: 800 },
];

export const LOCALE_TZ_PAIRS: { locale: string; tz: string }[] = [
  { locale: 'en-US', tz: 'America/New_York' },
  { locale: 'en-US', tz: 'America/Chicago' },
  { locale: 'en-US', tz: 'America/Los_Angeles' },
  { locale: 'en-US', tz: 'America/Denver' },
  { locale: 'en-GB', tz: 'Europe/London' },
  { locale: 'en-CA', tz: 'America/Toronto' },
  { locale: 'en-AU', tz: 'Australia/Sydney' },
];

// ──────────────────────────────────────────────────────────────
// GPU fingerprint pools by platform
// ──────────────────────────────────────────────────────────────

export const GPU_POOL: Record<string, string[]> = {
  mac: [
    'Apple M1',
    'Apple M2',
    'Apple M3',
    'Intel UHD Graphics 630',
    'AMD Radeon Pro 5300M',
    'Intel Iris Plus Graphics',
  ],
  windows: [
    'NVIDIA GeForce RTX 3060',
    'NVIDIA GeForce RTX 4070',
    'Intel UHD Graphics 770',
    'Intel Iris Xe Graphics',
    'AMD Radeon RX 580',
    'AMD Radeon RX 6700 XT',
  ],
  linux: [
    'Mesa Intel UHD Graphics',
    'Mesa Intel Iris Xe Graphics',
    'NVIDIA GeForce GTX 1650',
    'NVIDIA GeForce RTX 3060',
    'AMD Radeon RX 560',
    'AMD Radeon RX 6600',
  ],
};

/**
 * Generates realistic Chrome Client Hints & HTTP Request Headers matching
 * the randomized User-Agent and Locale to bypass server-side WAF fingerprinting.
 */
export function generateHTTPHeaders(ua: string, locale: string): Record<string, string> {
  const isMac = ua.includes('Macintosh');
  const isWin = ua.includes('Windows');
  const platform = isMac ? '"macOS"' : isWin ? '"Windows"' : '"Linux"';

  const chromeVerMatch = ua.match(/Chrome\/(\d+)/);
  const chromeVer = chromeVerMatch ? chromeVerMatch[1] : '136';

  const secChUa = `"Not(A:Brand";v="99", "Google Chrome";v="${chromeVer}", "Chromium";v="${chromeVer}"`;

  const acceptLang = locale.includes('zh')
    ? 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7'
    : locale.includes('GB')
    ? 'en-GB,en;q=0.9,en-US;q=0.8'
    : locale.includes('CA')
    ? 'en-CA,en-US;q=0.9,en;q=0.8'
    : locale.includes('AU')
    ? 'en-AU,en-US;q=0.9,en;q=0.8'
    : 'en-US,en;q=0.9';

  return {
    'Accept-Language': acceptLang,
  };
}

/**
 * Determines the platform key for GPU pool lookup from a User-Agent string.
 */
export function getPlatformFromUA(ua: string): 'mac' | 'windows' | 'linux' {
  if (ua.includes('Macintosh')) return 'mac';
  if (ua.includes('Windows')) return 'windows';
  return 'linux';
}

// ──────────────────────────────────────────────────────────────
// Comprehensive stealth init script
// ──────────────────────────────────────────────────────────────

export function buildStealthScript(ua: string, locale: string): string {
  const isMac = ua.includes('Macintosh');
  const isWin = ua.includes('Windows');
  const platform = isMac ? 'MacIntel' : isWin ? 'Win32' : 'Linux x86_64';
  const oscpu = isMac ? 'Intel Mac OS X 10_15_7' : isWin ? 'Windows NT 10.0; Win64; x64' : 'Linux x86_64';
  const hwConcurrency = pick([4, 6, 8, 12, 16]);
  const deviceMemory = pick([4, 8, 16]);

  // GPU fingerprint matching the platform
  const platformKey = getPlatformFromUA(ua);
  const gpuVendor = isMac ? 'Apple' : isWin ? 'Google Inc. (NVIDIA)' : 'Google Inc. (Mesa)';
  const gpuRenderer = pick(GPU_POOL[platformKey]);

  // Languages matching the locale
  const languages = locale.startsWith('en')
    ? `'${locale}', 'en'`
    : `'${locale}', 'en-US', 'en'`;

  return `
    (() => {
      // ── Core anti-detection patches ──
      Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
      delete navigator.__proto__.webdriver;
      Object.defineProperty(navigator, 'platform', { get: () => '${platform}' });
      Object.defineProperty(navigator, 'oscpu', { get: () => '${oscpu}' });
      Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => ${hwConcurrency} });
      Object.defineProperty(navigator, 'deviceMemory', { get: () => ${deviceMemory} });
      Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 0 });
      Object.defineProperty(navigator, 'languages', { get: () => [${languages}] });
      Object.defineProperty(navigator, 'language', { get: () => '${locale}' });
      Object.defineProperty(navigator, 'vendor', { get: () => 'Google Inc.' });

      // ── Chrome object detection bypass ──
      if (!window.chrome) {
        window.chrome = {};
      }
      if (!window.chrome.runtime) {
        window.chrome.runtime = {};
      }

      // ── Realistic plugins array ──
      const mkPlugin = (name, desc, filename) => {
        const p = { name, description: desc, filename, length: 1 };
        p[0] = { type: 'application/x-google-chrome-pdf', suffixes: 'pdf', description: 'Portable Document Format' };
        return p;
      };
      const pluginArr = [
        mkPlugin('Chrome PDF Plugin', 'Portable Document Format', 'internal-pdf-viewer'),
        mkPlugin('Chrome PDF Viewer', '', 'mhjfbmdgcfjbbpaeojofohoefgiehjai'),
        mkPlugin('Native Client', '', 'internal-nacl-plugin'),
      ];
      pluginArr.item = (i) => pluginArr[i];
      pluginArr.namedItem = (n) => pluginArr.find(p => p.name === n) || null;
      pluginArr.refresh = () => {};
      Object.defineProperty(navigator, 'plugins', { get: () => pluginArr });

      // ── MimeTypes ──
      const mimeArr = [{ type: 'application/pdf', suffixes: 'pdf', description: 'Portable Document Format' }];
      mimeArr.item = (i) => mimeArr[i];
      mimeArr.namedItem = (n) => mimeArr.find(m => m.type === n) || null;
      Object.defineProperty(navigator, 'mimeTypes', { get: () => mimeArr });

      // ── Chrome runtime object ──
      window.chrome = {
        runtime: {
          connect: () => {},
          sendMessage: () => {},
          onMessage: { addListener: () => {}, removeListener: () => {} },
          onConnect: { addListener: () => {}, removeListener: () => {} },
          id: undefined,
        },
        loadTimes: () => ({
          commitLoadTime: Date.now() / 1000 - Math.random() * 2,
          connectionInfo: 'h2',
          finishDocumentLoadTime: Date.now() / 1000 - Math.random(),
          finishLoadTime: Date.now() / 1000 - Math.random() * 0.5,
          firstPaintAfterLoadTime: 0,
          firstPaintTime: Date.now() / 1000 - Math.random() * 1.5,
          navigationType: 'Other',
          npnNegotiatedProtocol: 'h2',
          requestTime: Date.now() / 1000 - Math.random() * 3,
          startLoadTime: Date.now() / 1000 - Math.random() * 2.5,
          wasAlternateProtocolAvailable: false,
          wasFetchedViaSpdy: true,
          wasNpnNegotiated: true,
        }),
        csi: () => ({
          onloadT: Date.now(),
          pageT: Math.random() * 2000 + 500,
          startE: Date.now() - Math.floor(Math.random() * 3000),
          tran: 15,
        }),
        app: {
          isInstalled: false,
          InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
          RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' },
        },
      };

      // ── Notification permission ──
      if (typeof Notification !== 'undefined') {
        Object.defineProperty(Notification, 'permission', { get: () => 'default' });
      }

      // ── Permissions API ──
      const origQuery = navigator.permissions && navigator.permissions.query;
      if (origQuery) {
        navigator.permissions.query = (params) => {
          if (params.name === 'notifications') {
            return Promise.resolve({ state: 'prompt', onchange: null });
          }
          return origQuery.call(navigator.permissions, params);
        };
      }

      // ── Document focus ──
      Object.defineProperty(document, 'hasFocus', { value: () => true });
      Object.defineProperty(document, 'hidden', { get: () => false });
      Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });

      // ── Screen properties ──
      Object.defineProperty(screen, 'colorDepth', { get: () => 24 });
      Object.defineProperty(screen, 'pixelDepth', { get: () => 24 });

      // ── Canvas fingerprint noise ──
      const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
      HTMLCanvasElement.prototype.toDataURL = function(type) {
        const ctx = this.getContext('2d');
        if (ctx && this.width > 0 && this.height > 0) {
          try {
            const imgData = ctx.getImageData(0, 0, Math.min(this.width, 2), Math.min(this.height, 2));
            for (let i = 0; i < imgData.data.length; i += 4) {
              imgData.data[i] = imgData.data[i] ^ (Math.floor(Math.random() * 3));
            }
            ctx.putImageData(imgData, 0, 0);
          } catch(e) {}
        }
        return origToDataURL.apply(this, arguments);
      };

      const origToBlob = HTMLCanvasElement.prototype.toBlob;
      HTMLCanvasElement.prototype.toBlob = function(callback, type, quality) {
        const ctx = this.getContext('2d');
        if (ctx && this.width > 0 && this.height > 0) {
          try {
            const imgData = ctx.getImageData(0, 0, Math.min(this.width, 2), Math.min(this.height, 2));
            for (let i = 0; i < imgData.data.length; i += 4) {
              imgData.data[i] = imgData.data[i] ^ (Math.floor(Math.random() * 3));
            }
            ctx.putImageData(imgData, 0, 0);
          } catch(e) {}
        }
        return origToBlob.apply(this, arguments);
      };

      // ── WebGL fingerprint (platform-matched) ──
      const getParameter = WebGLRenderingContext.prototype.getParameter;
      WebGLRenderingContext.prototype.getParameter = function(parameter) {
        if (parameter === 37445) return '${gpuVendor}';
        if (parameter === 37446) return '${gpuRenderer}';
        return getParameter.apply(this, [parameter]);
      };
      if (typeof WebGL2RenderingContext !== 'undefined') {
        const getParameter2 = WebGL2RenderingContext.prototype.getParameter;
        WebGL2RenderingContext.prototype.getParameter = function(parameter) {
          if (parameter === 37445) return '${gpuVendor}';
          if (parameter === 37446) return '${gpuRenderer}';
          return getParameter2.apply(this, [parameter]);
        };
      }

      // ── AudioContext fingerprint noise ──
      if (typeof AudioContext !== 'undefined' || typeof OfflineAudioContext !== 'undefined') {
        const origGetFloatFreq = AnalyserNode.prototype.getFloatFrequencyData;
        AnalyserNode.prototype.getFloatFrequencyData = function(array) {
          origGetFloatFreq.call(this, array);
          for (let i = 0; i < array.length; i++) {
            array[i] = array[i] + (Math.random() * 0.0001 - 0.00005);
          }
        };
      }

      // ── Connection info ──
      if (!navigator.connection) {
        Object.defineProperty(navigator, 'connection', {
          get: () => ({
            effectiveType: '4g',
            rtt: ${pick([50, 75, 100])},
            downlink: ${pick([5, 10, 15])},
            saveData: false,
          })
        });
      }

      // ── Battery API ──
      if (navigator.getBattery) {
        const origGetBattery = navigator.getBattery;
        navigator.getBattery = () => Promise.resolve({
          charging: true,
          chargingTime: 0,
          dischargingTime: Infinity,
          level: ${pick([0.8, 0.9, 1.0])},
          addEventListener: () => {},
          removeEventListener: () => {},
          onchargingchange: null,
          onchargingtimechange: null,
          ondischargingtimechange: null,
          onlevelchange: null,
        });
      }

      // ── Web Bluetooth API ──
      if (!navigator.bluetooth) {
        Object.defineProperty(navigator, 'bluetooth', {
          get: () => ({
            requestDevice: () => Promise.reject(new Error('NotAllowedError')),
            getAvailability: () => Promise.resolve(false),
            addEventListener: () => {},
            removeEventListener: () => {},
          })
        });
      }

      // ── Permissions API extended ──
      const origPermQuery = navigator.permissions.query;
      navigator.permissions.query = (params) => {
        const denied = ['camera', 'microphone', 'geolocation', 'notifications', 'midi'];
        if (denied.includes(params.name)) {
          return Promise.resolve({ state: 'prompt', onchange: null });
        }
        return origPermQuery.call(navigator.permissions, params);
      };

      // ── Console.debug override (headless detection) ──
      const origDebug = console.debug;
      console.debug = function() {
        // Some bots call console.debug with特定字符串
        return origDebug.apply(this, arguments);
      };

      // ── Window dimensions consistency ──
      if (window.outerHeight === 0) {
        Object.defineProperty(window, 'outerHeight', { get: () => window.innerHeight });
      }
      if (window.outerWidth === 0) {
        Object.defineProperty(window, 'outerWidth', { get: () => window.innerWidth });
      }

      // ── Speech synthesis voices ──
      if (window.speechSynthesis) {
        const origGetVoices = window.speechSynthesis.getVoices;
        window.speechSynthesis.getVoices = () => {
          const voices = origGetVoices.call(window.speechSynthesis);
          if (voices.length === 0) {
            return [
              { name: 'Microsoft David - English (United States)', lang: 'en-US', default: true, localService: true, voiceURI: 'Microsoft David - English (United States)' },
              { name: 'Microsoft Zira - English (United States)', lang: 'en-US', default: false, localService: true, voiceURI: 'Microsoft Zira - English (United States)' },
            ];
          }
          return voices;
        };
      }
    })();
  `;
}
