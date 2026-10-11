import * as yaml from 'js-yaml';
import https from 'https';
import http from 'http';
import { URL } from 'url';

export interface ClashProxy {
  name: string;
  type: string;
  server: string;
  port: number;
  [key: string]: any;
}

export interface ParsedProxy {
  id: string;
  name: string;
  type: string;
  server: string;
  port: number;
  config: Record<string, any>;
}

const CLASH_TYPE_MAP: Record<string, string> = {
  ss: 'shadowsocks',
  shadowsocks: 'shadowsocks',
  vmess: 'vmess',
  trojan: 'trojan',
  vless: 'vless',
  ssr: 'shadowsocks',
  anytls: 'anytls',
  hysteria2: 'hysteria2',
  hy2: 'hysteria2',
  wireguard: 'wireguard',
  tuic: 'tuic',
};

export async function fetchSubscription(url: string, maxRedirects = 5): Promise<string> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const client = parsed.protocol === 'https:' ? https : http;

    const req = client.get(parsed, {
      headers: { 'User-Agent': 'clash-verge' },
      timeout: 15000,
    }, (res) => {
      if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        if (maxRedirects <= 0) {
          reject(new Error('Too many redirects'));
          return;
        }
        const redirectUrl = new URL(res.headers.location, url).toString();
        fetchSubscription(redirectUrl, maxRedirects - 1).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode !== 200) {
        res.resume();
        reject(new Error(`HTTP ${res.statusCode}`));
        return;
      }
      const chunks: Buffer[] = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
  });
}

export function parseSubscription(content: string): ParsedProxy[] {
  const trimmed = content.trim();

  if (trimmed.startsWith('{') || trimmed.startsWith('proxies:')) {
    return parseYamlContent(trimmed);
  }

  try {
    const decoded = Buffer.from(trimmed, 'base64').toString('utf-8');
    if (decoded.includes('://') || decoded.includes('proxies:')) {
      if (decoded.includes('proxies:')) {
        return parseYamlContent(decoded);
      }
      return parseLinkList(decoded);
    }
  } catch {}

  return parseYamlContent(trimmed);
}

function parseYamlContent(content: string): ParsedProxy[] {
  const doc = yaml.load(content) as any;
  if (!doc?.proxies || !Array.isArray(doc.proxies)) return [];

  return doc.proxies
    .filter((p: any) => CLASH_TYPE_MAP[p.type])
    .map((p: any) => convertClashProxy(p));
}

function parseLinkList(content: string): ParsedProxy[] {
  const lines = content.split('\n').filter(l => l.trim());
  const proxies: ParsedProxy[] = [];

  for (const line of lines) {
    try {
      const decoded = decodeURIComponent(line.trim());
      if (decoded.startsWith('ss://')) {
        const proxy = parseShadowsocksLink(decoded);
        if (proxy) proxies.push(proxy);
      } else if (decoded.startsWith('vmess://')) {
        const proxy = parseVmessLink(decoded);
        if (proxy) proxies.push(proxy);
      } else if (decoded.startsWith('trojan://')) {
        const proxy = parseTrojanLink(decoded);
        if (proxy) proxies.push(proxy);
      } else if (decoded.startsWith('vless://')) {
        const proxy = parseVlessLink(decoded);
        if (proxy) proxies.push(proxy);
      }
    } catch {}
  }

  return proxies;
}

