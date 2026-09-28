import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../services/app_paths.dart';
import 'clash_subscription_parser.dart';

/// mihomo 进程运行状态。
enum MihomoStatus {
  stopped,
  starting,
  running,
  crashed,
}

/// 管理捆绑的 mihomo 二进制进程生命周期。
///
/// mihomo 以全量节点 config 启动，监听 `127.0.0.1:7890`（HTTP 代理）
/// 和 `127.0.0.1:9090`（REST API，用于切换节点和测速）。
///
/// 严格限于本进程内使用，不修改 macOS 系统代理设置。
class MihomoProcessManager {
  MihomoProcessManager._();
  static final MihomoProcessManager instance = MihomoProcessManager._();

  static const int _proxyPort = 7890;
  static const int _apiPort = 9090;
  static const String _proxyGroup = 'PROXY';

  Process? _process;
  MihomoStatus _status = MihomoStatus.stopped;
  VoidCallback? _onCrashed;

  MihomoStatus get status => _status;
  bool get isRunning => _status == MihomoStatus.running;

  int get proxyPort => _proxyPort;
  int get apiPort => _apiPort;

  /// 注册意外崩溃回调。
  void setOnCrashed(VoidCallback callback) {
    _onCrashed = callback;
  }

  /// 启动 mihomo 进程，使用全量节点配置，选中 [selectedNodeName]。
  ///
  /// 若已在运行，先停止再重启。
  Future<void> start(List<ProxyNode> allNodes, String selectedNodeName) async {
    if (_process != null) {
      await stop();
    }

    _status = MihomoStatus.starting;

    // 检查端口是否被占用，尝试备选端口
    final port = await _findAvailablePort(_proxyPort, [_proxyPort, 17890, 27890]);

    // 生成 mihomo config
    final configFile = await _writeConfig(allNodes, selectedNodeName, proxyPort: port);

    // 获取 mihomo 二进制路径
    final mihomoPath = _getMihomoPath();
    if (!File(mihomoPath).existsSync()) {
      _status = MihomoStatus.stopped;
      throw StateError('mihomo 二进制不存在: $mihomoPath');
    }

    // 确保有执行权限
    await Process.run('chmod', ['+x', mihomoPath]);

    // 启动进程
    final configDir = AppPaths.configDir.path;
    _process = await Process.start(
      mihomoPath,
      ['-d', configDir, '-f', configFile.path],
      workingDirectory: configDir,
    );

    final stderrLines = <String>[];
    _process!.stderr.transform(utf8.decoder).listen((line) {
      stderrLines.add(line);
      debugPrint('[mihomo stderr] $line');
    });

    int? earlyExitCode;
    _process!.exitCode.then((code) {
      earlyExitCode = code;
      if (_status == MihomoStatus.running) {
        debugPrint('[MihomoProcessManager] 进程意外退出，退出码: $code');
        _status = MihomoStatus.crashed;
        _process = null;
        _onCrashed?.call();
      }
    });

    // 等待 mihomo 启动（最多 3 秒）
    for (int i = 0; i < 30; i++) {
      if (earlyExitCode != null) {
        final errSummary = stderrLines.join('\n').trim();
        _status = MihomoStatus.stopped;
        _process = null;
        throw StateError(
          'mihomo 进程启动异常 (code: $earlyExitCode)${errSummary.isNotEmpty ? ": $errSummary" : ""}',
        );
      }
      await Future.delayed(const Duration(milliseconds: 100));
      if (await _isApiReady()) {
        _status = MihomoStatus.running;
        debugPrint('[MihomoProcessManager] mihomo 已启动，代理端口: $port');
        return;
      }
    }

    // 启动超时
    await stop();
    throw TimeoutException('mihomo 启动超时（3秒内未响应 API）');
  }

  /// 通过 REST API 切换当前代理节点（无需重启进程）。
  Future<void> switchNode(String nodeName) async {
    if (!isRunning) throw StateError('mihomo 未运行');

    final url = Uri.parse('http://127.0.0.1:$_apiPort/proxies/$_proxyGroup');
    final resp = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': nodeName}),
    ).timeout(const Duration(seconds: 5));

