import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'components/app_components.dart';
import 'theme/app_theme.dart';

class BatchRenameHomePage extends StatefulWidget {
  const BatchRenameHomePage({super.key});

  @override
  State<BatchRenameHomePage> createState() => _BatchRenameHomePageState();
}

class _BatchRenameHomePageState extends State<BatchRenameHomePage> {
  final TextEditingController _folderController = TextEditingController();
  final TextEditingController _patternController = TextEditingController();
  final TextEditingController _replacementController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  bool _isProcessing = false;
  final List<String> _logMessages = [];
  final List<FileSystemEntity> _files = [];
  int _previewCount = 0;

  @override
  void initState() {
    super.initState();
    _patternController.text = r'^(.*)-pet\.yml$';
    _replacementController.text = r'$1.yml';
  }

  @override
  void dispose() {
    _folderController.dispose();
    _patternController.dispose();
    _replacementController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLogMessage(String message) {
    if (!mounted) return;
    setState(() {
      _logMessages.insert(
        0,
        '${DateTime.now().toIso8601String().substring(11, 19)} $message',
      );
    });
  }

  String _applyRegexReplacement(
    String input,
    RegExp pattern,
    String replacement,
  ) {
    final match = pattern.firstMatch(input);
    if (match == null) return input;

    String result = replacement;
    for (int i = 1; i <= match.groupCount; i++) {
      final groupValue = match.group(i) ?? '';
      result = result.replaceAll('\$$i', groupValue);
    }
    return result;
  }

  Future<void> _selectFolder() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择要重命名文件的目录',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folderController.text = selectedDirectory;
        _addLogMessage('已选择目录: $selectedDirectory');
      }
    } catch (e) {
      _addLogMessage('选择目录异常: $e');
    }
  }

  Future<void> _scanFiles() async {
    final folder = _folderController.text.trim();
    if (folder.isEmpty) {
      _addLogMessage('请先选择文件夹');
      return;
    }

    setState(() {
      _isProcessing = true;
      _files.clear();
      _logMessages.clear();
    });

    try {
      final directory = Directory(folder);
      if (!await directory.exists()) {
        _addLogMessage('错误: 文件夹不存在');
        return;
      }

      await for (final entity in directory.list(recursive: false)) {
        if (entity is File) {
          _files.add(entity);
        }
      }

      _addLogMessage('扫描完成，发现 ${_files.length} 个文件');
    } catch (e) {
      _addLogMessage('扫描出错: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _previewRename() async {
    final folder = _folderController.text.trim();
    if (folder.isEmpty) {
      _addLogMessage('请先选择文件夹');
      return;
    }

    final patternStr = _patternController.text.trim();
    if (patternStr.isEmpty) {
      _addLogMessage('请输入正则表达式匹配模式');
      return;
    }

    final replacementStr = _replacementController.text;
    if (replacementStr.isEmpty) {
      _addLogMessage('请输入替换格式');
      return;
    }

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
      _previewCount = 0;
    });

    try {
      final directory = Directory(folder);
      if (!await directory.exists()) {
        _addLogMessage('错误: 文件夹不存在');
        return;
      }

      _addLogMessage('开始预览匹配: $patternStr -> $replacementStr');

      int count = 0;
      final pattern = RegExp(patternStr);

      await for (final entity in directory.list(recursive: false)) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (pattern.hasMatch(fileName)) {
            final newFileName = _applyRegexReplacement(
              fileName,
              pattern,
              replacementStr,
            );
            _addLogMessage('预览: $fileName → $newFileName');
            count++;
          }
        }
      }

      setState(() {
        _previewCount = count;
      });

      _addLogMessage('预览完成，匹配到 $_previewCount 个文件将进行重命名');
    } catch (e) {
      _addLogMessage('正则解析或预览异常: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _executeRename() async {
    final folder = _folderController.text.trim();
    if (folder.isEmpty || _patternController.text.isEmpty || _replacementController.text.isEmpty) {
      _addLogMessage('请补全必要路径与规则');
      return;
    }

    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.borderRadiusMedium,
            side: const BorderSide(color: AppTheme.borderStrong),
          ),
          title: const Text('确认重命名', style: AppTheme.fontTitle),
          content: Text(
            '确定要按规则重命名 $_previewCount 个文件吗？\n该操作将直接修改磁盘文件名。',
            style: AppTheme.fontBody,
          ),
          actions: [
            AppButton.ghost(
              label: '取消',
              size: AppButtonSize.small,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppButton.danger(
              label: '确认执行',
              size: AppButtonSize.small,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (shouldProceed != true) return;

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
    });

    int renamedCount = 0;
    try {
      final directory = Directory(folder);
      if (!await directory.exists()) {
        _addLogMessage('错误: 文件夹不存在');
        return;
      }

      _addLogMessage('开始执行重命名...');
      final pattern = RegExp(_patternController.text.trim());

      await for (final entity in directory.list(recursive: false)) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (pattern.hasMatch(fileName)) {
            final newFileName = _applyRegexReplacement(
              fileName,
              pattern,
              _replacementController.text,
            );
            final newFile = File('${entity.parent.path}/$newFileName');
            await entity.rename(newFile.path);
            _addLogMessage('✓ $fileName → $newFileName');
            renamedCount++;
          }
        }
      }

      _addLogMessage('执行完毕，成功重命名 $renamedCount 个文件');
      setState(() {
        _previewCount = 0;
      });
    } catch (e) {
      _addLogMessage('执行重命名发生错误: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
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
            // 标题
            Row(
              children: [
                const Icon(Icons.text_format, size: 22, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                const Text('批量重命名', style: AppTheme.fontHeadline),
                const Spacer(),
                if (_previewCount > 0)
                  AppBadge(
                    label: '匹配到 $_previewCount 个文件',
                    color: AppTheme.accentSubtle,
                    textColor: AppTheme.accentLight,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              '使用正则表达式对指定目录中的文件进行批量匹配与捕获组替换',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space16),

            // 路径选择卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _folderController,
                          label: '文件夹路径',
                          hintText: '选择或粘贴包含待重命名文件的目录...',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '浏览',
                          icon: Icons.folder_open,
                          size: AppButtonSize.regular,
                          onPressed: _isProcessing ? null : _selectFolder,
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '扫描文件',
                          icon: Icons.search,
                          size: AppButtonSize.regular,
                          onPressed: _isProcessing ? null : _scanFiles,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space16),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _patternController,
                          label: '匹配模式 (正则表达式)',
                          hintText: r'如 ^(.*)-pet\.yml$',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space12),
                      Expanded(
                        child: AppTextField(
                          controller: _replacementController,
                          label: r'替换格式 (支持 $1, $2 捕获组)',
                          hintText: r'如 $1.yml',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space16),
                  Row(
                    children: [
                      AppButton.secondary(
                        label: '预览变更',
                        icon: Icons.visibility_outlined,
                        size: AppButtonSize.regular,
                        isLoading: _isProcessing && _previewCount == 0,
                        onPressed: _isProcessing ? null : _previewRename,
                      ),
                      const SizedBox(width: AppTheme.space8),
                      AppButton.primary(
                        label: _previewCount > 0 ? '执行重命名 ($_previewCount)' : '执行重命名',
                        icon: Icons.play_arrow,
                        size: AppButtonSize.regular,
                        isLoading: _isProcessing && _previewCount > 0,
                        onPressed: (_isProcessing || _previewCount == 0) ? null : _executeRename,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 日志预览区
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
                          '处理与预览日志',
                          style: AppTheme.fontCaption.copyWith(
                            color: AppTheme.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (_logMessages.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() {
                              _logMessages.clear();
                              _previewCount = 0;
                            }),
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
                      child: _logMessages.isEmpty
                          ? Center(
                              child: Text(
                                '暂无日志记录，可点击"预览变更"查看重命名计划',
                                style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                              ),
                            )
                          : ListView.builder(
                              controller: _logScrollController,
                              itemCount: _logMessages.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    _logMessages[index],
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
