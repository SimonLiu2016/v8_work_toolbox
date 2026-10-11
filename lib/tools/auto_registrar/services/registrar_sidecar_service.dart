import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/ai_config_store.dart';
import '../../../services/app_paths.dart';
import '../../../services/keychain_service.dart';
import '../models/registered_account.dart';
import 'registered_account_store.dart';

class SystemVisionAiInfo {
  final String providerName;
  final String model;
  final String baseUrl;
  final String apiKey;
  final bool isAvailable;
  final String? errorMessage;

  const SystemVisionAiInfo({
    this.providerName = '',
    this.model = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.isAvailable = false,
    this.errorMessage,
  });
}

class SidecarLog {
  final String timestamp;
  final String level; // 'info' | 'warn' | 'error' | 'success'
  final int workerId;
  final String message;

  SidecarLog({
    required this.timestamp,
    required this.level,
    required this.workerId,
    required this.message,
  });

  factory SidecarLog.fromJson(Map<String, dynamic> json) {
    return SidecarLog(
      timestamp: (json['timestamp'] as String?) ?? DateTime.now().toIso8601String(),
      level: (json['level'] as String?) ?? 'info',
      workerId: (json['workerId'] as int?) ?? 0,
      message: (json['message'] as String?) ?? '',
    );
  }
}

class SidecarStats {
  final int total;
  final int running;
  final int success;
  final int failed;
  final int captchaSolved;
  final int smsUsed;

  const SidecarStats({
    this.total = 0,
    this.running = 0,
    this.success = 0,
    this.failed = 0,
    this.captchaSolved = 0,
    this.smsUsed = 0,
  });

  factory SidecarStats.fromJson(Map<String, dynamic> json) {
    return SidecarStats(
      total: (json['total'] as int?) ?? 0,
      running: (json['running'] as int?) ?? 0,
      success: (json['success'] as int?) ?? 0,
      failed: (json['failed'] as int?) ?? 0,
      captchaSolved: (json['captchaSolved'] as int?) ?? 0,
      smsUsed: (json['smsUsed'] as int?) ?? 0,
    );
  }
}

class RegistrarSidecarService extends ChangeNotifier {
  RegistrarSidecarService._();
  static final RegistrarSidecarService instance = RegistrarSidecarService._();

  Process? _process;
  bool _isRunning = false;
  SidecarStats _stats = const SidecarStats();
  final List<SidecarLog> _logs = [];

  bool get isRunning => _isRunning;
  SidecarStats get stats => _stats;
  List<SidecarLog> get logs => List.unmodifiable(_logs);

  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  /// 找到 Sidecar CLI 路径
  String _getSidecarEntryPath() {
    // 首先检查开发源码目录
    final devPath = p.join(Directory.current.path, 'packages', 'registrar_sidecar', 'src', 'cli.ts');
    if (File(devPath).existsSync()) {
      return devPath;
    }
    // 检查打包或独立部署路径
    final prodPath = p.join(AppPaths.root.path, 'sidecar', 'cli.ts');
    return prodPath;
  }

  /// 自动解析系统配置中的 AI 视觉模型信息
  Future<SystemVisionAiInfo> resolveSystemVisionAi() async {
    final store = AiConfigStore.instance;
    if (!store.isInitialized) {
      await store.init();
    }

    // 1. 优先从 multimodal 槽位候选读取
    final candidates = store.slotBindings['multimodal'] ?? <SlotCandidate>[];
    if (candidates.isNotEmpty) {
      final first = candidates.first;
      final provider = store.providers.cast<AiProviderConfig?>().firstWhere(
        (p) => p?.id == first.providerId && (p?.enabled ?? false),
        orElse: () => null,
      );
      if (provider != null) {
        final key = await KeychainService.instance.readSecret(provider.keychainKeyId) ?? '';
        return SystemVisionAiInfo(
          providerName: provider.name,
          model: first.model,
          baseUrl: provider.baseUrl,
          apiKey: key,
          isAvailable: key.isNotEmpty,
          errorMessage: key.isEmpty ? '供应商 API Key 未在钥匙串中配置' : null,
        );
      }
    }

    // 2. 检查是否有启用且包含 multimodalModels 的供应商
    for (final p in store.providers) {
      if (!p.enabled) continue;
      if (p.multimodalModels.isNotEmpty) {
        final key = await KeychainService.instance.readSecret(p.keychainKeyId) ?? '';
        return SystemVisionAiInfo(
          providerName: p.name,
          model: p.multimodalModels.first,
          baseUrl: p.baseUrl,
          apiKey: key,
          isAvailable: key.isNotEmpty,
          errorMessage: key.isEmpty ? '供应商 API Key 未在钥匙串中配置' : null,
        );
      }
    }

    // 3. 回退到第一个启用的通用供应商
    for (final p in store.providers) {
      if (!p.enabled) continue;
      final key = await KeychainService.instance.readSecret(p.keychainKeyId) ?? '';
      final model = p.textModels.isNotEmpty ? p.textModels.first : 'claude-3-5-sonnet-20241022';
      return SystemVisionAiInfo(
        providerName: p.name,
        model: model,
        baseUrl: p.baseUrl,
        apiKey: key,
        isAvailable: key.isNotEmpty,
        errorMessage: key.isEmpty ? '供应商 API Key 未在钥匙串中配置' : null,
      );
    }

    return const SystemVisionAiInfo(
      isAvailable: false,
      errorMessage: '系统尚未配置任何可用的 AI 供应商',
    );
  }

