import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import 'components/app_components.dart';
import 'theme/app_theme.dart';

class FolderCompareHomePage extends StatefulWidget {
  const FolderCompareHomePage({super.key});

  @override
  State<FolderCompareHomePage> createState() => _FolderCompareHomePageState();
}

class _FolderCompareHomePageState extends State<FolderCompareHomePage> {
  final TextEditingController _folder1Controller = TextEditingController();
  final TextEditingController _folder2Controller = TextEditingController();
  final TextEditingController _keyExpressionController = TextEditingController();
  final TextEditingController _valueExpressionController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  bool _isProcessing = false;
  final List<String> _logMessages = [];
  final List<ComparisonResult> _comparisonResults = [];
  bool _filterDuplicates = true;

  final List<String> _fileTypes = ['yaml', 'json', 'properties'];
  String _selectedFileType = 'yaml';

  @override
  void initState() {
    super.initState();
    _keyExpressionController.text = 'Name';
    _valueExpressionController.text = 'Envs[0].value[0-14],ReplicaCount';
  }

  @override
  void dispose() {
    _folder1Controller.dispose();
    _folder2Controller.dispose();
    _keyExpressionController.dispose();
    _valueExpressionController.dispose();
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

  Future<void> _selectFolder1() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择第一个文件夹',
      );
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folder1Controller.text = selectedDirectory;
        _addLogMessage('已选择文件夹 1: $selectedDirectory');
      }
    } catch (e) {
      _addLogMessage('选择文件夹 1 异常: $e');
    }
  }

  Future<void> _selectFolder2() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择第二个文件夹',
      );
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folder2Controller.text = selectedDirectory;
        _addLogMessage('已选择文件夹 2: $selectedDirectory');
      }
    } catch (e) {
      _addLogMessage('选择文件夹 2 异常: $e');
    }
  }

  Map<String, dynamic> _extractValuesFromYaml(
    File file,
    String keyExpr,
    String valueExpr,
  ) {
    try {
      final content = file.readAsStringSync();
      final yaml = loadYaml(content);
      final result = <String, dynamic>{};

      if (keyExpr.isNotEmpty) {
        result['key'] = _getValueByPath(yaml, keyExpr);
      }

      if (valueExpr.isNotEmpty) {
        final valuePaths = valueExpr.split(',');
        for (var i = 0; i < valuePaths.length; i++) {
          final p = valuePaths[i].trim();
          result['value_$i'] = _getValueByPath(yaml, p);
        }
      }

      return result;
    } catch (e) {
      _addLogMessage('解析 YAML 失败 ${file.path}: $e');
      return {};
    }
  }

  dynamic _getValueByPath(dynamic yaml, String p) {
    try {
      if (p.contains('[')) {
        final parts = p.split('.');
        dynamic current = yaml;

        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          if (part.contains('[')) {
            if (part.contains('-') && part.contains(']')) {
              final match = RegExp(r'(.+)\[(\d+)-(\d+)\]').firstMatch(part);
              if (match != null) {
                final key = match.group(1)!;
                final start = int.parse(match.group(2)!);
                final end = int.parse(match.group(3)!);
                final value = current[key].toString();
                if (start < value.length && end < value.length && start <= end) {
                  current = value.substring(start, end + 1);
                } else {
                  current = value;
                }
                continue;
              }
            }

            final match = RegExp(r'(.+)\[(\d+)\]').firstMatch(part);
            if (match != null) {
              final key = match.group(1)!;
              final index = int.parse(match.group(2)!);
              current = current[key][index];
            }
          } else {
            current = current[part];
          }
        }
        return current;
      } else {
        final parts = p.split('.');
        dynamic current = yaml;
        for (var part in parts) {
          current = current[part];
        }
        return current;
      }
    } catch (e) {
      return null;
    }
  }

  bool _areValuesEqual(
    Map<String, dynamic> values1,
    Map<String, dynamic> values2,
  ) {
    for (var key in values1.keys) {
      if (key.startsWith('value_')) {
        final v1 = values1[key];
        final v2 = values2[key];
        if ((v1 == null) != (v2 == null)) return false;
        if (v1 != null && v2 != null && v1.toString() != v2.toString()) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _compareFolders() async {
    final path1 = _folder1Controller.text.trim();
    final path2 = _folder2Controller.text.trim();

    if (path1.isEmpty || path2.isEmpty) {
      _addLogMessage('请先选择需要对比的两个文件夹');
      return;
    }

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
      _comparisonResults.clear();
    });

    try {
      final folder1 = Directory(path1);
      final folder2 = Directory(path2);

      if (!await folder1.exists() || !await folder2.exists()) {
        _addLogMessage('指定的文件夹不存在，请检查路径');
        return;
      }

      _addLogMessage('开始对比: $path1 <=> $path2');

      final files1 = <String, File>{};
      final files2 = <String, File>{};

      await for (final entity in folder1.list()) {
        if (entity is File && entity.path.endsWith('.$_selectedFileType')) {
          files1[entity.uri.pathSegments.last] = entity;
        }
      }

      await for (final entity in folder2.list()) {
        if (entity is File && entity.path.endsWith('.$_selectedFileType')) {
          files2[entity.uri.pathSegments.last] = entity;
        }
      }

      _addLogMessage('目录1含 ${files1.length} 个 $_selectedFileType 文件，目录2含 ${files2.length} 个');

      int comparedCount = 0;
      int filteredCount = 0;

      for (final entry in files1.entries) {
        final fileName = entry.key;
        if (files2.containsKey(fileName)) {
          final values1 = _extractValuesFromYaml(
            entry.value,
            _keyExpressionController.text,
            _valueExpressionController.text,
          );
          final values2 = _extractValuesFromYaml(
            files2[fileName]!,
            _keyExpressionController.text,
            _valueExpressionController.text,
          );

          if (_filterDuplicates && _areValuesEqual(values1, values2)) {
            filteredCount++;
          } else if (!_areValuesEqual(values1, values2)) {
            _comparisonResults.add(
              ComparisonResult(
                fileName: fileName,
                key: values1['key']?.toString() ?? fileName,
                values1: values1,
                values2: values2,
              ),
            );
            _addLogMessage('发现差异: $fileName');
          } else {
            _comparisonResults.add(
              ComparisonResult(
                fileName: fileName,
                key: values1['key']?.toString() ?? fileName,
                values1: values1,
                values2: values2,
              ),
            );
          }
          comparedCount++;
        }
      }

      _addLogMessage(
        '对比完成：共匹配 $comparedCount 个同名文件，过滤相同记录 $filteredCount 项，发现 ${_comparisonResults.length} 项记录',
      );
    } catch (e) {
      _addLogMessage('对比异常: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportToCsv() async {
    if (_comparisonResults.isEmpty) {
      _addLogMessage('暂无对比结果可导出');
      return;
    }

    try {
      final csvData = <List<String>>[];
      final headers = ['服务名', '文件名'];
      final valueExprs = _valueExpressionController.text.split(',');
      for (var i = 0; i < valueExprs.length; i++) {
        headers.add('文件夹1_${_getDisplayName(valueExprs[i])}');
        headers.add('文件夹2_${_getDisplayName(valueExprs[i])}');
      }
      csvData.add(headers);

      for (final result in _comparisonResults) {
        final row = <String>[result.key, result.fileName];
        for (var i = 0; i < valueExprs.length; i++) {
          row.add(result.values1['value_$i']?.toString() ?? '');
          row.add(result.values2['value_$i']?.toString() ?? '');
        }
        csvData.add(row);
      }

      final csvString = const ListToCsvConverter().convert(csvData);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '选择 CSV 导出文件保存位置',
        fileName: '对比结果.csv',
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );

      if (savePath != null) {
        await File(savePath).writeAsString(csvString);
        _addLogMessage('✓ CSV 已成功导出至: $savePath');
      }
    } catch (e) {
      _addLogMessage('导出 CSV 出错: $e');
    }
  }

  String _getDisplayName(String expression) {
    if (expression.contains('JAVA_MEM_OPTIONS')) return 'JVM参数';
    if (expression.contains('ReplicaCount')) return '副本数';
    if (expression.contains('Name')) return '服务名';
    return expression.trim();
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
                const Icon(Icons.compare_arrows, size: 22, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                const Text('文件夹对比', style: AppTheme.fontHeadline),
                const Spacer(),
                if (_comparisonResults.isNotEmpty)
                  AppBadge(
                    label: '${_comparisonResults.length} 项结果',
                    color: AppTheme.accentSubtle,
                    textColor: AppTheme.accentLight,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              '按路径表达式对比两个目录中同名配置文件的字段值并支持导出 CSV',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space16),

            // 路径与参数选择卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _folder1Controller,
                          label: '目录 1 (基准目录)',
                          hintText: '选择第一个对比目录...',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '选择',
                          icon: Icons.folder_open,
                          size: AppButtonSize.regular,
                          onPressed: _isProcessing ? null : _selectFolder1,
                        ),
                      ),
                      const SizedBox(width: AppTheme.space16),
                      Expanded(
                        child: AppTextField(
                          controller: _folder2Controller,
                          label: '目录 2 (目标目录)',
                          hintText: '选择第二个对比目录...',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '选择',
                          icon: Icons.folder_open,
                          size: AppButtonSize.regular,
                          onPressed: _isProcessing ? null : _selectFolder2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space12),

                  // 表达式配置
                  Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: AppTextField(
                          controller: _keyExpressionController,
                          label: 'Key 表达式 (服务标识)',
                          hintText: '如 Name',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space12),
                      Expanded(
                        child: AppTextField(
                          controller: _valueExpressionController,
                          label: 'Value 表达式 (逗号分隔多个字段)',
                          hintText: '如 Envs[0].value[0-14],ReplicaCount',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space12),

                  // 选项行
                  Row(
                    children: [
                      Text(
                        '文件类型: ',
                        style: AppTheme.fontCaption.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppTheme.space6),
                      ..._fileTypes.map((type) {
                        final isSel = _selectedFileType == type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: _isProcessing ? null : () => setState(() => _selectedFileType = type),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSel ? AppTheme.accentSubtle : AppTheme.bgInput,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSel ? AppTheme.accent : AppTheme.borderSubtle,
                                ),
                              ),
                              child: Text(
                                type.toUpperCase(),
                                style: AppTheme.fontCaption.copyWith(
                                  color: isSel ? Colors.white : AppTheme.textSecondary,
                                  fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: AppTheme.space16),
                      InkWell(
                        onTap: _isProcessing
                            ? null
                            : () => setState(() => _filterDuplicates = !_filterDuplicates),
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          children: [
                            Icon(
                              _filterDuplicates ? Icons.check_box : Icons.check_box_outline_blank,
                              size: 15,
                              color: _filterDuplicates ? AppTheme.accent : AppTheme.textTertiary,
                            ),
                            const SizedBox(width: 6),
                            Text('过滤相同记录', style: AppTheme.fontCaption.copyWith(color: AppTheme.textPrimary)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      AppButton.primary(
                        label: '开始对比',
                        icon: Icons.compare_arrows,
                        size: AppButtonSize.regular,
                        isLoading: _isProcessing,
                        onPressed: _isProcessing ? null : _compareFolders,
                      ),
                      const SizedBox(width: AppTheme.space8),
                      AppButton.secondary(
                        label: '导出 CSV',
                        icon: Icons.download,
                        size: AppButtonSize.regular,
                        onPressed: (_isProcessing || _comparisonResults.isEmpty) ? null : _exportToCsv,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 结果与日志分栏
            Expanded(
              child: Row(
                children: [
                  // 左栏：差异列表
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: AppTheme.borderRadiusMedium,
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.space12,
                              AppTheme.space10,
                              AppTheme.space12,
                              AppTheme.space6,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '差异结果 (${_comparisonResults.length})',
                                  style: AppTheme.fontTitle.copyWith(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: AppTheme.borderSubtle),
                          Expanded(
                            child: _comparisonResults.isEmpty
                                ? Center(
                                    child: Text(
                                      '暂无对比差异结果',
                                      style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.all(AppTheme.space8),
                                    itemCount: _comparisonResults.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1, color: AppTheme.borderSubtle),
                                    itemBuilder: (context, index) {
                                      final item = _comparisonResults[index];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppTheme.space8,
                                          vertical: AppTheme.space6,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  item.fileName,
                                                  style: AppTheme.fontBody.copyWith(fontWeight: FontWeight.w600),
                                                ),
                                                const SizedBox(width: AppTheme.space8),
                                                AppBadge(label: item.key, color: AppTheme.bgInput),
                                              ],
                                            ),
                                            const SizedBox(height: AppTheme.space4),
                                            ..._buildDifferenceWidgets(item),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),

                  // 右栏：执行日志
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgInput,
                        borderRadius: AppTheme.borderRadiusMedium,
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.space12,
                              AppTheme.space10,
                              AppTheme.space12,
                              AppTheme.space6,
                            ),
                            child: Row(
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
                                if (_logMessages.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => setState(() => _logMessages.clear()),
                                    child: Text(
                                      '清空',
                                      style: AppTheme.fontCaption.copyWith(color: AppTheme.accentLight),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: AppTheme.borderSubtle),
                          Expanded(
                            child: ListView.builder(
                              controller: _logScrollController,
                              itemCount: _logMessages.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  child: Text(
                                    _logMessages[index],
                                    style: AppTheme.fontMono.copyWith(fontSize: 10.5),
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
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDifferenceWidgets(ComparisonResult result) {
    final widgets = <Widget>[];
    final valueExprs = _valueExpressionController.text.split(',');

    for (var i = 0; i < valueExprs.length; i++) {
      final expr = valueExprs[i].trim();
      final v1 = result.values1['value_$i']?.toString() ?? '(空)';
      final v2 = result.values2['value_$i']?.toString() ?? '(空)';

      if (v1 != v2) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Text(
                  '${_getDisplayName(expr)}: ',
                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                ),
                Text(
                  v1,
                  style: AppTheme.fontMono.copyWith(color: AppTheme.error, fontSize: 11),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward, size: 10, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(
                  v2,
                  style: AppTheme.fontMono.copyWith(color: AppTheme.success, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class ComparisonResult {
  final String fileName;
  final String key;
  final Map<String, dynamic> values1;
  final Map<String, dynamic> values2;

  ComparisonResult({
    required this.fileName,
    required this.key,
    required this.values1,
    required this.values2,
  });
}
