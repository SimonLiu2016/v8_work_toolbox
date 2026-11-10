import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../models/playground_models.dart';
import '../models/prompt_template_models.dart';

/// 提示词效果库全局单例管理器。
///
/// 统一管理多维度提示词模板（镜头、动作、粒子、光影、艺术风格）与各模型实测样片（Benchmark）。
/// 数据持久化于 [AppPaths.sharedPromptTemplatesDir] 下的 `catalog.json` 与 `benchmarks/` 目录。
class PromptTemplateStore {
  PromptTemplateStore._();

  static final PromptTemplateStore instance = PromptTemplateStore._();

  final List<VisualPromptTemplate> _templates = [];
  bool _initialized = false;
  bool get isInitialized => _initialized;

  final _templatesController =
      StreamController<List<VisualPromptTemplate>>.broadcast();

  Stream<List<VisualPromptTemplate>> get templatesStream =>
      _templatesController.stream;

  List<VisualPromptTemplate> get templates {
    return List.unmodifiable(_templates);
  }

  /// 初始化并自愈加载出厂内置模板与本地用户持久化条目。
  Future<void> init() async {
    if (_initialized) return;

    try {
      final dir = AppPaths.sharedPromptTemplatesDir;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final benchDir = AppPaths.promptBenchmarksDir;
      if (!benchDir.existsSync()) {
        benchDir.createSync(recursive: true);
      }

      // 1. 读取应用安装包中的出厂预置
      final builtinTemplates = await _loadBuiltinPresets();

      // 2. 读取本地持久化的 catalog.json
      final catalogFile = AppPaths.promptTemplateCatalogFile;
      if (!catalogFile.existsSync()) {
        _templates.clear();
        _templates.addAll(builtinTemplates);
        await _saveCatalogAtomic();
      } else {
        final content = await catalogFile.readAsString();
        if (content.trim().isEmpty) {
          _templates.clear();
          _templates.addAll(builtinTemplates);
          await _saveCatalogAtomic();
        } else {
          final decoded = jsonDecode(content);
          final localTemplates = <VisualPromptTemplate>[];
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                try {
                  localTemplates.add(VisualPromptTemplate.fromJson(item));
                } catch (e) {
                  debugPrint('[PromptTemplateStore] 解析模板条目失败: $e');
                }
              }
            }
          }

          // 3. 自愈合并：若出厂模板有新增，增量合并进本地库；若已有出厂模板，保留本地用户自测的 Benchmarks
          final mergedMap = <String, VisualPromptTemplate>{};
          for (final local in localTemplates) {
            mergedMap[local.id] = local;
          }

          for (final builtin in builtinTemplates) {
            if (!mergedMap.containsKey(builtin.id)) {
              mergedMap[builtin.id] = builtin;
            } else {
              final existing = mergedMap[builtin.id]!;
              // 若本地尚未有实测样片，采用出厂定义；若本地有实测样片，保留其 benchmarks
              if (existing.benchmarks.isNotEmpty) {
                mergedMap[builtin.id] = builtin.copyWith(
                  benchmarks: existing.benchmarks,
                  recommendedParams: existing.recommendedParams.isNotEmpty
                      ? existing.recommendedParams
                      : builtin.recommendedParams,
                  updatedAt: existing.updatedAt,
                );
              }
            }
          }

          _templates.clear();
          _templates.addAll(mergedMap.values);
          await _saveCatalogAtomic();
        }
      }

      _initialized = true;
      _templatesController.add(List.unmodifiable(_templates));
      debugPrint(
        '[PromptTemplateStore] 提示词模板库初始化完成，当前加载 ${_templates.length} 个模板',
      );
    } catch (e, stack) {
      debugPrint('[PromptTemplateStore] 初始化失败: $e\n$stack');
      _initialized = true;
    }
  }

  /// 加载内置 assets 预置
  Future<List<VisualPromptTemplate>> _loadBuiltinPresets() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/prompt_templates/builtin_templates.json',
      );
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => VisualPromptTemplate.fromJson(e))
            .toList();
      }
    } catch (e) {
      debugPrint('[PromptTemplateStore] 加载出厂内置模板资产异常: $e');
    }
    return const [];
  }

  /// 按多重维度过滤检索模板
  List<VisualPromptTemplate> filter({
    String? majorCategory,
    String? subcategory,
    PlaygroundChannel? channel,
    String? searchQuery,
    String? tag,
  }) {
    return _templates.where((t) {
      if (majorCategory != null &&
          majorCategory.isNotEmpty &&
          t.majorCategory != majorCategory) {
        return false;
      }
      if (subcategory != null &&
          subcategory.isNotEmpty &&
          t.subcategory != subcategory) {
        return false;
      }
      if (channel != null && t.channel != channel) {
        return false;
      }
      if (tag != null && tag.isNotEmpty && !t.tags.contains(tag)) {
        return false;
      }
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final query = searchQuery.trim().toLowerCase();
        final inTitle = t.title.toLowerCase().contains(query);
        final inSubcat = t.subcategory.toLowerCase().contains(query);
        final inPrompt = t.promptTemplate.toLowerCase().contains(query);
        final inTags = t.tags.any((tag) => tag.toLowerCase().contains(query));
        if (!inTitle && !inSubcat && !inPrompt && !inTags) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// 根据 ID 查找模板
  VisualPromptTemplate? getById(String id) {
    for (final t in _templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 新增或更新模板
  Future<void> saveTemplate(VisualPromptTemplate template) async {
    final index = _templates.indexWhere((t) => t.id == template.id);
    final updated = template.copyWith(updatedAt: DateTime.now());
    if (index >= 0) {
      _templates[index] = updated;
    } else {
      _templates.insert(0, updated);
    }
    await _saveCatalogAtomic();
    _templatesController.add(List.unmodifiable(_templates));
  }

  /// 删除模板（出厂模板默认不彻底抹除，若删除可作为自定义模板处理）
  Future<void> deleteTemplate(String id) async {
    final index = _templates.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _templates.removeAt(index);
      await _saveCatalogAtomic();
      _templatesController.add(List.unmodifiable(_templates));
    }
  }

  /// 记录特定模型实测样片（Benchmark）
  Future<void> recordBenchmark({
    required String templateId,
    required String providerId,
    required String modelName,
    String modelVersion = '',
    required File mediaFile,
    required String testedPrompt,
    int qualityRating = 5,
    bool isRecommended = true,
    Map<String, dynamic>? extraParams,
  }) async {
    final template = getById(templateId);
    if (template == null) return;

    if (!mediaFile.existsSync()) {
      debugPrint('[PromptTemplateStore] 待记录样片文件不存在: ${mediaFile.path}');
      return;
    }

    // 归档目标路径
    final targetDir = AppPaths.promptBenchmarkTemplateDir(templateId);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final ext = p.extension(mediaFile.path);
    final sanitizedModel = modelName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final filename = '${sanitizedModel}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destinationFile = File(p.join(targetDir.path, filename));

    await mediaFile.copy(destinationFile.path);

    final newBenchmark = TemplateModelBenchmark(
      providerId: providerId,
      modelName: modelName,
      modelVersion: modelVersion,
      sampleMediaPath: destinationFile.path,
      testedPrompt: testedPrompt,
      qualityRating: qualityRating,
      isRecommended: isRecommended,
      verifiedAt: DateTime.now(),
      extraParams: extraParams,
    );

    // 更新或替换同一型号的既有样片
    final benchmarks = List<TemplateModelBenchmark>.from(template.benchmarks);
    final existingIdx = benchmarks.indexWhere(
      (b) => b.modelName.toLowerCase() == modelName.toLowerCase(),
    );

    if (existingIdx >= 0) {
      // 删除旧样片文件
      final oldPath = benchmarks[existingIdx].sampleMediaPath;
      try {
        final oldFile = File(oldPath);
        if (oldFile.existsSync()) {
          oldFile.deleteSync();
        }
      } catch (_) {}
      benchmarks[existingIdx] = newBenchmark;
    } else {
      benchmarks.add(newBenchmark);
    }

    final updatedTemplate = template.copyWith(benchmarks: benchmarks);
    await saveTemplate(updatedTemplate);
  }

  /// 更新某模型样片的评分与标杆状态
  Future<void> updateBenchmarkRating({
    required String templateId,
    required String modelName,
    required int qualityRating,
    required bool isRecommended,
  }) async {
    final template = getById(templateId);
    if (template == null) return;

    final benchmarks = List<TemplateModelBenchmark>.from(template.benchmarks);
    final idx = benchmarks.indexWhere(
      (b) => b.modelName.toLowerCase() == modelName.toLowerCase(),
    );
    if (idx >= 0) {
      benchmarks[idx] = benchmarks[idx].copyWith(
        qualityRating: qualityRating,
        isRecommended: isRecommended,
      );
      final updated = template.copyWith(benchmarks: benchmarks);
      await saveTemplate(updated);
    }
  }

  /// 删除某模型下的实测样片
  Future<void> deleteBenchmark({
    required String templateId,
    required String modelName,
  }) async {
    final template = getById(templateId);
    if (template == null) return;

    final benchmarks = List<TemplateModelBenchmark>.from(template.benchmarks);
    final idx = benchmarks.indexWhere(
      (b) => b.modelName.toLowerCase() == modelName.toLowerCase(),
    );
    if (idx >= 0) {
      final removed = benchmarks.removeAt(idx);
      try {
        final f = File(removed.sampleMediaPath);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
      final updated = template.copyWith(benchmarks: benchmarks);
      await saveTemplate(updated);
    }
  }

  /// 清理孤儿多媒体样片（磁盘上存在但不再被任何模板引用的文件）
  Future<int> cleanupOrphanMedia() async {
    final rootDir = AppPaths.promptBenchmarksDir;
    if (!rootDir.existsSync()) return 0;

    final referencedPaths = <String>{};
    for (final t in _templates) {
      for (final b in t.benchmarks) {
        if (b.sampleMediaPath.isNotEmpty) {
          referencedPaths.add(b.sampleMediaPath);
        }
      }
    }

    int cleanedCount = 0;
    try {
      await for (final entity in rootDir.list(recursive: true)) {
        if (entity is File) {
          if (!referencedPaths.contains(entity.path)) {
            try {
              entity.deleteSync();
              cleanedCount++;
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[PromptTemplateStore] 清理孤儿文件异常: $e');
    }
    return cleanedCount;
  }

  /// 原子保存 catalog.json
  Future<void> _saveCatalogAtomic() async {
    final catalogFile = AppPaths.promptTemplateCatalogFile;
    final parent = catalogFile.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    final tempFile = File('${catalogFile.path}.tmp');
    final jsonList = _templates.map((t) => t.toJson()).toList();
    final jsonText = const JsonEncoder.withIndent('  ').convert(jsonList);

    await tempFile.writeAsString(jsonText, flush: true);
    if (catalogFile.existsSync()) {
      await catalogFile.delete();
    }
    await tempFile.rename(catalogFile.path);
  }
}
