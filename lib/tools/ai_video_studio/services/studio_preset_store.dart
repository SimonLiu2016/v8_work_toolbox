import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../services/ai_logger.dart';
import '../../../services/app_paths.dart';
import '../models/studio_models.dart';

/// 全局美学风格与时代题材预设存储管理器（全局单例）。
///
/// 管理 8 大体系 35 套工业级美学风格（正向+专属负向避雷词）与全量时代题材世界观。
/// 数据持久化于 AppPaths.videoStudioPresetsDir 下的 JSON 文件，支持出厂自愈与跨项目实时响应。
class StudioPresetStore {
  StudioPresetStore._();

  static final StudioPresetStore instance = StudioPresetStore._();

  List<AestheticStyle> _styles = [];
  List<VisualEraGenre> _eras = [];
  List<StudioPromptTemplate> _templates = [];

  bool _initialized = false;
  bool get isInitialized => _initialized;

  final _stylesController = StreamController<List<AestheticStyle>>.broadcast();
  final _erasController = StreamController<List<VisualEraGenre>>.broadcast();
  final _templatesController = StreamController<List<StudioPromptTemplate>>.broadcast();

  Stream<List<AestheticStyle>> get stylesStream => _stylesController.stream;
  Stream<List<VisualEraGenre>> get erasStream => _erasController.stream;
  Stream<List<StudioPromptTemplate>> get templatesStream => _templatesController.stream;

  List<AestheticStyle> get styles {
    if (!_initialized) {
      // 尚未异步 init 时回退使用内置出厂常量
      return AestheticStyle.presets;
    }
    return List.unmodifiable(_styles);
  }

  List<VisualEraGenre> get eras {
    if (!_initialized) {
      // 尚未异步 init 时回退使用内置出厂常量
      return VisualEraGenre.presets;
    }
    return List.unmodifiable(_eras);
  }

  List<StudioPromptTemplate> get templates {
    if (!_initialized) {
      return StudioPromptTemplate.builtinPresets;
    }
    return List.unmodifiable(_templates);
  }

  /// 按分类对提示词模板进行分组
  Map<String, List<StudioPromptTemplate>> get templatesByCategory {
    final list = templates;
    final map = <String, List<StudioPromptTemplate>>{};
    for (final t in list) {
      map.putIfAbsent(t.category, () => []).add(t);
    }
    return map;
  }