  /// 启动注册任务
  Future<void> startTasks({
    required int concurrency,
    required String targetDomain, // 'outlook.com' | 'hotmail.com'
    required bool useProxy,
    String? proxyServer, // e.g. "127.0.0.1:6160"
    required String captchaMode, // 'capsolver' | 'ai_vision'
    String capSolverApiKey = '',
    String aiVisionApiKey = '',
    String aiVisionEndpoint = '',
    String aiVisionModel = '',
    String smsApiKey = '',
    String smsCountry = '0',
    String recoveryEmail = '',
    String imapServer = 'imap.qq.com',
    int imapPort = 993,
    String imapUser = '',
    String imapAuth = '',
    int maxRetries = 3,
  }) async {
    if (_isRunning) return;

    final entryPath = _getSidecarEntryPath();
    final sidecarDir = p.dirname(p.dirname(entryPath));

    _logs.clear();
    _stats = const SidecarStats();
    notifyListeners();

    try {
      // 启动 npx tsx cli.ts
      _process = await Process.start(
        'npx',
        ['tsx', entryPath],
        workingDirectory: sidecarDir,
        mode: ProcessStartMode.normal,
      );

      _isRunning = true;
      notifyListeners();

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleStdoutLine, onError: (err) {
        _appendLog(SidecarLog(
          timestamp: DateTime.now().toIso8601String(),
          level: 'error',
          workerId: 0,
          message: 'Sidecar 读取 stdout 错误: $err',
        ));
      });

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          _appendLog(SidecarLog(
            timestamp: DateTime.now().toIso8601String(),
            level: 'warn',
            workerId: 0,
            message: '[stderr] $line',
          ));
        }
      });

      _process!.exitCode.then((code) {
        _isRunning = false;
        _appendLog(SidecarLog(
          timestamp: DateTime.now().toIso8601String(),
          level: 'info',
          workerId: 0,
          message: 'Sidecar 进程已退出 (code: $code)',
        ));
        _process = null;
        notifyListeners();
      });

      String resolvedApiKey = aiVisionApiKey;
      String resolvedEndpoint = aiVisionEndpoint;
      String resolvedModel = aiVisionModel;

      if (captchaMode == 'ai_vision' && resolvedApiKey.isEmpty) {
        final visionInfo = await resolveSystemVisionAi();
        if (visionInfo.isAvailable) {
          resolvedApiKey = visionInfo.apiKey;
          resolvedEndpoint = visionInfo.baseUrl;
          resolvedModel = visionInfo.model;
          _appendLog(SidecarLog(
            timestamp: DateTime.now().toIso8601String(),
            level: 'info',
            workerId: 0,
            message: '自动复用系统 AI 视觉模型: ${visionInfo.providerName} / ${visionInfo.model}',
          ));
        } else {
          _appendLog(SidecarLog(
            timestamp: DateTime.now().toIso8601String(),
            level: 'warn',
            workerId: 0,
            message: '未能在系统中找到可用的 AI 视觉配置: ${visionInfo.errorMessage}',
          ));
        }
      }

      // 构造启动配置并推入
      final configPayload = {
        'concurrency': concurrency,
        'targetDomain': targetDomain,
        'captchaMode': captchaMode,
        'capSolverApiKey': capSolverApiKey,
        'aiVisionApiKey': resolvedApiKey,
        'aiVisionEndpoint': resolvedEndpoint,
        'aiVisionModel': resolvedModel,
        'smsApiKey': smsApiKey,
        'smsCountry': smsCountry,
        'maxRetries': maxRetries,
        'recoveryEmail': recoveryEmail,
        'imapServer': imapServer,
        'imapPort': imapPort,
        'imapUser': imapUser,
        'imapAuth': imapAuth,
        'proxyConfig': {
          'mode': useProxy ? (proxyServer != null ? 'static' : 'none') : 'none',
          'staticList': useProxy && proxyServer != null ? [proxyServer] : [],
        },
      };

      _sendCommand('start', configPayload);
    } catch (e) {
      _isRunning = false;
      _appendLog(SidecarLog(
        timestamp: DateTime.now().toIso8601String(),
        level: 'error',
        workerId: 0,
        message: '启动 Sidecar 异常: $e',
      ));
      notifyListeners();
    }
  }

  void _sendCommand(String action, dynamic payload) {
    if (_process == null) return;
    final cmd = jsonEncode({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'action': action,
      'payload': payload,
    });
    _process!.stdin.writeln(cmd);
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    try {
      final msg = jsonDecode(trimmed) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final data = msg['data'];

      switch (type) {
        case 'log':
          if (data is Map<String, dynamic>) {
            _appendLog(SidecarLog.fromJson(data));
          }
          break;

        case 'stats':
          if (data is Map<String, dynamic>) {
            _stats = SidecarStats.fromJson(data);
            notifyListeners();
          }
          break;

        case 'account':
          if (data is Map<String, dynamic>) {
            final acc = RegisteredAccount.fromJson(data);
            RegisteredAccountStore.instance.saveAccount(acc);
          }
          break;

        case 'stopped':
          _isRunning = false;
          notifyListeners();
          break;

        default:
          debugPrint('[Sidecar Unhandled Event] $trimmed');
      }
    } catch (e) {
      // 普通文本输出
      _appendLog(SidecarLog(
        timestamp: DateTime.now().toIso8601String(),
        level: 'info',
        workerId: 0,
        message: trimmed,
      ));
    }
  }

  void _appendLog(SidecarLog log) {
    _logs.add(log);
    if (_logs.length > 500) {
      _logs.removeRange(0, _logs.length - 500);
    }
    notifyListeners();
  }

  /// 停止任务
  Future<void> stopTasks() async {
    if (!_isRunning || _process == null) return;
    _sendCommand('stop', null);
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    await Future.delayed(const Duration(milliseconds: 500));
    _process?.kill(ProcessSignal.sigterm);
    _isRunning = false;
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}
