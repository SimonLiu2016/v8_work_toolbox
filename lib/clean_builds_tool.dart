import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class CleanBuildsHomePage extends StatefulWidget {
  const CleanBuildsHomePage({super.key});

  @override
  State<CleanBuildsHomePage> createState() => _CleanBuildsHomePageState();
}

class _CleanBuildsHomePageState extends State<CleanBuildsHomePage> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  // 配置列表: {"name":..., "path":...}
  final List<Map<String, String>> _configs = [];
  final List<String> _logs = [];
  bool _isRunning = false;
  bool _cancelRequested = false;
  double _progress = 0.0;
  int _totalTasks = 0;
  int _completedTasks = 0;

  // 默认待清理的常见构建产物目录/文件
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
    'build/': true,
  };

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  File get _configFile {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return File('$home/.v8_cleaner_config.json');
  }

  Future<void> _loadConfigs() async {
    try {
      final cfg = _configFile;
      if (await cfg.exists()) {
        final s = await cfg.readAsString();
        final list = jsonDecode(s) as List<dynamic>;
        _configs.clear();
        for (final e in list) {
          if (e is Map) {
            final name = e['name']?.toString() ?? '';
            final path = e['path']?.toString() ?? '';
            if (path.isNotEmpty) _configs.add({'name': name, 'path': path});
          }
        }
        setState(() {});
      }
    } catch (e) {
      _log('读取配置失败: $e');
    }
  }

  Future<void> _saveConfigs() async {
    try {
      final cfg = _configFile;
      final list = _configs
          .map((e) => {'name': e['name'], 'path': e['path']})
          .toList();
      await cfg.writeAsString(jsonEncode(list));
    } catch (e) {
      _log('保存配置失败: $e');
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
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String()} $s');
    });
  }

  Future<void> _startClean() async {
    if (_configs.isEmpty) {
      _log('没有配置路径，取消执行。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认清理'),
        content: const Text('将删除检测到的构建产物目录，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('继续'),
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
        .toList();
    final foundTargets = <Directory>[];

    // 扫描每个根路径，收集待删除的目录
    for (final cfg in _configs) {
      final root = cfg['path'] ?? '';
      final name = cfg['name'] ?? root;
      if (_cancelRequested) break;
      final dir = Directory(root);
      if (!await dir.exists()) {
        _log('路径不存在: $name -> $root');
        continue;
      }
      _log('扫描: $name -> $root');
      // 遍历两层目录来发现项目（避免太深的全盘遍历）
      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (_cancelRequested) break;
          if (entity is Directory) {
            final name = entity.path.split(Platform.pathSeparator).last;
            if (artifactNames.contains(name)) {
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

    _log('发现 ${foundTargets.length} 个候选清理目标');

    // 顺序删除
    for (final target in foundTargets) {
      if (_cancelRequested) {
        _log('用户已请求取消');
        break;
      }
      try {
        _log('删除: ${target.path}');
        await target.delete(recursive: true);
        _log('已删除: ${target.path}');
      } catch (e) {
        _log('删除失败: ${target.path} -> $e');
      }
      _completedTasks++;
      setState(() {
        _progress = _totalTasks == 0 ? 0.0 : _completedTasks / _totalTasks;
      });
      // 给UI一点时间更新，且响应取消
      await Future.delayed(const Duration(milliseconds: 200));
    }

    setState(() {
      _isRunning = false;
    });
    _log('清理完成，已处理 $_completedTasks 个目标');
  }

  void _stopClean() {
    setState(() {
      _cancelRequested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('清理构建产物工具')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '配置名称',
                      hintText: 'Projects (可选)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      labelText: '添加要扫描的路径',
                      hintText: '/Users/simon/projects',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _addRoot, child: const Text('添加')),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _configs
                  .map(
                    (r) => Chip(
                      label: Text('${r['name']}  —  ${r['path']}'),
                      onDeleted: () => _removeRoot(r),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('待清理的产物类型（可选）'),
              children: _artifactOptions.keys.map((k) {
                return CheckboxListTile(
                  value: _artifactOptions[k],
                  title: Text(k),
                  onChanged: (v) {
                    setState(() {
                      _artifactOptions[k] = v ?? false;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _startClean,
                  child: const Text('开始'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isRunning ? _stopClean : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('停止'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: _isRunning ? _progress : null,
                  ),
                ),
                const SizedBox(width: 12),
                Text('${(_progress * 100).toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListView.builder(
                  reverse: true,
                  itemCount: _logs.length,
                  itemBuilder: (c, i) {
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _logs[i],
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
