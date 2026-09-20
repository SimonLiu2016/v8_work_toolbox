import 'dart:async';

import 'package:flutter/foundation.dart';

import 'settings_store.dart';

/// 应用级显式代理通道配置。
///
/// 代理地址不是密钥（无 token、无密码），存明文配置文件 `config/proxy.json`，
/// 与 `ai_config.json` 中 `baseUrl` 的处理一致，不写入 Keychain。未配置
/// （`enabled == false` 或 `host` 为空）时，应用保持直连行为。
///
/// 变更后调用 [save] 持久化并通知监听者重建 HTTP 客户端。见
/// [AppHttpClient.create] 与 [AiService.rebuildHttpClient]。
class ProxySettings extends ChangeNotifier {
  ProxySettings._();
  static final ProxySettings instance = ProxySettings._();

  static const String _configId = 'proxy';

  String _host = '';
  int _port = 0;
  bool _enabled = false;

  String get host => _host;
  int get port => _port;
  bool get enabled => _enabled;
  bool get isConfigured => _enabled && _host.isNotEmpty && _port > 0;

  /// 从持久化存储加载。未配置时返回默认（直连）。
  Future<void> load() async {
    final json = await SettingsStore.instance.readToolConfig(_configId);
    _host = (json['host'] as String?)?.trim() ?? '';
    _port = (json['port'] as num?)?.toInt() ?? 0;
    _enabled = json['enabled'] as bool? ?? false;
    notifyListeners();
  }

  /// 未配置时抛 [ArgumentError]，此前生效的配置保持不变。
  Future<void> save({required String host, required int port, required bool enabled}) async {
    _validate(host, port);
    _host = host.trim();
    _port = port;
    _enabled = enabled;
    await SettingsStore.instance.writeToolConfig(_configId, {
      'host': _host,
      'port': _port,
      'enabled': _enabled,
    });
    notifyListeners();
  }

  void _validate(String host, int port) {
    final h = host.trim();
    if (h.isEmpty) {
      throw ArgumentError('代理主机不能为空');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('代理端口必须在 1-65535 之间（当前: $port）');
    }
  }

  /// 供 MCP 子进程环境注入用。未配置时返回空 Map，不注入任何代理变量。
  Map<String, String> toEnvVars() {
    if (!isConfigured) return const {};
    final url = 'http://$_host:$_port';
    return {
      'HTTP_PROXY': url,
      'HTTPS_PROXY': url,
      'ALL_PROXY': url,
      // 本机回环与私网段直连，避免代理自己也走代理
      'NO_PROXY': 'localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12',
      // 小写变体，部分工具只认小写
      'http_proxy': url,
      'https_proxy': url,
      'all_proxy': url,
      'no_proxy': 'localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12',
    };
  }

  /// 仅供测试注入状态，绕过持久化。生产代码用 [load] / [save]。
  @visibleForTesting
  void setForTesting({String host = '', int port = 0, bool enabled = false}) {
    _host = host;
    _port = port;
    _enabled = enabled;
    notifyListeners();
  }

  /// PAC 风格的代理字符串，供 `HttpClient.findProxy` 使用。未配置时返回 'DIRECT'。
  String findProxyFor(Uri? _) {
    if (!isConfigured) return 'DIRECT';
    return 'PROXY $_host:$_port';
  }
}
