import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'components/app_components.dart';
import 'services/settings_store.dart';
import 'theme/app_theme.dart';

class CleanBuildsHomePage extends StatefulWidget {
  const CleanBuildsHomePage({super.key});

  @override
  State<CleanBuildsHomePage> createState() => _CleanBuildsHomePageState();
}

class _CleanBuildsHomePageState extends State<CleanBuildsHomePage> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  final List<Map<String, String>> _configs = [];
  final List<String> _logs = [];
  bool _isRunning = false;
  bool _cancelRequested = false;
  double _progress = 0.0;
  int _totalTasks = 0;
  int _completedTasks = 0;

  final Map<String, bool> _artifactOptions = {
    'build': true,
    'target': true,
    'node_modules': true,
    'dist': true,
    '.dart_tool': true,
    '.gradle': true,
    'cmake-build-debug': true,
    'out': true,
    '__pycache__': true,
  };

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    try {
      final data = await SettingsStore.instance.readToolConfig('clean-builds');
      _configs.clear();

      if (data.containsKey('configs') && data['configs'] is List) {
        for (final e in data['configs'] as List) {
          if (e is Map) {
            final name = e['name']?.toString() ?? '';
            final path = e['path']?.toString() ?? '';
            if (path.isNotEmpty) _configs.add({'name': name, 'path': path});
          }
        }
      } else if (data.isNotEmpty) {
        // 兼容直接从旧 JSON 迁移出来的结构（若是数组包装或直接字段）
        for (final entry in data.entries) {
          if (entry.value is Map) {
            final m = entry.value as Map;
            final name = m['name']?.toString() ?? '';
            final path = m['path']?.toString() ?? '';
            if (path.isNotEmpty) _configs.add({'name': name, 'path': path});
          }
        }
      }

      if (data.containsKey('artifactOptions') && data['artifactOptions'] is Map) {
        final opts = data['artifactOptions'] as Map;
        opts.forEach((k, v) {
          if (v is bool && _artifactOptions.containsKey(k.toString())) {
            _artifactOptions[k.toString()] = v;
          }
        });
      }

      if (mounted) setState(() {});
    } catch (e) {
      _log('读取配置失败: $e');
    }
  }

  Future<void> _saveConfigs() async {
    try {
      await SettingsStore.instance.writeToolConfig('clean-builds', {
        'configs': _configs,
        'artifactOptions': _artifactOptions,
      });
    } catch (e) {
      _log('保存配置失败: $e');
    }
  }

  Future<void> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要扫描的项目根目录',
    );
    if (result != null && result.isNotEmpty) {
      _pathController.text = result;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = result.split(Platform.pathSeparator).last;
      }
    }
  }

  void _addRoot() {
    final p = _pathController.text.trim();
    final n = _nameController.text.trim();
    if (p.isEmpty) return;
    if (!_configs.any((c) => c['path'] == p)) {
      setState(() {
        _configs.add({'name': n.isEmpty ? p : n, 'path': p});
        _pathController.clear();
        _nameController.clear();
      });
      _saveConfigs();
    }
  }

  void _removeRoot(Map<String, String> item) {
    setState(() {
      _configs.remove(item);
    });
    _saveConfigs();
  }

  void _log(String s) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $s');
    });
  }

  Future<void> _startClean() async {
    if (_configs.isEmpty) {
      _log('没有配置扫描路径，取消执行。');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.borderRadiusMedium,
          side: const BorderSide(color: AppTheme.borderStrong),
        ),
        title: const Text('确认清理', style: AppTheme.fontTitle),
        content: const Text(
          '将永久删除选中路径中检测到的构建产物目录，是否继续？',
          style: AppTheme.fontBody,
        ),
        actions: [
          AppButton.ghost(
            label: '取消',
            size: AppButtonSize.small,
            onPressed: () => Navigator.pop(c, false),
          ),
          AppButton.danger(
            label: '确认清理',
            size: AppButtonSize.small,
            onPressed: () => Navigator.pop(c, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRunning = true;
      _cancelRequested = false;
      _logs.clear();
      _progress = 0.0;
      _totalTasks = 0;
      _completedTasks = 0;
    });

    final artifactNames = _artifactOptions.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();
    final foundTargets = <Directory>[];

    for (final cfg in _configs) {
      final root = cfg['path'] ?? '';
      final name = cfg['name'] ?? root;
      if (_cancelRequested) break;
      final dir = Directory(root);
      if (!await dir.exists()) {
        _log('路径不存在: $name -> $root');
        continue;
      }
      _log('扫描: $name ($root)');
      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (_cancelRequested) break;
          if (entity is Directory) {
            final dirName = entity.path.split(Platform.pathSeparator).last;
            if (artifactNames.contains(dirName)) {
              foundTargets.add(entity);
            }
          }
        }
      } catch (e) {
        _log('扫描出错: $e');
      }
    }

    setState(() {
      _totalTasks = foundTargets.length;
      _progress = 0.0;
    });

    _log('发现 ${foundTargets.length} 个清理候选目标');

    for (final target in foundTargets) {
      if (_cancelRequested) {
        _log('用户已终止操作');
        break;
      }
      try {
        _log('删除中: ${target.path}');
        await target.delete(recursive: true);
        _log('已删除: ${target.path}');
      } catch (e) {
        _log('删除失败: ${target.path} -> $e');
      }
      _completedTasks++;
      setState(() {
        _progress = _totalTasks == 0 ? 0.0 : _completedTasks / _totalTasks;
      });
      await Future.delayed(const Duration(milliseconds: 100));
    }

    setState(() {
      _isRunning = false;
    });
    _log('清理完成，已处理 $_completedTasks / $_totalTasks 个目标');
  }

  void _stopClean() {
    setState(() {
      _cancelRequested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgContent,
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题区
            Row(
              children: [
                const Icon(Icons.cleaning_services, size: 22, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                const Text('清理构建产物', style: AppTheme.fontHeadline),
                const Spacer(),
                if (_isRunning)
                  const AppBadge(
                    label: '正在清理',
                    color: AppTheme.warningSubtle,
                    textColor: AppTheme.warning,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              '扫描开发项目目录并批量清理 build/、target/、node_modules 等冗余产物',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space16),

            // 添加扫描路径卡片
            AppCard(
              padding: const EdgeInsets.all(AppTheme.space12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: AppTextField(
                          controller: _nameController,
                          hintText: '标签 (可选)',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Expanded(
                        child: AppTextField(
                          controller: _pathController,
                          hintText: '选择或粘贴扫描根目录路径...',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      AppButton.secondary(
                        label: '浏览',
                        icon: Icons.folder_open,
                        size: AppButtonSize.regular,
                        onPressed: _pickDirectory,
                      ),
                      const SizedBox(width: AppTheme.space8),
                      AppButton.primary(
                        label: '添加',
                        icon: Icons.add,
                        size: AppButtonSize.regular,
                        onPressed: _addRoot,
                      ),
                    ],
                  ),
                  if (_configs.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space12),
                    Wrap(
                      spacing: AppTheme.space8,
                      runSpacing: AppTheme.space4,
                      children: _configs.map((r) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.space8,
                            vertical: AppTheme.space4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.bgInput,
                            borderRadius: AppTheme.borderRadiusSmall,
                            border: Border.all(color: AppTheme.borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder, size: 13, color: AppTheme.accentLight),
                              const SizedBox(width: AppTheme.space6),
                              Text(
                                '${r['name']}  (${r['path']})',
                                style: AppTheme.fontCaption.copyWith(
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(width: AppTheme.space4),
                              GestureDetector(
                                onTap: () => _removeRoot(r),
                                child: const Icon(
                                  Icons.close,
                                  size: 13,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 待清理产物类型选择
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space12,
                vertical: AppTheme.space8,
              ),
              child: Row(
                children: [
                  Text(
                    '产物类型：',
                    style: AppTheme.fontCaption.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Expanded(
                    child: Wrap(
                      spacing: AppTheme.space8,
                      runSpacing: AppTheme.space4,
                      children: _artifactOptions.keys.map((k) {
                        final isChecked = _artifactOptions[k] ?? false;
                        return InkWell(
                          onTap: _isRunning
                              ? null
                              : () {
                                  setState(() {
                                    _artifactOptions[k] = !isChecked;
                                  });
                                  _saveConfigs();
                                },
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isChecked ? AppTheme.accentSubtle : AppTheme.bgInput,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isChecked
                                    ? AppTheme.accent.withValues(alpha: 0.5)
                                    : AppTheme.borderSubtle,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                                  size: 13,
                                  color: isChecked ? AppTheme.accent : AppTheme.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  k,
                                  style: AppTheme.fontCaption.copyWith(
                                    color: isChecked ? Colors.white : AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 操作按钮与进度条
            Row(
              children: [
                AppButton.primary(
                  label: '开始扫描清理',
                  icon: Icons.play_arrow,
                  size: AppButtonSize.regular,
                  onPressed: _isRunning ? null : _startClean,
                ),
                const SizedBox(width: AppTheme.space8),
                if (_isRunning)
                  AppButton.danger(
                    label: '停止',
                    icon: Icons.stop,
                    size: AppButtonSize.regular,
                    onPressed: _stopClean,
                  ),
                const SizedBox(width: AppTheme.space16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _isRunning ? _progress : 0.0,
                      minHeight: 8,
                      backgroundColor: AppTheme.bgInput,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.space12),
                Text(
                  '${(_progress * 100).toStringAsFixed(0)}%',
                  style: AppTheme.fontCaption.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space12),

            // 日志终端区
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.space12),
                decoration: BoxDecoration(
                  color: AppTheme.bgInput,
                  borderRadius: AppTheme.borderRadiusMedium,
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal, size: 14, color: AppTheme.textTertiary),
                        const SizedBox(width: AppTheme.space6),
                        Text(
                          '执行日志',
                          style: AppTheme.fontCaption.copyWith(
                            color: AppTheme.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (_logs.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _logs.clear()),
                            child: Text(
                              '清空日志',
                              style: AppTheme.fontCaption.copyWith(color: AppTheme.accentLight),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.space8),
                    const Divider(height: 1, color: AppTheme.borderSubtle),
                    const SizedBox(height: AppTheme.space8),
                    Expanded(
                      child: ListView.builder(
                        controller: _logScrollController,
                        reverse: true,
                        itemCount: _logs.length,
                        itemBuilder: (c, i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              _logs[i],
                              style: AppTheme.fontMono.copyWith(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
