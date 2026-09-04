import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'keychain_service.dart';

/// 协议类型
enum AiProtocolType {
  openai('OpenAI 兼容协议'),
  anthropic('Anthropic 协议'),
  gemini('Google Gemini 协议');

  final String label;
  const AiProtocolType(this.label);

  static AiProtocolType fromString(String? val) {
    return AiProtocolType.values.firstWhere(
      (e) => e.name == val,
      orElse: () => AiProtocolType.openai,
    );
  }
}

/// 供应商配置
class AiProviderConfig {
  final String id;
  final String name;
  final AiProtocolType protocol;
  final String baseUrl;
  final String keychainKeyId;
  final bool enabled;
  final List<String> textModels;
  final List<String> multimodalModels;
  final List<String> ttsModels;
  final List<String> sttModels;

  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.keychainKeyId,
    this.enabled = true,
    this.textModels = const [],
    this.multimodalModels = const [],
    this.ttsModels = const [],
    this.sttModels = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'keychainKeyId': keychainKeyId,
    'enabled': enabled,
    'models': {
      'text': textModels,
      'multimodal': multimodalModels,
      'tts': ttsModels,
      'stt': sttModels,
    },
  };

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    final models = json['models'] as Map<String, dynamic>? ?? {};
    return AiProviderConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名供应商',
      protocol: AiProtocolType.fromString(json['protocol'] as String?),
      baseUrl: json['baseUrl'] as String? ?? '',
      keychainKeyId: json['keychainKeyId'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      textModels: List<String>.from(models['text'] ?? []),
      multimodalModels: List<String>.from(models['multimodal'] ?? []),
      ttsModels: List<String>.from(models['tts'] ?? []),
      sttModels: List<String>.from(models['stt'] ?? []),
    );
  }

  AiProviderConfig copyWith({
    String? name,
    AiProtocolType? protocol,
    String? baseUrl,
    bool? enabled,
    List<String>? textModels,
    List<String>? multimodalModels,
    List<String>? ttsModels,
    List<String>? sttModels,
  }) {
    return AiProviderConfig(
      id: id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      baseUrl: baseUrl ?? this.baseUrl,
      keychainKeyId: keychainKeyId,
      enabled: enabled ?? this.enabled,
      textModels: textModels ?? this.textModels,
      multimodalModels: multimodalModels ?? this.multimodalModels,
      ttsModels: ttsModels ?? this.ttsModels,
      sttModels: sttModels ?? this.sttModels,
    );
  }
}

/// 外部第三方 MCP 客户端配置
class McpClientConfig {
  final String id;
  final String name;
  final String transport; // 'stdio' or 'sse'
  final String endpointOrCommand;
  final List<String> args;
  final Map<String, String> env;
  final Map<String, String> headers;
  final bool enabled;

