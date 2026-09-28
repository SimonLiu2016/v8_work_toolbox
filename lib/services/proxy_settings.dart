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
///
/// 工具级代理开关通过 [isToolEnabled] / [setToolEnabled] 读写，
/// 各工具（ai-assistant、doc-audio-reader 等）独立决定是否走代理通道。
class ProxySettings extends ChangeNotifier {
  ProxySettings._();
  static final ProxySettings instance = ProxySettings._();

  static const String _configId = 'proxy';

  String _host = '';
  int _port = 0;
  bool _enabled = false;
  Map<String, bool> _perToolEnabled = {};

  List<String> _bypassList = [];

  String get host => _host;
  int get port => _port;
  bool get enabled => _enabled;
  bool get isConfigured => _enabled && _host.isNotEmpty && _port > 0;
  List<String> get bypassList => List.unmodifiable(_bypassList);

  /// 查询指定工具的代理开关，不存在时默认 false（直连）。
  bool isToolEnabled(String toolId) => _perToolEnabled[toolId] ?? false;

  /// 从持久化存储加载。未配置时返回默认（直连）。
  Future<void> load() async {
    final json = await SettingsStore.instance.readToolConfig(_configId);
    _host = (json['host'] as String?)?.trim() ?? '';
    _port = (json['port'] as num?)?.toInt() ?? 0;
    _enabled = json['enabled'] as bool? ?? false;
    final perTool = json['perToolEnabled'];
    if (perTool is Map) {
      _perToolEnabled = perTool.map(
        (k, v) => MapEntry(k.toString(), v == true),
      );
    } else {
      _perToolEnabled = {};
    }
    final rawBypass = json['bypassList'];
    if (rawBypass is List) {
      _bypassList = rawBypass.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    } else {
      // 默认内置绕过列表：包含国内常用私有 AI 接入地址与国内镜像
      _bypassList = ['119.29.249.154'];
    }
    notifyListeners();
  }

  /// 仅在 [enabled] 为 true 时校验主机和端口有效性；关闭代理时允许保存或清空。
  Future<void> save({
    required String host,
    required int port,
    required bool enabled,
    List<String>? bypassList,
  }) async {
    if (enabled) {
      _validate(host, port);
    }
    _host = host.trim();
    _port = port;
    _enabled = enabled;
    if (bypassList != null) {
      _bypassList = bypassList.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    await _persist();
    notifyListeners();
  }

  /// 仅切换全局代理启用状态，保留既有 host 和 port 配置。
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      _validate(_host, _port);
    }
    _enabled = enabled;
    await _persist();
    notifyListeners();
  }

  /// 更新指定工具的代理开关并持久化。
  Future<void> setToolEnabled(String toolId, bool enabled) async {
    _perToolEnabled = Map.from(_perToolEnabled)..[toolId] = enabled;
    await _persist();
    notifyListeners();
  }

  /// 更新绕过白名单并持久化。
  Future<void> setBypassList(List<String> list) async {
    _bypassList = list.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await SettingsStore.instance.writeToolConfig(_configId, {
      'host': _host,
      'port': _port,
      'enabled': _enabled,
      'perToolEnabled': _perToolEnabled,
      'bypassList': _bypassList,
    });
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

  /// 判断目标 URL 是否属于直连绕过范围（本地回环、RFC 1918 私网、自定义白名单）
  bool shouldBypass(Uri? uri) {
    if (uri == null) return true;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return true;

    // 1. 本机回环
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }

    // 2. 检查自定义绕过白名单 (完全匹配、尾部域名匹配或前缀匹配)
    for (final pattern in _bypassList) {
      final p = pattern.trim().toLowerCase();
      if (p.isEmpty) continue;
      if (host == p) return true;
      if (p.startsWith('.') && host.endsWith(p)) return true;
      if (p.startsWith('*.')) {
        final suffix = p.substring(1);
        if (host.endsWith(suffix)) return true;
      }
    }

    // 3. RFC 1918 私网 IP 判断
    final parts = host.split('.');
    if (parts.length == 4) {
      final octets = parts.map((e) => int.tryParse(e)).toList();
      if (octets.every((o) => o != null && o >= 0 && o <= 255)) {
        final o1 = octets[0]!;
        final o2 = octets[1]!;
        // 10.0.0.0/8
        if (o1 == 10) return true;
        // 172.16.0.0/12
        if (o1 == 172 && o2 >= 16 && o2 <= 31) return true;
        // 192.168.0.0/16
        if (o1 == 192 && o2 == 168) return true;
      }
    }

    return false;
  }

  /// 供 MCP 子进程环境注入用。未配置时返回空 Map，不注入任何代理变量。
  Map<String, String> toEnvVars() {
    if (!isConfigured) return const {};
    final url = 'http://$_host:$_port';
    final defaultNoProxy = 'localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12';
    final noProxyStr = _bypassList.isEmpty
        ? defaultNoProxy
        : '$defaultNoProxy,${_bypassList.join(',')}';

    return {
      'HTTP_PROXY': url,
      'HTTPS_PROXY': url,
      'ALL_PROXY': url,
      'NO_PROXY': noProxyStr,
      'http_proxy': url,
      'https_proxy': url,
      'all_proxy': url,
      'no_proxy': noProxyStr,
    };
  }

  /// 仅供测试注入状态，绕过持久化。生产代码用 [load] / [save]。
  @visibleForTesting
  void setForTesting({
    String host = '',
    int port = 0,
    bool enabled = false,
    Map<String, bool>? perToolEnabled,
    List<String>? bypassList,
  }) {
    _host = host;
    _port = port;
    _enabled = enabled;
    _perToolEnabled = perToolEnabled ?? {};
    _bypassList = bypassList ?? [];
    notifyListeners();
  }

  /// PAC 风格的代理字符串，供 `HttpClient.findProxy` 使用。未配置或匹配绕过规则时返回 'DIRECT'。
  String findProxyFor(Uri? uri) {
    if (!isConfigured) return 'DIRECT';
    if (shouldBypass(uri)) return 'DIRECT';
    return 'PROXY $_host:$_port';
  }
}
