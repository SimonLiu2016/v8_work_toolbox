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

/// 槽位候选绑定项（有序候选列表中的单个条目）
class SlotCandidate {
  final String providerId;
  final String model;
  final int priority;

  const SlotCandidate({
    required this.providerId,
    required this.model,
    required this.priority,
  });

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'model': model,
    'priority': priority,
  };

  factory SlotCandidate.fromJson(Map<String, dynamic> json) {
    return SlotCandidate(
      providerId: json['providerId'] as String? ?? '',
      model: json['model'] as String? ?? '',
      priority: json['priority'] as int? ?? 0,
    );
  }

  SlotCandidate copyWith({String? providerId, String? model, int? priority}) {
    return SlotCandidate(
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      priority: priority ?? this.priority,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SlotCandidate &&
          runtimeType == other.runtimeType &&
          providerId == other.providerId &&
          model == other.model;

  @override
  int get hashCode => providerId.hashCode ^ model.hashCode;

  @override
  String toString() =>
      'SlotCandidate(providerId: $providerId, model: $model, priority: $priority)';
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
  final int timeoutSeconds;

  const McpClientConfig({
    required this.id,
    required this.name,
    required this.transport,
    required this.endpointOrCommand,
    this.args = const [],
    this.env = const {},
    this.headers = const {},
    this.enabled = true,
    this.timeoutSeconds = 60,
  });

  McpClientConfig copyWith({
    String? id,
    String? name,
    String? transport,
    String? endpointOrCommand,
    List<String>? args,
    Map<String, String>? env,
    Map<String, String>? headers,
    bool? enabled,
    int? timeoutSeconds,
  }) {
    return McpClientConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      endpointOrCommand: endpointOrCommand ?? this.endpointOrCommand,
      args: args ?? this.args,
      env: env ?? this.env,
      headers: headers ?? this.headers,
      enabled: enabled ?? this.enabled,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  static McpClientConfig firecrawlPreset({
    String id = 'mcp_firecrawl',
    String name = 'Firecrawl 爬虫与搜索',
    String apiUrl = 'https://43-133-77-38.nip.io',
    String apiKey =
        '9f3a39789003582170a952660dc66bba31190da43e4875591916caafef6d818c',
    bool enabled = true,
  }) {
    return McpClientConfig(
      id: id,
      name: name,
      transport: 'stdio',
      endpointOrCommand: 'npx',
      args: const ['-y', 'firecrawl-mcp'],
      env: {'FIRECRAWL_API_URL': apiUrl, 'FIRECRAWL_API_KEY': apiKey},
      timeoutSeconds: 120,
      enabled: enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'transport': transport,
    'endpointOrCommand': endpointOrCommand,
    'args': args,
    'env': env,
    'headers': headers,
    'enabled': enabled,
    'timeoutSeconds': timeoutSeconds,
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
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 60,
    );
  }
}

/// AI 配置中枢存储
class AiConfigStore {
  AiConfigStore._();
  static final AiConfigStore instance = AiConfigStore._();

  File? _configFile;
  List<AiProviderConfig> _providers = [];
  Map<String, List<SlotCandidate>> _slotBindings = {};
  List<McpClientConfig> _mcpClients = [];

  /// 本进程是否已完成初始化。
  ///
  /// 单例状态是**进程级**的：`desktop_multi_window` 的每个子窗口都会重跑
  /// `main()`，若该窗口的启动路径没有调用 [init]，这里就是 false，槽位绑定表
  /// 为空。此前这会让下游报「槽位无可用候选供应商」，与「确实没绑候选」混为
  /// 一谈，排查时无法归因。
  bool _isInitialized = false;

  /// 最近一次 [init] 失败的原因；成功后被清空。
  String? _lastInitError;

  List<AiProviderConfig> get providers => List.unmodifiable(_providers);
  Map<String, List<SlotCandidate>> get slotBindings =>
      Map.unmodifiable(_slotBindings);
  List<McpClientConfig> get mcpClients => List.unmodifiable(_mcpClients);

  /// 本进程的配置存储是否已初始化成功。
  bool get isInitialized => _isInitialized;

  /// 仅供测试：把单例重置为「尚未初始化」的干净状态。
  ///
  /// 生产代码不得调用——子窗口漏初始化的bug 正是靠这个状态被诊断出来的。
  @visibleForTesting
  Future<void> resetForTesting() async {
    _configFile = null;
    _providers = [];
    _slotBindings = {};
    _mcpClients = [];
    _isInitialized = false;
    _lastInitError = null;
  }

  /// 最近一次初始化失败的原因；无失败时为 null。
  String? get lastInitError => _lastInitError;

  /// 初始化未完成时的可诊断描述，供槽位路由构造可归因的错误消息。
  ///
  /// 已成功初始化且没有保留的加载失败时返回 null。
  String? get uninitializedReason {
    if (_isInitialized && _lastInitError == null) return null;
    return _lastInitError ??
        'AI 配置存储尚未初始化。此窗口进程可能未在启动时完成初始化'
            '（详见 main.dart 的 WindowServices 必需服务清单）。';
  }

  Future<void> init({Directory? customRootDir}) async {
    // 每次 init 都是全新一次加载尝试：先清掉上一次的失败原因，
    // `_load()` 遇到配置损坏会重新记录更具体的原因。
    _lastInitError = null;
    try {
      Directory dir;
      if (customRootDir != null) {
        dir = customRootDir;
      } else {
        final home = Platform.environment['HOME'];
        if (Platform.isMacOS && home != null && home.isNotEmpty) {
          dir = Directory(
            p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'),
          );
        } else {
          final appSupport = await getApplicationSupportDirectory();
          dir = Directory(p.join(appSupport.path, 'V8WorkToolbox'));
        }
      }

      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      _configFile = File(p.join(dir.path, 'ai_config.json'));
      await KeychainService.instance.init(customRootDir: dir);
      await _load();
      _isInitialized = true;
      // `_load()` 内部处理配置损坏：保留它记录的更具体原因，不清空。
    } catch (e) {
      // 记录但不抛出：main() 的 fail-soft 契约不允许单个服务阻断 runApp。
      // 但必须留下可诊断信号，否则下游只能看到「配置为空」。
      _isInitialized = false;
      _lastInitError = '初始化 AI 配置失败: $e';
      debugPrint(_lastInitError);
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
      _providers = providerList
          .map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();

      final slots = (json['defaultSlots'] as Map<String, dynamic>?) ?? {};
      bool needsMigration = false;
      _slotBindings = slots.map((key, value) {
        if (value is List) {
          // 新格式：候选列表
          final candidates = value
              .map((e) => SlotCandidate.fromJson(e as Map<String, dynamic>))
              .toList();
          return MapEntry(key, candidates);
        } else if (value is Map) {
          // 旧格式：单一 {providerId, model} 映射 → 自动迁移为单元素候选列表
          needsMigration = true;
          final providerId = (value['providerId'] as String?) ?? '';
          final model = (value['model'] as String?) ?? '';
          if (providerId.isNotEmpty) {
            return MapEntry(key, [
              SlotCandidate(providerId: providerId, model: model, priority: 0),
            ]);
          }
          return MapEntry(key, <SlotCandidate>[]);
        }
        return MapEntry(key, <SlotCandidate>[]);
      });

      // 确保所有标准槽位存在
      for (final slot in ['text', 'multimodal', 'tts', 'stt']) {
        _slotBindings.putIfAbsent(slot, () => <SlotCandidate>[]);
      }

      final mcps = (json['mcpServers'] as List<dynamic>?) ?? [];
      _mcpClients = mcps
          .map((e) => McpClientConfig.fromJson(e as Map<String, dynamic>))
          .toList();
      if (_mcpClients.isEmpty) {
        _mcpClients.add(McpClientConfig.firecrawlPreset());
        await _save();
      }

      // 旧格式检测到后立即重新保存为新格式
      if (needsMigration) {
        debugPrint('检测到旧格式 defaultSlots，已自动迁移为候选列表格式');
        await _save();
      }
    } catch (e) {
      // 配置损坏/不可读是**真实的加载失败**，不能静默换成空默认值——那会让用户
      // 以为「没绑候选」，而实际是文件坏了。保留原因供 [uninitializedReason]
      // 与槽位错误消息使用；默认值仍写入以保持功能可继续（不阻断启动）。
      _lastInitError = '读取 ai_config.json 异常: $e';
      debugPrint('$_lastInitError，加载默认配置');
      _initDefaults();
    }
  }

  void _initDefaults() {
    _providers = [];
    _slotBindings = {
      'text': <SlotCandidate>[],
      'multimodal': <SlotCandidate>[],
      'tts': <SlotCandidate>[],
      'stt': <SlotCandidate>[],
    };
    _mcpClients = [McpClientConfig.firecrawlPreset()];
  }

  Future<void> _save() async {
    if (_configFile == null) return;
    try {
      final map = {
        'providers': _providers.map((p) => p.toJson()).toList(),
        'defaultSlots': _slotBindings.map(
          (key, candidates) =>
              MapEntry(key, candidates.map((c) => c.toJson()).toList()),
        ),
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
  /// 保存供应商。配置（ai_config.json）总是先落盘；apiKey 非空时再写加密
  /// 密钥库——密钥写入失败会抛出 [KeychainWriteException]，此时配置已保存，
  /// 调用方可向用户区分提示"配置已保存但密钥写入失败"。
  Future<void> saveProvider(AiProviderConfig provider, {String? apiKey}) async {
    final idx = _providers.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) {
      _providers[idx] = provider;
    } else {
      _providers.add(provider);
    }
    // 配置先落盘，保证密钥库故障不会吞掉用户填写的表单
    await _save();

    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        await KeychainService.instance.writeSecret(
          provider.keychainKeyId,
          apiKey,
        );
      } catch (e) {
        throw KeychainWriteException('API Key 写入加密密钥库失败: $e');
      }
    }
  }

  Future<void> deleteProvider(String providerId) async {
    final p = _providers.firstWhere(
      (e) => e.id == providerId,
      orElse: () => const AiProviderConfig(
        id: '',
        name: '',
        protocol: AiProtocolType.openai,
        baseUrl: '',
        keychainKeyId: '',
      ),
    );
    if (p.keychainKeyId.isNotEmpty) {
      await KeychainService.instance.deleteSecret(p.keychainKeyId);
    }
    _providers.removeWhere((e) => e.id == providerId);

    // 清理所有槽位中引用了被删除供应商的候选项
    _slotBindings.forEach((slot, candidates) {
      candidates.removeWhere((c) => c.providerId == providerId);
      // 重新分配优先级
      for (int i = 0; i < candidates.length; i++) {
        candidates[i] = candidates[i].copyWith(priority: i);
      }
    });

    await _save();
  }

  /// @deprecated 使用 addSlotCandidate / removeSlotCandidate / reorderSlotCandidates 替代
  /// 保留向后兼容：将单一绑定设置为该槽位的唯一候选
  Future<void> setSlotBinding(
    String slotName,
    String providerId,
    String modelName,
  ) async {
    if (providerId.isEmpty) {
      _slotBindings[slotName] = <SlotCandidate>[];
    } else {
      _slotBindings[slotName] = [
        SlotCandidate(providerId: providerId, model: modelName, priority: 0),
      ];
    }
    await _save();
  }

  /// 向槽位候选列表末尾追加新候选
  Future<void> addSlotCandidate(
    String slotName,
    String providerId,
    String model,
  ) async {
    final candidates = _slotBindings[slotName] ?? <SlotCandidate>[];
    final newPriority = candidates.length;
    candidates.add(
      SlotCandidate(
        providerId: providerId,
        model: model,
        priority: newPriority,
      ),
    );
    _slotBindings[slotName] = candidates;
    await _save();
  }

  /// 移除槽位中指定位置的候选
  Future<void> removeSlotCandidate(String slotName, int index) async {
    final candidates = _slotBindings[slotName];
    if (candidates == null || index < 0 || index >= candidates.length) return;
    candidates.removeAt(index);
    // 重新分配优先级
    for (int i = 0; i < candidates.length; i++) {
      candidates[i] = candidates[i].copyWith(priority: i);
    }
    await _save();
  }

  /// 调整槽位候选的优先级顺序（拖拽排序）
  Future<void> reorderSlotCandidates(
    String slotName,
    int oldIndex,
    int newIndex,
  ) async {
    final candidates = _slotBindings[slotName];
    if (candidates == null) return;
    if (oldIndex < 0 || oldIndex >= candidates.length) return;

    // Flutter ReorderableListView convention: adjust newIndex when moving down
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0 || newIndex >= candidates.length) return;
    if (oldIndex == newIndex) return;

    final item = candidates.removeAt(oldIndex);
    candidates.insert(newIndex, item);
    // 重新分配优先级
    for (int i = 0; i < candidates.length; i++) {
      candidates[i] = candidates[i].copyWith(priority: i);
    }
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

/// 密钥库写入失败：此时供应商配置已落盘，仅 API Key 未保存。
/// 调用方应将其与"保存失败"区分提示。
class KeychainWriteException implements Exception {
  final String message;
  const KeychainWriteException(this.message);

  @override
  String toString() => message;
}
