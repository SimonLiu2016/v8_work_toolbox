import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../services/proxy_settings.dart';
import '../../../services/settings_store.dart';
import 'clash_subscription_parser.dart';
import 'mihomo_process_manager.dart';

/// 应用内嵌代理管理器的顶层服务。
///
/// 职责：订阅管理、节点列表维护、mihomo 进程生命周期协调、全局启用开关。
/// 最终将代理地址写入 [ProxySettings]，现有 AppHttpClient 和 MCP 注入路径无需改动。
class NetworkProxyService extends ChangeNotifier {
  NetworkProxyService._();
  static final NetworkProxyService instance = NetworkProxyService._();

  static const String _configId = 'network-proxy';

  String _subscriptionUrl = '';
  DateTime? _lastRefreshTime;
  String? _trafficInfo;
  List<ProxyNode> _nodes = [];
  String? _selectedNodeName;
  bool _isRunning = false;
  bool _isRefreshing = false;
  bool _isTestingSpeed = false;
  String? _lastError;
  final Map<String, int?> _delayResults = {};

  String get subscriptionUrl => _subscriptionUrl;
  DateTime? get lastRefreshTime => _lastRefreshTime;
  String? get trafficInfo => _trafficInfo;
  List<ProxyNode> get nodes => List.unmodifiable(_nodes);
  String? get selectedNodeName => _selectedNodeName;
  bool get isRunning => _isRunning;
  bool get isRefreshing => _isRefreshing;
  bool get isTestingSpeed => _isTestingSpeed;
  String? get lastError => _lastError;
  int? delayOf(String nodeName) => _delayResults[nodeName];

  /// 初始化：从持久化存储加载状态，若有选中节点则自动启动 mihomo。
  Future<void> load() async {
    MihomoProcessManager.instance.setOnCrashed(_onMihomocrashed);

    final json = await SettingsStore.instance.readToolConfig(_configId);
    _subscriptionUrl = json['subscriptionUrl'] as String? ?? '';
    _lastRefreshTime = json['lastRefreshTime'] != null
        ? DateTime.tryParse(json['lastRefreshTime'] as String)
        : null;
    _trafficInfo = json['trafficInfo'] as String?;
    _selectedNodeName = json['selectedNodeName'] as String?;

    // 恢复节点列表
    final nodesJson = json['nodes'];
    if (nodesJson is List) {
      _nodes = nodesJson
          .whereType<Map>()
          .map((m) => ProxyNode.fromJson(m.cast<String, dynamic>()))
          .toList();
    }

    // 若有选中节点且列表非空，自动启动 mihomo
    if (_selectedNodeName != null && _nodes.isNotEmpty) {
      await _startMihomo(silent: true);
    }

    notifyListeners();
  }

