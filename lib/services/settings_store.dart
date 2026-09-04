import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'launcher_service.dart';

/// 旧配置文件迁移项定义
class MigrationEntry {
  final String toolId;
  final String oldFilePath;

  const MigrationEntry({required this.toolId, required this.oldFilePath});
}

/// 统一配置存储单例
class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  Directory? _rootDir;
  Directory? _configDir;
  File? _appConfigFile;
  Map<String, dynamic> _appConfig = {};
  String? _lastError;

  String? get lastError => _lastError;

  /// 旧配置迁移表
  static List<MigrationEntry> get migrationTable {
    final home = Platform.environment['HOME'] ?? '';
    return [
      if (home.isNotEmpty)
        MigrationEntry(
          toolId: 'clean-builds',
          oldFilePath: p.join(home, '.v8_cleaner_config.json'),
        ),
    ];
  }

  /// 初始化存储与目录结构，并执行一次性迁移
  Future<void> init({Directory? rootDir, List<MigrationEntry>? customMigrations}) async {
    try {
      if (rootDir != null) {
        _rootDir = rootDir;
      } else {
        final home = Platform.environment['HOME'];
        if (Platform.isMacOS && home != null && home.isNotEmpty) {
          _rootDir = Directory(
            p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'),
          );
        } else {
          final appSupport = await getApplicationSupportDirectory();
          _rootDir = Directory(p.join(appSupport.path, 'V8WorkToolbox'));
        }
      }

      if (!_rootDir!.existsSync()) {
        _rootDir!.createSync(recursive: true);
      }

      _configDir = Directory(p.join(_rootDir!.path, 'config'));
      if (!_configDir!.existsSync()) {
        _configDir!.createSync(recursive: true);
      }

      _appConfigFile = File(p.join(_rootDir!.path, 'app.json'));
      await _loadAppConfig();
      await _runMigrationsIfNeeded(customMigrations: customMigrations);
    } catch (e) {
      _lastError = '初始化配置存储失败: $e';
      debugPrint(_lastError);
    }
  }

  /// 原子写入文件（写入 .tmp 后原子重命名）
  Future<void> _atomicWrite(File targetFile, String content) async {
    // 确保目标目录存在
    final dir = targetFile.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final tempFile = File('${targetFile.path}.tmp');
    await tempFile.writeAsString(content, flush: true);

    // 安全删除目标文件（可能不存在）
    try {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
    } catch (_) {
      // 文件可能已被删除，忽略错误
    }

    await tempFile.rename(targetFile.path);
  }

  // ---------------------------------------------------------------------------
  // 全局应用配置 (app.json)
  // ---------------------------------------------------------------------------

  Future<void> _loadAppConfig() async {
    if (_appConfigFile == null || !await _appConfigFile!.exists()) {
      _appConfig = _defaultAppConfig();
      await _saveAppConfig();
      return;
    }

    try {
      final content = await _appConfigFile!.readAsString();
      if (content.trim().isEmpty) {
        _appConfig = _defaultAppConfig();
      } else {
        _appConfig = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      _lastError = 'app.json 损坏，已回退默认配置: $e';
      debugPrint(_lastError);
      _appConfig = _defaultAppConfig();
    }
  }

  Map<String, dynamic> _defaultAppConfig() {
    return {
      'recentTools': <String>[],
      'hotkey': HotKeyConfig.defaultHotKey.toJson(),
      'migratedFrom': <String>[],
    };
  }

  Future<void> _saveAppConfig() async {
    if (_appConfigFile == null) return;
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(_appConfig);
      await _atomicWrite(_appConfigFile!, jsonStr);
    } catch (e) {
      _lastError = '保存 app.json 失败: $e';
      debugPrint(_lastError);
    }
  }

  // ---------------------------------------------------------------------------
  // 旧配置一次性迁移 (Task 3.3)
  // ---------------------------------------------------------------------------

  Future<void> _runMigrationsIfNeeded({List<MigrationEntry>? customMigrations}) async {
    if (_configDir == null) return;

    final migratedList = List<String>.from(_appConfig['migratedFrom'] ?? []);
    bool updated = false;
    final entries = customMigrations ?? migrationTable;

    for (final entry in entries) {
      final oldFile = File(entry.oldFilePath);
      final newTargetFile = File(p.join(_configDir!.path, '${entry.toolId}.json'));

      // 如果目标文件已存在，跳过迁移
      if (await newTargetFile.exists()) {
        continue;
      }

      // 如果旧文件存在，复制内容到新存储
      if (await oldFile.exists()) {
        try {
          final content = await oldFile.readAsString();
          // 验证合法 json
          jsonDecode(content);
          await _atomicWrite(newTargetFile, content);
          migratedList.add(entry.oldFilePath);
          updated = true;
          debugPrint('成功迁移旧配置: ${entry.oldFilePath} -> ${newTargetFile.path}');
        } catch (e) {
          debugPrint('迁移旧配置失败: ${entry.oldFilePath}, 错误: $e');
        }
      }
    }

    if (updated) {
      _appConfig['migratedFrom'] = migratedList;
      await _saveAppConfig();
    }
  }

  // ---------------------------------------------------------------------------
  // 工具配置读写 (config/<tool-id>.json)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> readToolConfig(String toolId) async {
    if (_configDir == null) await init();
    final file = File(p.join(_configDir!.path, '$toolId.json'));
    if (!await file.exists()) {
      return {};
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      _lastError = '工具 [$toolId] 配置文件损坏，已返回空配置: $e';
      debugPrint(_lastError);
      return {};
    }
  }

  Future<void> writeToolConfig(
    String toolId,
    Map<String, dynamic> data,
  ) async {
    if (_configDir == null) await init();
    final file = File(p.join(_configDir!.path, '$toolId.json'));
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      await _atomicWrite(file, jsonStr);
    } catch (e) {
      _lastError = '写入工具 [$toolId] 配置失败: $e';
      debugPrint(_lastError);
    }
  }

  // ---------------------------------------------------------------------------
  // 最近使用与全局快捷键辅助接口
  // ---------------------------------------------------------------------------

  List<String> getRecentToolIds() {
    return List<String>.from(_appConfig['recentTools'] ?? []);
  }

  Future<void> recordToolUsed(String toolId) async {
    final list = List<String>.from(_appConfig['recentTools'] ?? []);
    list.remove(toolId);
    list.insert(0, toolId);
    if (list.length > 8) {
      list.removeRange(8, list.length);
    }
    _appConfig['recentTools'] = list;
    await _saveAppConfig();
  }

  HotKeyConfig getHotKeyConfig() {
    final hotkeyJson = _appConfig['hotkey'] as Map<String, dynamic>?;
    return HotKeyConfig.fromJson(hotkeyJson);
  }

  Future<void> setHotKeyConfig(HotKeyConfig config) async {
    _appConfig['hotkey'] = config.toJson();
    await _saveAppConfig();
  }

  // ---------------------------------------------------------------------------
  // 磁盘瘦身用户保留标记 (slimmer-keep-list.json)
  // ---------------------------------------------------------------------------

  /// 读取用户标记保留的目录路径集合
  Future<Set<String>> getSlimmerKeepList() async {
    if (_configDir == null) await init();
    final file = File(p.join(_configDir!.path, 'slimmer-keep-list.json'));
    if (!await file.exists()) {
      return <String>{};
    }
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <String>{};
      final list = jsonDecode(content) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (e) {
      debugPrint('读取 slimmer-keep-list.json 失败: $e');
      // 文件损坏，删除后返回空集合（下次保存会重建）
      try {
        if (await file.exists()) {
          await file.delete();
          debugPrint('已删除损坏的 slimmer-keep-list.json');
        }
      } catch (_) {}
      return <String>{};
    }
  }

  /// 添加一个路径到用户保留列表
  Future<void> addSlimmerKeepPath(String path) async {
    final keepList = await getSlimmerKeepList();
    if (keepList.contains(path)) return;
    keepList.add(path);
    await _saveSlimmerKeepList(keepList);
  }

  /// 批量添加多个路径到用户保留列表（单次保存）
  Future<void> addSlimmerKeepPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final keepList = await getSlimmerKeepList();
    bool changed = false;
    for (final path in paths) {
      if (!keepList.contains(path)) {
        keepList.add(path);
        changed = true;
      }
    }
    if (changed) {
      await _saveSlimmerKeepList(keepList);
    }
  }

  /// 从用户保留列表移除一个路径
  Future<void> removeSlimmerKeepPath(String path) async {
    final keepList = await getSlimmerKeepList();
    if (!keepList.contains(path)) return;
    keepList.remove(path);
    await _saveSlimmerKeepList(keepList);
  }

  Future<void> _saveSlimmerKeepList(Set<String> keepList) async {
    if (_configDir == null) await init();
    final file = File(p.join(_configDir!.path, 'slimmer-keep-list.json'));
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(keepList.toList());
      await _atomicWrite(file, jsonStr);
    } catch (e) {
      _lastError = '保存 slimmer-keep-list.json 失败: $e';
      debugPrint(_lastError);
    }
  }
}