  /// 根据 ID 查找提示词模板
  StudioPromptTemplate? getTemplateById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final normalized = id.trim().toLowerCase();
    for (final t in templates) {
      if (t.id.toLowerCase() == normalized) return t;
    }
    for (final b in StudioPromptTemplate.builtinPresets) {
      if (b.id.toLowerCase() == normalized) return b;
    }
    return null;
  }

  /// 便捷获取指定模板的当前有效内容
  String getPromptContent(String templateId, {String defaultFallback = ''}) {
    final t = getTemplateById(templateId);
    if (t != null) {
      return t.effectiveContent;
    }
    return defaultFallback;
  }

  /// 按 8 大体系对美学风格进行分组
  Map<String, List<AestheticStyle>> get stylesByCategory {
    final list = styles;
    final map = <String, List<AestheticStyle>>{};
    for (final s in list) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  /// 根据 ID 查找美学风格
  AestheticStyle? getStyleById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final normalized = id.trim().toLowerCase();
    for (final s in styles) {
      if (s.id.toLowerCase() == normalized) return s;
    }
    return null;
  }

  /// 根据 ID 查找时代题材
  VisualEraGenre? getEraById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final normalized = id.trim().toLowerCase();
    for (final e in eras) {
      if (e.id.toLowerCase() == normalized) return e;
    }
    return null;
  }

  /// 初始化并执行出厂自愈检查
  Future<void> init() async {
    try {
      final dir = AppPaths.videoStudioPresetsDir;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      await _loadStyles();
      await _loadEras();
      await _loadTemplates();
      _initialized = true;
      _stylesController.add(_styles);
      _erasController.add(_eras);
      _templatesController.add(_templates);
    } catch (e, stack) {
      AiLogger.logError('StudioPresetStore 初始化失败: $e\n$stack');
      _styles = List.of(AestheticStyle.presets);
      _eras = List.of(VisualEraGenre.presets);
      _templates = List.of(StudioPromptTemplate.builtinPresets);
      _initialized = true;
    }
  }

  Future<void> _loadStyles() async {
    final file = AppPaths.aestheticStylesFile;
    if (!file.existsSync() || file.lengthSync() == 0) {
      _styles = List.of(AestheticStyle.presets);
      await _persistStyles();
      return;
    }

    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      final parsed = list
          .whereType<Map<String, dynamic>>()
          .map((m) => AestheticStyle.fromJson(m))
          .toList();
      if (parsed.isEmpty) {
        _styles = List.of(AestheticStyle.presets);
        await _persistStyles();
      } else {
        // 自愈：确保内置出厂的预设若有缺失自动增量补齐
        final existingIds = parsed.map((e) => e.id.toLowerCase()).toSet();
        var hasNew = false;
        for (final builtin in AestheticStyle.presets) {
          if (!existingIds.contains(builtin.id.toLowerCase())) {
            parsed.add(builtin);
            hasNew = true;
          }
        }
        _styles = parsed;
        if (hasNew) {
          await _persistStyles();
        }
      }
    } catch (e) {
      AiLogger.logWarning('美学风格预设文件解析异常，重置为出厂预设: $e');
      _styles = List.of(AestheticStyle.presets);
      await _persistStyles();
    }
  }

  Future<void> _loadEras() async {
    final file = AppPaths.visualErasFile;
    if (!file.existsSync() || file.lengthSync() == 0) {
      _eras = List.of(VisualEraGenre.presets);
      await _persistEras();
      return;
    }

    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      final parsed = list
          .whereType<Map<String, dynamic>>()
          .map((m) => VisualEraGenre.fromJson(m))
          .toList();
      if (parsed.isEmpty) {
        _eras = List.of(VisualEraGenre.presets);
        await _persistEras();
      } else {
        // 自愈与版本同步：以代码中最新出厂常量刷新所有内置预设，并补齐新增项，保留用户自定义项
        final builtinMap = {
          for (final b in VisualEraGenre.presets) b.id.toLowerCase(): b,
        };
        final updatedList = <VisualEraGenre>[];
        final seenIds = <String>{};
        for (final item in parsed) {
          final idLower = item.id.toLowerCase();
          seenIds.add(idLower);
          if (builtinMap.containsKey(idLower) && item.isBuiltin) {
            updatedList.add(builtinMap[idLower]!);
          } else {
            updatedList.add(item);
          }
        }
        for (final builtin in VisualEraGenre.presets) {
          if (!seenIds.contains(builtin.id.toLowerCase())) {
            updatedList.add(builtin);
          }
        }
        _eras = updatedList;
        await _persistEras();
      }
    } catch (e) {
      AiLogger.logWarning('时代题材预设文件解析异常，重置为出厂预设: $e');
      _eras = List.of(VisualEraGenre.presets);
      await _persistEras();
    }
  }

  Future<void> _loadTemplates() async {
    final file = AppPaths.promptTemplatesFile;
    if (!file.existsSync() || file.lengthSync() == 0) {
      _templates = List.of(StudioPromptTemplate.builtinPresets);
      await _persistTemplates();
      return;
    }

    try {
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      final parsed = list
          .whereType<Map<String, dynamic>>()
          .map((m) => StudioPromptTemplate.fromJson(m))
          .toList();
      if (parsed.isEmpty) {
        _templates = List.of(StudioPromptTemplate.builtinPresets);
        await _persistTemplates();
      } else {
        // 自愈与版本同步：确保内置模板缺失自动补齐，并更新内置项的 defaultContent/description，同时保留用户自定 override
        final builtinMap = {
          for (final b in StudioPromptTemplate.builtinPresets) b.id.toLowerCase(): b,
        };
        final updatedList = <StudioPromptTemplate>[];
        final seenIds = <String>{};
        for (final item in parsed) {
          final idLower = item.id.toLowerCase();
          seenIds.add(idLower);
          if (builtinMap.containsKey(idLower)) {
            final builtin = builtinMap[idLower]!;
            var overrideText = item.userOverride;
            // 平滑升级旧版包含否定词的模板，避免粉色大象效应
            if (idLower == 'character_age_staging' &&
                overrideText != null &&
                overrideText.contains('非低幼儿童')) {
              overrideText = overrideText
                  .replaceAll('，非低幼儿童，非幼童童子，非小娃娃', '')
                  .replaceAll('，非低幼儿童，非幼童童子', '')
                  .replaceAll('，非青少年，非幼童', '')
                  .replaceAll(RegExp(r'[,，\s]*非(低幼|幼童|小娃娃|儿童|矮短)[^,，。；\n\r]*'), '');
            }
            updatedList.add(builtin.copyWith(
              userOverride: overrideText,
              updatedAt: item.updatedAt,
            ));
          } else {
            updatedList.add(item);
          }
        }
        for (final builtin in StudioPromptTemplate.builtinPresets) {
          if (!seenIds.contains(builtin.id.toLowerCase())) {
            updatedList.add(builtin);
          }
        }
        _templates = updatedList;
        await _persistTemplates();
      }
    } catch (e) {
      AiLogger.logWarning('提示词模板文件解析异常，重置为出厂预设: $e');
      _templates = List.of(StudioPromptTemplate.builtinPresets);
      await _persistTemplates();
    }
  }

  Future<void> _persistStyles() async {
    final file = AppPaths.aestheticStylesFile;
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_styles.map((s) => s.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> _persistEras() async {
    final file = AppPaths.visualErasFile;
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_eras.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  Future<void> _persistTemplates() async {
    final file = AppPaths.promptTemplatesFile;
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_templates.map((t) => t.toJson()).toList()),
      flush: true,
    );
  }

  /// 保存或更新提示词模板
  Future<void> saveTemplate(StudioPromptTemplate template) async {
    final idx = _templates.indexWhere((t) => t.id.toLowerCase() == template.id.toLowerCase());
    if (idx >= 0) {
      _templates[idx] = template;
    } else {
      _templates.add(template);
    }
    await _persistTemplates();
    _templatesController.add(_templates);
  }

  /// 单项重置提示词模板为出厂默认
  Future<void> resetTemplateToDefault(String templateId) async {
    final idx = _templates.indexWhere((t) => t.id.toLowerCase() == templateId.toLowerCase());
    if (idx >= 0) {
      _templates[idx] = _templates[idx].copyWith(clearOverride: true, updatedAt: DateTime.now());
      await _persistTemplates();
      _templatesController.add(_templates);
    }
  }

  /// 全部重置提示词模板为出厂默认
  Future<void> resetAllTemplatesToDefault() async {
    _templates = List.of(StudioPromptTemplate.builtinPresets);
    await _persistTemplates();
    _templatesController.add(_templates);
  }

  /// 保存或更新美学风格
  Future<void> saveStyle(AestheticStyle style) async {
    final idx = _styles.indexWhere((s) => s.id == style.id);
    if (idx >= 0) {
      _styles[idx] = style;
    } else {
      _styles.add(style);
    }
    await _persistStyles();
    _stylesController.add(_styles);
  }

  /// 删除自定义美学风格（内置出厂预设禁止删除）
  Future<bool> deleteStyle(String id) async {
    final target = getStyle(id);
    if (target == null || target.isBuiltin) return false;
    _styles.removeWhere((s) => s.id == id);
    await _persistStyles();
    _stylesController.add(_styles);
    return true;
  }

  /// 重置美学风格为 35 套出厂预设
  Future<void> resetStylesToDefault() async {
    _styles = List.of(AestheticStyle.presets);
    await _persistStyles();
    _stylesController.add(_styles);
  }

  /// 保存或更新时代题材
  Future<void> saveEra(VisualEraGenre era) async {
    final idx = _eras.indexWhere((e) => e.id == era.id);
    if (idx >= 0) {
      _eras[idx] = era;
    } else {
      _eras.add(era);
    }
    await _persistEras();
    _erasController.add(_eras);
  }

  /// 删除自定义时代题材（内置出厂预设禁止删除）
  Future<bool> deleteEra(String id) async {
    final target = getEra(id);
    if (target == null || target.isBuiltin) return false;
    _eras.removeWhere((e) => e.id == id);
    await _persistEras();
    _erasController.add(_eras);
    return true;
  }

  /// 重置时代题材为出厂预设
  Future<void> resetErasToDefault() async {
    _eras = List.of(VisualEraGenre.presets);
    await _persistEras();
    _erasController.add(_eras);
  }

  /// 根据 ID 精确或大小写不敏感查找美学风格
  AestheticStyle? getStyle(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final normalized = id.trim().toLowerCase();
    for (final s in styles) {
      if (s.id.toLowerCase() == normalized) return s;
    }
    return AestheticStyle.fromId(id);
  }

  /// 根据 ID 精确或大小写不敏感查找时代题材
  VisualEraGenre? getEra(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final normalized = id.trim().toLowerCase();
    for (final e in eras) {
      if (e.id.toLowerCase() == normalized) return e;
    }
    return VisualEraGenre.fromId(id);
  }

  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
    _styles.clear();
    _eras.clear();
    _templates.clear();
  }
}
