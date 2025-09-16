import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';

class BatchRenameHomePage extends StatefulWidget {
  const BatchRenameHomePage({super.key});

  @override
  State<BatchRenameHomePage> createState() => _BatchRenameHomePageState();
}

class _BatchRenameHomePageState extends State<BatchRenameHomePage> {
  final TextEditingController _folderController = TextEditingController();
  final TextEditingController _patternController = TextEditingController();
  final TextEditingController _replacementController = TextEditingController();

  bool _isProcessing = false;
  List<String> _logMessages = [];
  List<FileSystemEntity> _files = [];
  int _previewCount = 0; // 用于预览计数

  @override
  void initState() {
    super.initState();
    // 设置默认的正则表达式模式和替换格式
    _patternController.text = r'^(.*)-pet\.yml$';
    _replacementController.text = r'$1.yml';
  }

  @override
  void dispose() {
    _folderController.dispose();
    _patternController.dispose();
    _replacementController.dispose();
    super.dispose();
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().split('.').first}: $message',
      );
    });
  }

  /// 应用正则表达式替换，处理捕获组引用
  String _applyRegexReplacement(
    String input,
    RegExp pattern,
    String replacement,
  ) {
    // 如果出现错误，使用手动方式处理捕获组
    final match = pattern.firstMatch(input);
    if (match == null) return input;

    String result = replacement;
    // 替换 $1, $2 等捕获组引用
    for (int i = 1; i <= match.groupCount; i++) {
      final groupValue = match.group(i) ?? '';
      result = result.replaceAll('\$$i', groupValue);
    }
    return result;
  }

  Future<void> _selectFolder() async {
    _addLogMessage('正在尝试打开文件夹选择对话框...');

    try {
      // 使用 file_picker 插件选择文件夹
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folderController.text = selectedDirectory;
        _addLogMessage('已选择文件夹: $selectedDirectory');
      } else {
        _addLogMessage('用户取消了文件夹选择');
      }
    } catch (e) {
      _addLogMessage('选择文件夹时出现错误: $e');
      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件选择器出现错误: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showManualInputDialog() async {
    final TextEditingController manualPathController = TextEditingController();

    // 如果已经有路径，则预填充
    if (_folderController.text.isNotEmpty) {
      manualPathController.text = _folderController.text;
    }

    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择文件夹'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请输入或粘贴文件夹路径:'),
              const SizedBox(height: 8),
              TextField(
                controller: manualPathController,
                decoration: const InputDecoration(
                  hintText: '例如: /Users/username/Documents',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '提示: 您可以在 Finder 中右键点击文件夹，选择"显示简介"来复制路径',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(manualPathController.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      // 验证路径是否存在
      final directory = Directory(result);
      if (await directory.exists()) {
        _folderController.text = result;
        _addLogMessage('已设置文件夹路径: $result');
      } else {
        _addLogMessage('错误: 路径不存在: $result');
        // 显示错误提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('路径不存在，请检查后重试'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (result != null) {
      _addLogMessage('未输入路径');
    }
  }

  Future<void> _scanFiles() async {
    if (_folderController.text.isEmpty) {
      _addLogMessage('请先选择文件夹');
      return;
    }

    setState(() {
      _isProcessing = true;
      _files.clear();
      _logMessages.clear();
    });

    try {
      final directory = Directory(_folderController.text);
      if (!await directory.exists()) {
        _addLogMessage('错误: 文件夹不存在');
        return;
      }

      // 获取文件夹中的所有文件
      await for (var entity in directory.list(recursive: false)) {
        if (entity is File) {
          _files.add(entity);
        }
      }

      _addLogMessage('扫描完成，找到 ${_files.length} 个文件');
    } catch (e) {
      _addLogMessage('扫描文件时出现错误: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _previewRename() async {
    if (_folderController.text.isEmpty) {
      _addLogMessage('请先选择文件夹');
      return;
    }

    if (_patternController.text.isEmpty) {
      _addLogMessage('请输入匹配模式');
      return;
    }

    if (_replacementController.text.isEmpty) {
      _addLogMessage('请输入替换格式');
      return;
    }

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
      _previewCount = 0;
    });

    try {
      final directory = Directory(_folderController.text);
      if (!await directory.exists()) {
        _addLogMessage('错误: 文件夹不存在');
        return;
      }

      _addLogMessage('开始预览重命名...');
      _addLogMessage('匹配模式: ${_patternController.text}');
      _addLogMessage('替换格式: ${_replacementController.text}');

      int count = 0;
      // 获取文件夹中的所有文件
      await for (var entity in directory.list(recursive: false)) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;

          // 使用正则表达式进行匹配和替换
          try {
            final pattern = RegExp(_patternController.text);
            final match = pattern.firstMatch(fileName);
            if (match != null) {
              // 使用 replaceFirst 方法处理捕获组
              String newFileName = fileName;
              // 替换捕获组引用，如 $1, $2 等
              newFileName = _applyRegexReplacement(
                fileName,
                pattern,
                _replacementController.text,
              );
              _addLogMessage('预览: $fileName -> $newFileName');
              count++;
            }
          } catch (e) {
            _addLogMessage('正则表达式错误: $e');
            break;
          }
        }
      }

      setState(() {
        _previewCount = count;
      });

      _addLogMessage('预览完成，将重命名 $_previewCount 个文件');
    } catch (e) {
      _addLogMessage('预览重命名时出现错误: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _executeRename() async {
    if (_folderController.text.isEmpty) {
      _addLogMessage('请先选择文件夹');
      return;
    }

    if (_patternController.text.isEmpty) {
      _addLogMessage('请输入匹配模式');
      return;
    }

    if (_replacementController.text.isEmpty) {
      _addLogMessage('请输入替换格式');
      return;
    }

    // 确认对话框
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认重命名'),
          content: Text('确定要重命名 $_previewCount 个文件吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (shouldProceed != true) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
    });

    int renamedCount = 0;
    try {
      final directory = Directory(_folderController.text);
      if (!await directory.exists()) {
        _addLogMessage('错误: 文件夹不存在');
        return;
      }

      _addLogMessage('开始执行重命名...');

      // 获取文件夹中的所有文件
      await for (var entity in directory.list(recursive: false)) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;

          // 使用正则表达式进行匹配和替换
          try {
            final pattern = RegExp(_patternController.text);
            final match = pattern.firstMatch(fileName);
            if (match != null) {
              // 使用 replaceFirst 方法处理捕获组
              final newFileName = _applyRegexReplacement(
                fileName,
                pattern,
                _replacementController.text,
              );
              final newFile = File('${entity.parent.path}/$newFileName');

              // 执行重命名
              await entity.rename(newFile.path);
              _addLogMessage('✓ $fileName -> $newFileName');
              renamedCount++;
            }
          } catch (e) {
            _addLogMessage('重命名文件时出现错误: $e');
          }
        }
      }

      _addLogMessage('重命名完成，共重命名 $renamedCount 个文件');
    } catch (e) {
      _addLogMessage('执行重命名时出现错误: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('批量重命名工具'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 文件夹选择部分
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '文件夹选择',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _folderController,
                              decoration: const InputDecoration(
                                hintText: '请输入文件夹路径',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _selectFolder,
                            icon: const Icon(Icons.folder),
                            label: const Text('选择'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _scanFiles,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(_isProcessing ? '扫描中...' : '扫描文件'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 重命名规则部分
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '重命名规则',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '使用正则表达式匹配文件名，支持捕获组',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _patternController,
                        decoration: const InputDecoration(
                          labelText: '匹配模式 (正则表达式)',
                          hintText: r'例如: ^(.*)-pet\.yml$',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _replacementController,
                        decoration: const InputDecoration(
                          labelText: '替换格式',
                          hintText: r'例如: \$1.yml',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _previewRename,
                            icon: const Icon(Icons.visibility),
                            label: const Text('预览'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isProcessing || _previewCount == 0
                                ? null
                                : _executeRename,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('执行'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 操作日志部分
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '操作日志',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectionArea(
                        child: Container(
                          height: 200, // 固定高度
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListView.builder(
                              itemCount: _logMessages.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  _logMessages[index],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