  /// 保存订阅地址（校验非空）。
  Future<void> saveSubscriptionUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('订阅地址不能为空');
    }
    _subscriptionUrl = trimmed;
    await _persist();
    notifyListeners();
  }

  /// 下载并解析订阅，更新节点列表（失败时保留旧列表）。
  Future<void> refreshSubscription() async {
    if (_subscriptionUrl.isEmpty) {
      throw StateError('请先配置订阅地址');
    }
    _isRefreshing = true;
    _lastError = null;
    notifyListeners();

    try {
      // 订阅下载走直连（代理尚未建立时也能工作）
      // 机场订阅服务端通常依赖 User-Agent 鉴权和防爬，缺失或默认 Dart UA 会被拦截 403
      final client = http.Client();
      try {
        final resp = await client
            .get(
              Uri.parse(_subscriptionUrl),
              headers: {
                'User-Agent': 'clash-verge/v1.7.7',
                'Accept': '*/*',
              },
            )
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw StateError('HTTP ${resp.statusCode}：服务器拒绝请求');
        }

        // 解析机场返回的用户流量信息（若提供）
        final userInfo = resp.headers['subscription-userinfo'];
        if (userInfo != null && userInfo.isNotEmpty) {
          _trafficInfo = _parseSubscriptionUserInfo(userInfo);
        }

        final newNodes = ClashSubscriptionParser.parse(resp.body);
        _nodes = newNodes;
        _lastRefreshTime = DateTime.now();

        // 若当前选中节点不在新列表中，清除选中
        if (_selectedNodeName != null &&
            !_nodes.any((n) => n.name == _selectedNodeName)) {
          _selectedNodeName = null;
        }

        await _persist();
        notifyListeners();
      } finally {
        client.close();
      }
    } catch (e) {
      _lastError = '刷新订阅失败：$e';
      notifyListeners();
      rethrow;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// 选中节点并启动/切换 mihomo。
  Future<void> selectNode(ProxyNode node) async {
    _lastError = null;
    _selectedNodeName = node.name;
    notifyListeners();

    try {
      if (MihomoProcessManager.instance.isRunning) {
        await MihomoProcessManager.instance.switchNode(node.name);
      } else {
        await _startMihomo();
      }
      // 更新 ProxySettings，使 AppHttpClient 走 mihomo 代理
      await ProxySettings.instance.save(
        host: '127.0.0.1',
        port: MihomoProcessManager.instance.proxyPort,
        enabled: true,
      );
      _isRunning = true;
      await _persist();
    } catch (e) {
      _lastError = '启动代理失败：$e';
      _isRunning = false;
    }
    notifyListeners();
  }

  /// 并发测试所有节点延迟，逐步更新结果。
  Future<void> testAllDelays() async {
    _isTestingSpeed = true;
    _lastError = null;
    notifyListeners();

    try {
      if (!await _ensureMihomoRunning()) {
        return;
      }
      final futures = _nodes.map((node) async {
        final delay = await MihomoProcessManager.instance.testDelay(node.name);
        _delayResults[node.name] = delay;
        notifyListeners();
      });
      await Future.wait(futures);
    } catch (e) {
      _lastError = '测速失败: $e';
    } finally {
      _isTestingSpeed = false;
      notifyListeners();
    }
  }

  /// 测试单个节点延迟。
  Future<void> testNodeDelay(String nodeName) async {
    try {
      if (!await _ensureMihomoRunning()) return;
      final delay = await MihomoProcessManager.instance.testDelay(nodeName);
      _delayResults[nodeName] = delay;
      notifyListeners();
    } catch (e) {
      _lastError = '单节点测速失败: $e';
      notifyListeners();
    }
  }

  /// 确保内嵌内核已启动（用于测速或代理通道）。
  /// 若用户尚未选定生效节点，则仅启动内核服务，不激活全局代理开关。
  Future<bool> _ensureMihomoRunning() async {
    if (MihomoProcessManager.instance.isRunning) return true;
    if (_nodes.isEmpty) {
      _lastError = '请先配置并更新订阅以获取代理节点';
      notifyListeners();
      return false;
    }
    await _startMihomo(silent: false);
    return MihomoProcessManager.instance.isRunning;
  }

  /// 全局代理启用/禁用（mihomo 继续运行，仅控制 ProxySettings.enabled）。
  Future<void> setGlobalEnabled(bool enabled) async {
    if (enabled) {
      if (_selectedNodeName == null) {
        if (_nodes.isNotEmpty) {
          // 若尚未选定节点，默认选中首个可用节点并生效
          await selectNode(_nodes.first);
          return;
        } else {
          _lastError = '请先配置订阅并更新获取代理节点';
          notifyListeners();
          return;
        }
      }
    }
    final port = MihomoProcessManager.instance.proxyPort;
    await ProxySettings.instance.save(
      host: '127.0.0.1',
      port: port > 0 ? port : 7890,
      enabled: enabled,
    );
    notifyListeners();
  }

  /// 停止 mihomo 进程（应用退出前调用）。
  Future<void> shutdown() async {
    await MihomoProcessManager.instance.stop();
    _isRunning = false;
  }

  // ---------------------------------------------------------------------------
  // 内部辅助
  // ---------------------------------------------------------------------------

  Future<void> _startMihomo({bool silent = false}) async {
    if (_nodes.isEmpty) return;
    try {
      final targetNodeName = _selectedNodeName ?? _nodes.first.name;
      await MihomoProcessManager.instance.start(_nodes, targetNodeName);
      _isRunning = true;
    } catch (e) {
      _isRunning = false;
      if (!silent) {
        _lastError = '启动代理内核失败：$e';
      } else {
        debugPrint('[NetworkProxyService] 自动启动内核失败（忽略）：$e');
      }
    }
  }

  void _onMihomocrashed() {
    _isRunning = false;
    _lastError = '代理进程意外退出';
    notifyListeners();
  }

  static String? _parseSubscriptionUserInfo(String raw) {
    try {
      final parts = raw.split(';').map((s) => s.trim());
      int upload = 0;
      int download = 0;
      int total = 0;
      for (final p in parts) {
        final kv = p.split('=');
        if (kv.length == 2) {
          final k = kv[0].trim();
          final v = int.tryParse(kv[1].trim()) ?? 0;
          if (k == 'upload') upload = v;
          if (k == 'download') download = v;
          if (k == 'total') total = v;
        }
      }
      if (total > 0) {
        final usedGb = (upload + download) / (1024 * 1024 * 1024);
        final totalGb = total / (1024 * 1024 * 1024);
        return '已用 ${usedGb.toStringAsFixed(1)} GB / ${totalGb.toStringAsFixed(0)} GB';
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persist() async {
    await SettingsStore.instance.writeToolConfig(_configId, {
      'subscriptionUrl': _subscriptionUrl,
      'lastRefreshTime': _lastRefreshTime?.toIso8601String(),
      'trafficInfo': _trafficInfo,
      'selectedNodeName': _selectedNodeName,
      'nodes': _nodes.map((n) => n.toJson()).toList(),
    });
  }
}
