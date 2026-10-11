import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../../../services/mcp_service.dart';

/// BDMS URL 签名响应。
class DolaSignedResult {
  final String signedUrl;
  final String aBogus;
  final String msToken;
  final String? error;

  const DolaSignedResult({
    required this.signedUrl,
    this.aBogus = '',
    this.msToken = '',
    this.error,
  });

  bool get isSuccess => error == null || error!.isEmpty;

  factory DolaSignedResult.fromJson(Map<String, dynamic> json) {
    return DolaSignedResult(
      signedUrl: (json['signed_url'] as String?) ?? (json['url'] as String?) ?? '',
      aBogus: (json['a_bogus'] as String?) ?? '',
      msToken: (json['msToken'] as String?) ?? '',
      error: json['error'] as String?,
    );
  }
}

/// 负责托管长驻 Node.js 进程为 Dola API 计算合规的 BDMS 签名（a_bogus 等）。
class DolaSignerService {
  DolaSignerService._();
  static final DolaSignerService instance = DolaSignerService._();

  Process? _process;
  bool _isStarting = false;
  int _requestIdCounter = 0;
  final Map<String, Completer<DolaSignedResult>> _pendingRequests = {};
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  /// 检测系统中是否有 Node.js
  Future<bool> isNodeAvailable() async {
    try {
      final envPath = McpStdioSession.getDiscoveredPath();
      final res = await Process.run(
        'node',
        ['--version'],
        environment: envPath.isNotEmpty ? {'PATH': envPath} : null,
      );
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 获取签名脚本的物理文件路径
  String _resolveSignerScriptPath() {
    final execDir = p.dirname(Platform.resolvedExecutable);

    // 候选路径列表（按优先级尝试）
    final candidatePaths = [
      // 1. macOS 打包应用 Bundle Framework 资源目录 (例如 /Applications/V8WorkToolbox.app/Contents/Frameworks/App.framework/...)
      p.normalize(p.join(execDir, '..', 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets', 'dola', 'bdms_sign_url.js')),
      p.normalize(p.join(execDir, '..', 'Frameworks', 'App.framework', 'Versions', 'A', 'Resources', 'flutter_assets', 'assets', 'dola', 'bdms_sign_url.js')),
      // 2. 本地工程开发模式源码目录 assets/dola/
      p.join(Directory.current.path, 'assets', 'dola', 'bdms_sign_url.js'),
      // 3. 应用数据配置存储目录
      if (AppPaths.isInitialized)
        p.join(AppPaths.root.path, 'assets', 'dola', 'bdms_sign_url.js'),
      // 4. 工作目录相对路径
      p.join('assets', 'dola', 'bdms_sign_url.js'),
    ];

    for (final candidate in candidatePaths) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return candidatePaths.first;
  }

  /// 确保后台签名 Daemon 进程已启动
  Future<void> ensureStarted() async {
    if (_process != null) return;
    if (_isStarting) {
      while (_isStarting) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isStarting = true;
    try {
      final scriptPath = _resolveSignerScriptPath();
      if (!File(scriptPath).existsSync()) {
        throw StateError('Dola BDMS 签名脚本文件不存在: $scriptPath');
      }

      final envPath = McpStdioSession.getDiscoveredPath();
      final env = <String, String>{
        'DOLA_SIGNER_DAEMON': '1',
      };
      if (envPath.isNotEmpty) {
        env['PATH'] = envPath;
      }

      final proc = await Process.start(
        'node',
        [scriptPath, '--daemon'],
        environment: env,
      );

      _process = proc;

      // 监听标准输出（逐行 JSON-RPC 响应）
      _stdoutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStdoutLine, onError: (err) {
        debugPrint('[DolaSignerService] stdout error: $err');
      }, onDone: _handleProcessExit);

      // 监听错误输出
      _stderrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          debugPrint('[DolaSignerService stderr] $line');
        }
      });

      // 进程意外退出监听
      proc.exitCode.then((code) {
        debugPrint('[DolaSignerService] daemon exited with code: $code');
        _handleProcessExit();
      });
    } finally {
      _isStarting = false;
    }
  }

  void _handleStdoutLine(String line) {
    final text = line.trim();
    if (text.isEmpty) return;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      final rid = json['id']?.toString() ?? '';
      if (rid.isNotEmpty && _pendingRequests.containsKey(rid)) {
        final completer = _pendingRequests.remove(rid);
        completer?.complete(DolaSignedResult.fromJson(json));
        return;
      }
      // 如果没有 id，但有唯一正在排队的请求
      if (_pendingRequests.length == 1) {
        final firstKey = _pendingRequests.keys.first;
        final completer = _pendingRequests.remove(firstKey);
        completer?.complete(DolaSignedResult.fromJson(json));
      }
    } catch (e) {
      debugPrint('[DolaSignerService] Failed to parse daemon output: $text, err: $e');
    }
  }

  void _handleProcessExit() {
    _process = null;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    // 将所有等待中的请求标记为失败
    final pending = Map<String, Completer<DolaSignedResult>>.from(_pendingRequests);
    _pendingRequests.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Dola 签名子进程已退出'));
      }
    }
  }

  /// 为指定的 Dola URL 进行签名
  Future<DolaSignedResult> signUrl({
    required String url,
    String method = 'POST',
    Map<String, dynamic> headers = const {},
    String body = '{}',
    Map<String, String> cookies = const {},
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await ensureStarted();
    final proc = _process;
    if (proc == null) {
      throw StateError('未能成功拉起 Dola 签名子进程');
    }

    final id = 'req_${++_requestIdCounter}_${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<DolaSignedResult>();
    _pendingRequests[id] = completer;

    final payload = {
      'id': id,
      'url': url,
      'method': method,
      'headers': headers,
      'body': body,
      'cookies': cookies,
    };

    proc.stdin.writeln(jsonEncode(payload));

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Dola URL 签名超时 ($id)');
      },
    );
  }

  /// 关闭释放守护进程
  Future<void> dispose() async {
    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        proc.kill();
      } catch (_) {}
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
  }
}