function convertClashProxy(p: any): ParsedProxy {
  const type = CLASH_TYPE_MAP[p.type] || p.type;
  const config: Record<string, any> = {};

  if (type === 'shadowsocks') {
    config.password = p.password;
    config.cipher = p.cipher;
    if (p['udp-relay']) config.udp = true;
  } else if (type === 'vmess') {
    config.uuid = p.uuid;
    config.alterId = p.alterId || 0;
    config.cipher = p.cipher || 'auto';
    if (p.tls) config.tls = true;
    if (p.network) config.network = p.network;
    if (p['ws-opts']) config.wsOpts = p['ws-opts'];
    if (p['grpc-opts']) config.grpcOpts = p['grpc-opts'];
  } else if (type === 'trojan') {
    config.password = p.password;
    if (p.sni) config.sni = p.sni;
    if (p['skip-cert-verify']) config.skipCertVerify = true;
  } else if (type === 'vless') {
    config.uuid = p.uuid;
    if (p.tls) config.tls = true;
    if (p.network) config.network = p.network;
    if (p['ws-opts']) config.wsOpts = p['ws-opts'];
    if (p.flow) config.flow = p.flow;
  } else if (type === 'anytls') {
    config.password = p.password;
    if (p.sni) config.sni = p.sni;
    if (p['skip-cert-verify']) config.skipCertVerify = true;
    if (p['client-fingerprint']) config.fingerprint = p['client-fingerprint'];
    if (p.alpn) config.alpn = p.alpn;
  } else if (type === 'hysteria2') {
    config.password = p.password;
    if (p.sni) config.sni = p.sni;
    if (p['skip-cert-verify']) config.skipCertVerify = true;
    if (p.obfs) config.obfs = p.obfs;
    if (p['obfs-password']) config.obfsPassword = p['obfs-password'];
  } else {
    // Generic: copy all known fields
    if (p.password) config.password = p.password;
    if (p.uuid) config.uuid = p.uuid;
    if (p.sni) config.sni = p.sni;
    if (p.tls) config.tls = true;
    if (p['skip-cert-verify']) config.skipCertVerify = true;
  }

  return {
    id: `${type}-${p.name}-${p.port}`,
    name: p.name,
    type,
    server: p.server,
    port: p.port,
    config,
  };
}

function parseShadowsocksLink(link: string): ParsedProxy | null {
  try {
    const withoutScheme = link.slice(5);
    const [serverPart, ...rest] = withoutScheme.split('#');
    const name = decodeURIComponent(rest.join('#') || 'ss');

    let userinfo: string, hostport: string;
    if (serverPart.includes('@')) {
      [userinfo, hostport] = serverPart.split('@');
    } else {
      const decoded = Buffer.from(serverPart, 'base64').toString('utf-8');
      [userinfo, hostport] = decoded.split('@');
    }

    const [server, portStr] = hostport.split(':');
    const port = parseInt(portStr, 10);

    let cipher: string, password: string;
    if (userinfo.includes(':')) {
      const decoded = Buffer.from(userinfo, 'base64').toString('utf-8');
      [cipher, password] = decoded.split(':');
    } else {
      return null;
    }

    return {
      id: `ss-${name}-${port}`,
      name,
      type: 'shadowsocks',
      server,
      port,
      config: { cipher, password },
    };
  } catch { return null; }
}

function parseVmessLink(link: string): ParsedProxy | null {
  try {
    const base64 = link.slice(8);
    const json = Buffer.from(base64, 'base64').toString('utf-8');
    const obj = JSON.parse(json);
    return {
      id: `vmess-${obj.ps || obj.add}-${obj.port}`,
      name: obj.ps || `${obj.add}:${obj.port}`,
      type: 'vmess',
      server: obj.add,
      port: parseInt(String(obj.port), 10),
      config: {
        uuid: obj.id,
        alterId: obj.aid || 0,
        cipher: obj.scy || 'auto',
        tls: obj.tls === 'tls',
      },
    };
  } catch { return null; }
}

function parseTrojanLink(link: string): ParsedProxy | null {
  try {
    const withoutScheme = link.slice(9);
    const [serverPart, ...rest] = withoutScheme.split('#');
    const name = decodeURIComponent(rest.join('#') || 'trojan');

    const [userinfo, hostport] = serverPart.split('@');
    const password = decodeURIComponent(userinfo);
    const [server, portStr] = hostport.split(':');
    const port = parseInt(portStr, 10);

    return {
      id: `trojan-${name}-${port}`,
      name,
      type: 'trojan',
      server,
      port,
      config: { password },
    };
  } catch { return null; }
}

function parseVlessLink(link: string): ParsedProxy | null {
  try {
    const withoutScheme = link.slice(8);
    const [serverPart, ...rest] = withoutScheme.split('#');
    const name = decodeURIComponent(rest.join('#') || 'vless');

    const [uuid, hostport] = serverPart.split('@');
    const [server, portStr] = hostport.split(':');
    const port = parseInt(portStr, 10);

    return {
      id: `vless-${name}-${port}`,
      name,
      type: 'vless',
      server,
      port,
      config: { uuid },
    };
  } catch { return null; }
}
