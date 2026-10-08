/// 安全工具箱的本地小配置：Shodan API Key 与全局利用参数。
///
/// 全部走 `SettingsStore` 的工具配置（`config/security-toolbox.json`），与
/// GitHub token 同一处。不用 `flutter_secure_storage`：那是密码库的凭证容器，
/// 语义不同；Shodan Key 可从账户页随时轮换，随配置走更有用。
///
/// LHOST/LPORT 缺省时探测本机主网卡 IP——用户没配过不代表该填错，
/// 填错的 LHOST 会让 meterpreter 回连到错误地址，而那个错误只在会话建立失败后
/// 才可见，所以探测 + 事后高亮双保险。
library;

import '../../../services/settings_store.dart';
import 'exploit_services.dart';
import 'lan_recon_services.dart';

/// 配置键名。集中在此，避免读写两侧漂移。
abstract final class SecuritySettingKeys {
  static const String shodanApiKey = 'shodan_api_key';
  static const String exploitLhost = 'exploit_lhost';
  static const String exploitLport = 'exploit_lport';
}

class SecuritySettingsStore {
  SecuritySettingsStore._();
  static final SecuritySettingsStore instance = SecuritySettingsStore._();

  static const String toolId = 'security-toolbox';

  Future<Map<String, dynamic>> _read() =>
      SettingsStore.instance.readToolConfig(toolId);

  Future<void> _write(Map<String, dynamic> data) =>
      SettingsStore.instance.writeToolConfig(toolId, data);

  // ---------------------------------------------------------------------------
  // Shodan
  // ---------------------------------------------------------------------------

  Future<String> shodanKey() async {
    final config = await _read();
    return (config[SecuritySettingKeys.shodanApiKey] as String? ?? '').trim();
  }

  Future<bool> hasShodanKey() async =>
      (await shodanKey()).isNotEmpty;

  Future<void> saveShodanKey(String key) async {
    final config = await _read();
    await _write({
      ...config,
      SecuritySettingKeys.shodanApiKey: key.trim(),
    });
  }

  Future<void> clearShodanKey() async {
    final config = await _read();
    config.remove(SecuritySettingKeys.shodanApiKey);
    await _write(config);
  }

  // ---------------------------------------------------------------------------
  // 全局利用参数
  // ---------------------------------------------------------------------------

  /// 读取全局 LHOST/LPORT；未配置时探测本机 IP 兜底、端口默认 4444。
  Future<ExploitDefaults> exploitDefaults() async {
    final config = await _read();
    final lhost = (config[SecuritySettingKeys.exploitLhost] as String? ?? '')
        .trim();
    final lport = (config[SecuritySettingKeys.exploitLport] as num?)?.toInt();

    String host = lhost;
    if (host.isEmpty) {
      host = await detectPrimaryLanIp() ?? '127.0.0.1';
    }
    return ExploitDefaults(lhost: host, lport: lport ?? 4444);
  }

  Future<void> saveExploitDefaults(String lhost, int lport) async {
    final config = await _read();
    await _write({
      ...config,
      SecuritySettingKeys.exploitLhost: lhost.trim(),
      SecuritySettingKeys.exploitLport: lport,
    });
  }

  /// 本机主网卡 IPv4：第一个非 loopback 接口。
  ///
  /// 取不到时返回 null，调用方回落到 127.0.0.1——反弹到本机在单机演练时
  /// 是合法目标，填错成 0.0.0.0 反而更糟。
  Future<String?> detectPrimaryLanIp() async {
    try {
      final ifaces = await NetworkInterfaceDetector.detect();
      if (ifaces.isEmpty) return null;
      // 优先 192.168/10.172 这类真实内网段，跳过 VPN 隧道（utun* 多为 198.18.x）。
      final lan = ifaces.firstWhere(
        (i) =>
            i.ipv4.startsWith('192.168.') ||
            i.ipv4.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(i.ipv4),
        orElse: () => ifaces.first,
      );
      return lan.ipv4;
    } catch (_) {
      return null;
    }
  }

  /// 是否已显式配置过 LHOST（决定 UI 显示"未配置，已用探测值"还是实际值）。
  Future<bool> hasExploitLhost() async {
    final config = await _read();
    return (config[SecuritySettingKeys.exploitLhost] as String? ?? '')
        .trim()
        .isNotEmpty;
  }
}

/// API Key 脱敏展示：仅留末 4 位。
///
/// 空串与过短的 key 返回固定占位，不泄露任何片段——短 key 本身就是配错了。
String maskApiKey(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) return '未配置';
  if (trimmed.length <= 4) return '****';
  return '****${trimmed.substring(trimmed.length - 4)}';
}
