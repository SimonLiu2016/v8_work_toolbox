import 'package:flutter/foundation.dart';

import '../../../services/settings_store.dart';

class RegistrarConfig {
  final int concurrency;
  final String targetDomain;
  final bool useProxy;
  final String captchaMode; // 'ai_vision' | 'capsolver'
  final String capSolverApiKey;
  final String smsApiKey;
  final String smsCountry;
  final String recoveryEmail;
  final String imapAuth;
  final String imapServer;
  final int imapPort;

  const RegistrarConfig({
    this.concurrency = 2,
    this.targetDomain = 'outlook.com',
    this.useProxy = true,
    this.captchaMode = 'ai_vision',
    this.capSolverApiKey = '',
    this.smsApiKey = '',
    this.smsCountry = '0',
    this.recoveryEmail = '',
    this.imapAuth = '',
    this.imapServer = 'imap.qq.com',
    this.imapPort = 993,
  });

  RegistrarConfig copyWith({
    int? concurrency,
    String? targetDomain,
    bool? useProxy,
    String? captchaMode,
    String? capSolverApiKey,
    String? smsApiKey,
    String? smsCountry,
    String? recoveryEmail,
    String? imapAuth,
    String? imapServer,
    int? imapPort,
  }) {
    return RegistrarConfig(
      concurrency: concurrency ?? this.concurrency,
      targetDomain: targetDomain ?? this.targetDomain,
      useProxy: useProxy ?? this.useProxy,
      captchaMode: captchaMode ?? this.captchaMode,
      capSolverApiKey: capSolverApiKey ?? this.capSolverApiKey,
      smsApiKey: smsApiKey ?? this.smsApiKey,
      smsCountry: smsCountry ?? this.smsCountry,
      recoveryEmail: recoveryEmail ?? this.recoveryEmail,
      imapAuth: imapAuth ?? this.imapAuth,
      imapServer: imapServer ?? this.imapServer,
      imapPort: imapPort ?? this.imapPort,
    );
  }

  Map<String, dynamic> toJson() => {
        'concurrency': concurrency,
        'targetDomain': targetDomain,
        'useProxy': useProxy,
        'captchaMode': captchaMode,
        'capSolverApiKey': capSolverApiKey,
        'smsApiKey': smsApiKey,
        'smsCountry': smsCountry,
        'recoveryEmail': recoveryEmail,
        'imapAuth': imapAuth,
        'imapServer': imapServer,
        'imapPort': imapPort,
      };

  factory RegistrarConfig.fromJson(Map<String, dynamic> json) {
    return RegistrarConfig(
      concurrency: (json['concurrency'] as int?) ?? 2,
      targetDomain: (json['targetDomain'] as String?) ?? 'outlook.com',
      useProxy: (json['useProxy'] as bool?) ?? true,
      captchaMode: (json['captchaMode'] as String?) ?? 'ai_vision',
      capSolverApiKey: (json['capSolverApiKey'] as String?) ?? '',
      smsApiKey: (json['smsApiKey'] as String?) ?? '',
      smsCountry: (json['smsCountry'] as String?) ?? '0',
      recoveryEmail: (json['recoveryEmail'] as String?) ?? '',
      imapAuth: (json['imapAuth'] as String?) ?? '',
      imapServer: (json['imapServer'] as String?) ?? 'imap.qq.com',
      imapPort: (json['imapPort'] as int?) ?? 993,
    );
  }
}

class RegistrarConfigStore extends ChangeNotifier {
  RegistrarConfigStore._();
  static final RegistrarConfigStore instance = RegistrarConfigStore._();

  static const String _toolId = 'auto-registrar';

  RegistrarConfig _config = const RegistrarConfig();
  bool _loaded = false;

  RegistrarConfig get config => _config;
  bool get isLoaded => _loaded;

  /// 加载已持久化的注册配置
  Future<void> load() async {
    try {
      final data = await SettingsStore.instance.readToolConfig(_toolId);
      if (data.isNotEmpty) {
        _config = RegistrarConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('[RegistrarConfigStore] 读取配置失败: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// 保存并持久化配置
  Future<void> save(RegistrarConfig newConfig) async {
    _config = newConfig;
    try {
      await SettingsStore.instance.writeToolConfig(_toolId, newConfig.toJson());
    } catch (e) {
      debugPrint('[RegistrarConfigStore] 保存配置失败: $e');
    }
    notifyListeners();
  }
}
