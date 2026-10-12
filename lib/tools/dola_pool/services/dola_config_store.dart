import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../../../services/media_capability.dart';

/// Dola 号池的能力覆盖配置。
///
/// **为什么单独一个 store 而不走 `AiProviderConfig.mediaCapabilities`**：
/// 号池不是 provider。provider 的语义是「一个 baseUrl + 一个密钥」，号池是
/// N 个 sessionid 的调度池——塞进 provider 会让 `baseUrl`、`keychainKeyId`
/// 这些字段全部失去意义。
///
/// 覆盖优先级：本 store 的用户覆盖 > `MediaCapabilityPresets` 内置预设 >
/// 协议保守默认。第三条由既有的 `MediaCapabilityResolver` 提供，本 store 通过
/// 实现 [AiProviderConfigLike] 接入前两条，**resolver 无需改签名**。
///
/// 文件位置与账号元数据同目录（`AppPaths.dolaDir`），因为能力覆盖与号池账号
/// 同生命周期——换一批账号、换模型版本，能力可能都不同。
class DolaConfigStore extends ChangeNotifier
    implements AiProviderConfigLike {
  DolaConfigStore._();
  static final DolaConfigStore instance = DolaConfigStore._();

  static const String _fileName = 'dola_capabilities.json';

  /// 协议 id。号池的请求形态是自研的 HTTP + BDMS 签名，不属于 openai 系列，
  /// 给一个专有 id 让 `MediaCapabilityDefaults.forProtocolId` 落到保守壳。
  @override
  String get protocolId => 'dola';

  Map<String, MediaModelCapability> _overrides =
      const <String, MediaModelCapability>{};
  bool _initialized = false;

  bool get isInitialized => _initialized;

  @override
  Map<String, MediaModelCapability> get mediaCapabilities => _overrides;

  File get _storageFile =>
      File(p.join(AppPaths.dolaDir.path, _fileName));

  Future<void> init() async {
    if (_initialized) return;
    try {
      final file = _storageFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            _overrides = decoded.map(
              (k, v) => MapEntry(
                k as String,
                v is Map
                    ? MediaModelCapability.fromJson(v.cast<String, dynamic>())
                    : const MediaModelCapability(),
              ),
            );
          }
        }
      }
    } catch (e) {
      // 初始化失败不抛：号池配置缺失时回落到内置预设，功能仍可用。但必须留
      // 下可诊断的信号——「用户改了配置却不生效」比「没有配置」更难排查。
      debugPrint('[DolaConfigStore] init error（回落内置预设）: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// 取某个模型的能力：用户覆盖优先，否则内置预设。
  MediaModelCapability? overrideFor(String modelId) => _overrides[modelId];

  /// 写入或删除某个模型的能力覆盖。
  ///
  /// 传 null 删除该模型的覆盖，回落到内置预设。
  Future<void> save(String modelId, MediaModelCapability? capability) async {
    final next = Map<String, MediaModelCapability>.of(_overrides);
    if (capability == null) {
      next.remove(modelId);
    } else {
      next[modelId] = capability;
    }
    _overrides = Map.unmodifiable(next);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final file = _storageFile;
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          _overrides.map((k, v) => MapEntry(k, v.toJson())),
        ),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[DolaConfigStore] persist error: $e');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _overrides = const <String, MediaModelCapability>{};
    _initialized = false;
  }
}