    if (resp.statusCode != 204) {
      throw StateError('切换节点失败: HTTP ${resp.statusCode}，节点: $nodeName');
    }
    debugPrint('[MihomoProcessManager] 已切换到节点: $nodeName');
  }

  /// 测试指定节点的延迟（毫秒），超时或失败返回 null。
  Future<int?> testDelay(String nodeName) async {
    if (!isRunning) return null;

    try {
      final encodedName = Uri.encodeComponent(nodeName);
      final url = Uri.parse(
        'http://127.0.0.1:$_apiPort/proxies/$encodedName/delay'
        '?url=http%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 7));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return (body['delay'] as num?)?.toInt();
      }
    } catch (_) {}
    return null;
  }

  /// 停止 mihomo 进程。
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    _status = MihomoStatus.stopped;

    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      try {
        await proc.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        proc.kill(ProcessSignal.sigkill);
      }
    }
    debugPrint('[MihomoProcessManager] mihomo 已停止');
  }

  /// 生成并写入 mihomo config.yaml，返回配置文件。
  Future<File> _writeConfig(
    List<ProxyNode> nodes,
    String selectedNodeName, {
    required int proxyPort,
  }) async {
    final configDir = AppPaths.configDir;
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }

    final proxiesList = nodes.map((n) => _nodeToYamlMap(n.rawConfig)).toList();
    final nodeNames = nodes.map((n) => n.name).toList();

    // 确保选中节点名在列表中
    final selected = nodeNames.contains(selectedNodeName)
        ? selectedNodeName
        : nodeNames.first;

    final config = {
      'port': proxyPort,
      'socks-port': proxyPort + 1,
      'allow-lan': false,
      'log-level': 'silent',
      'external-controller': '127.0.0.1:$_apiPort',
      'proxies': proxiesList,
      'proxy-groups': [
        {
          'name': _proxyGroup,
          'type': 'select',
          'proxies': nodeNames,
        }
      ],
      'rules': ['MATCH,$_proxyGroup'],
    };

    final yamlStr = _mapToYaml(config);
    final configFile = File(p.join(configDir.path, 'mihomo_config.yaml'));
    await configFile.writeAsString(yamlStr, flush: true);

    // 持久化选中节点到 config（mihomo 启动后再用 API 切换到正确节点）
    // mihomo 的 select group 需要在启动后用 API PUT 来设置初始选择
    return configFile;
  }

  /// 将节点原始配置 Map 转为 YAML 友好的 Map（去除 null 值）。
  Map<String, dynamic> _nodeToYamlMap(Map<String, dynamic> raw) {
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.value != null) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// 简单 Map→YAML 序列化（用于 config.yaml 生成）。
  String _mapToYaml(Map<String, dynamic> map, {int indent = 0}) {
    final sb = StringBuffer();
    final pad = '  ' * indent;
    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        sb.writeln('$pad$key:');
        sb.write(_mapToYaml(value, indent: indent + 1));
      } else if (value is List) {
        sb.writeln('$pad$key:');
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            sb.writeln('$pad  - ${_inlineMap(item)}');
          } else {
            sb.writeln('$pad  - ${_yamlValue(item)}');
          }
        }
      } else {
        sb.writeln('$pad$key: ${_yamlValue(value)}');
      }
    }
    return sb.toString();
  }

  String _inlineMap(Map<String, dynamic> map) {
    final parts = map.entries.map((e) => '${e.key}: ${_yamlValue(e.value)}').join(', ');
    return '{$parts}';
  }

  String _yamlValue(dynamic v) {
    if (v == null) return 'null';
    if (v is bool) return v.toString();
    if (v is num) return v.toString();
    if (v is Map) {
      return _inlineMap(Map<String, dynamic>.from(v));
    }
    if (v is String) {
      // 需要加引号的情况
      if (v.contains(':') || v.contains('#') || v.isEmpty || v.contains('\n')) {
        return '"${v.replaceAll('"', '\\"')}"';
      }
      return v;
    }
    if (v is List) {
      return '[${v.map(_yamlValue).join(', ')}]';
    }
    return '"$v"';
  }

  /// 检查 mihomo REST API 是否就绪。
  Future<bool> _isApiReady() async {
    try {
      final resp = await http
          .get(Uri.parse('http://127.0.0.1:$_apiPort/'))
          .timeout(const Duration(milliseconds: 300));
      return resp.statusCode == 200 || resp.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  /// 查找可用端口，从候选列表中选第一个未被占用的。
  Future<int> _findAvailablePort(int preferred, List<int> candidates) async {
    for (final port in candidates) {
      try {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } catch (_) {
        continue;
      }
    }
    return preferred; // 实在没有空闲就用首选端口，让 mihomo 自己报错
  }

  /// 获取捆绑的 mihomo 二进制路径。
  String _getMihomoPath() {
    final execPath = Platform.resolvedExecutable;
    // 1. macOS app bundle: .../MacOS/V8WorkToolbox → .../Resources/mihomo
    final bundlePath = p.normalize(p.join(p.dirname(execPath), '..', 'Resources', 'mihomo'));
    if (File(bundlePath).existsSync()) {
      return bundlePath;
    }

    // 2. 本地开发工程源码路径 (flutter run / test)
    final devPath = p.normalize(p.join(Directory.current.path, 'macos', 'Runner', 'Resources', 'mihomo'));
    if (File(devPath).existsSync()) {
      return devPath;
    }

    // 3. 本地已有外部内核兜底
    const clashVergePath = '/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo';
    if (File(clashVergePath).existsSync()) {
      return clashVergePath;
    }

    return bundlePath;
  }
}