  const McpClientConfig({
    required this.id,
    required this.name,
    required this.transport,
    required this.endpointOrCommand,
    this.args = const [],
    this.env = const {},
    this.headers = const {},
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'transport': transport,
    'endpointOrCommand': endpointOrCommand,
    'args': args,
    'env': env,
    'headers': headers,
    'enabled': enabled,
  };

  factory McpClientConfig.fromJson(Map<String, dynamic> json) {
    return McpClientConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'MCP 服务',
      transport: json['transport'] as String? ?? 'stdio',
      endpointOrCommand: json['endpointOrCommand'] as String? ?? '',
      args: List<String>.from(json['args'] ?? []),
      env: Map<String, String>.from(json['env'] ?? {}),
      headers: Map<String, String>.from(json['headers'] ?? {}),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// AI 配置中枢存储
class AiConfigStore {
  AiConfigStore._();
  static final AiConfigStore instance = AiConfigStore._();

  File? _configFile;
  List<AiProviderConfig> _providers = [];
  Map<String, Map<String, String>> _slotBindings = {}; // slotName -> {'providerId': ..., 'model': ...}
  List<McpClientConfig> _mcpClients = [];

  List<AiProviderConfig> get providers => List.unmodifiable(_providers);
  Map<String, Map<String, String>> get slotBindings => Map.unmodifiable(_slotBindings);
  List<McpClientConfig> get mcpClients => List.unmodifiable(_mcpClients);

  Future<void> init({Directory? customRootDir}) async {
    try {
      Directory dir;
      if (customRootDir != null) {
        dir = customRootDir;
      } else {
        final home = Platform.environment['HOME'];
        if (Platform.isMacOS && home != null && home.isNotEmpty) {
          dir = Directory(p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'));
        } else {
          final appSupport = await getApplicationSupportDirectory();
          dir = Directory(p.join(appSupport.path, 'V8WorkToolbox'));
        }
      }

      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      _configFile = File(p.join(dir.path, 'ai_config.json'));
      await _load();
    } catch (e) {
      debugPrint('初始化 AI 配置失败: $e');
    }
  }

  Future<void> _load() async {
    if (_configFile == null || !await _configFile!.exists()) {
      _initDefaults();
      await _save();
      return;
    }

    try {
      final text = await _configFile!.readAsString();
      if (text.trim().isEmpty) {
        _initDefaults();
        return;
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      final providerList = (json['providers'] as List<dynamic>?) ?? [];
      _providers = providerList.map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>)).toList();

      final slots = (json['defaultSlots'] as Map<String, dynamic>?) ?? {};
      _slotBindings = slots.map((key, value) {
        return MapEntry(key, Map<String, String>.from(value as Map? ?? {}));
      });

      final mcps = (json['mcpServers'] as List<dynamic>?) ?? [];
      _mcpClients = mcps.map((e) => McpClientConfig.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('读取 ai_config.json 异常，加载默认配置: $e');
      _initDefaults();
    }
  }

  void _initDefaults() {
    _providers = [];
    _slotBindings = {
      'text': {'providerId': '', 'model': ''},
      'multimodal': {'providerId': '', 'model': ''},
      'tts': {'providerId': '', 'model': ''},
      'stt': {'providerId': '', 'model': ''},
    };
    _mcpClients = [];
  }

  Future<void> _save() async {
    if (_configFile == null) return;
    try {
      final map = {
        'providers': _providers.map((p) => p.toJson()).toList(),
        'defaultSlots': _slotBindings,
        'mcpServers': _mcpClients.map((m) => m.toJson()).toList(),
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
      final tmp = File('${_configFile!.path}.tmp');
      await tmp.writeAsString(jsonStr, flush: true);
      if (await _configFile!.exists()) {
        await _configFile!.delete();
      }
      await tmp.rename(_configFile!.path);
    } catch (e) {
      debugPrint('保存 ai_config.json 失败: $e');
    }
  }

  // 增删改查
  Future<void> saveProvider(AiProviderConfig provider, {String? apiKey}) async {
    final idx = _providers.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) {
      _providers[idx] = provider;
    } else {
      _providers.add(provider);
    }

    if (apiKey != null && apiKey.isNotEmpty) {
      await KeychainService.instance.writeSecret(provider.keychainKeyId, apiKey);
    }
    await _save();
  }

  Future<void> deleteProvider(String providerId) async {
    final p = _providers.firstWhere((e) => e.id == providerId, orElse: () => const AiProviderConfig(id: '', name: '', protocol: AiProtocolType.openai, baseUrl: '', keychainKeyId: ''));
    if (p.keychainKeyId.isNotEmpty) {
      await KeychainService.instance.deleteSecret(p.keychainKeyId);
    }
    _providers.removeWhere((e) => e.id == providerId);

    // 清理槽位引用
    _slotBindings.forEach((slot, binding) {
      if (binding['providerId'] == providerId) {
        binding['providerId'] = '';
        binding['model'] = '';
      }
    });

    await _save();
  }

  Future<void> setSlotBinding(String slotName, String providerId, String modelName) async {
    _slotBindings[slotName] = {
      'providerId': providerId,
      'model': modelName,
    };
    await _save();
  }

  Future<void> saveMcpClient(McpClientConfig client) async {
    final idx = _mcpClients.indexWhere((m) => m.id == client.id);
    if (idx >= 0) {
      _mcpClients[idx] = client;
    } else {
      _mcpClients.add(client);
    }
    await _save();
  }

  Future<void> deleteMcpClient(String clientId) async {
    _mcpClients.removeWhere((m) => m.id == clientId);
    await _save();
  }
}
