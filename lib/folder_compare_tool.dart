import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:yaml/yaml.dart';
import 'package:csv/csv.dart';

class FolderCompareHomePage extends StatefulWidget {
  const FolderCompareHomePage({super.key});

  @override
  State<FolderCompareHomePage> createState() => _FolderCompareHomePageState();
}

class _FolderCompareHomePageState extends State<FolderCompareHomePage> {
  final TextEditingController _folder1Controller = TextEditingController();
  final TextEditingController _folder2Controller = TextEditingController();
  final TextEditingController _keyExpressionController =
      TextEditingController();
  final TextEditingController _valueExpressionController =
      TextEditingController();

  bool _isProcessing = false;
  List<String> _logMessages = [];
  List<ComparisonResult> _comparisonResults = [];
  bool _filterDuplicates = true; // 添加过滤重复记录的复选框状态

  // 文件类型选项
  final List<String> _fileTypes = ['yaml', 'json', 'properties'];
  String _selectedFileType = 'yaml';

  @override
  void initState() {
    super.initState();
    // 设置默认的表达式
    _keyExpressionController.text = 'Name';
    _valueExpressionController.text = 'Envs[0].value[0-14],ReplicaCount';
  }

  @override
  void dispose() {
    _folder1Controller.dispose();
    _folder2Controller.dispose();
    _keyExpressionController.dispose();
    _valueExpressionController.dispose();
    super.dispose();
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().split('.').first}: $message',
      );
    });
  }

  Future<void> _selectFolder1() async {
    _addLogMessage('正在选择第一个文件夹...');
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folder1Controller.text = selectedDirectory;
        _addLogMessage('已选择第一个文件夹: $selectedDirectory');
      } else {
        _addLogMessage('用户取消了文件夹选择');
      }
    } catch (e) {
      _addLogMessage('选择文件夹时出现错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件选择器出现错误: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _selectFolder2() async {
    _addLogMessage('正在选择第二个文件夹...');
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        _folder2Controller.text = selectedDirectory;
        _addLogMessage('已选择第二个文件夹: $selectedDirectory');
      } else {
        _addLogMessage('用户取消了文件夹选择');
      }
    } catch (e) {
      _addLogMessage('选择文件夹时出现错误: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件选择器出现错误: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 解析YAML文件并提取指定字段
  Map<String, dynamic> _extractValuesFromYaml(
    File file,
    String keyExpr,
    String valueExpr,
  ) {
    try {
      final content = file.readAsStringSync();
      final yaml = loadYaml(content);

      final result = <String, dynamic>{};

      // 提取服务名（key）
      if (keyExpr.isNotEmpty) {
        result['key'] = _getValueByPath(yaml, keyExpr);
      }

      // 提取要对比的值
      if (valueExpr.isNotEmpty) {
        final valuePaths = valueExpr.split(',');
        for (var i = 0; i < valuePaths.length; i++) {
          final path = valuePaths[i].trim();
          result['value_$i'] = _getValueByPath(yaml, path);
        }
      }

      return result;
    } catch (e) {
      _addLogMessage('解析YAML文件时出错 ${file.path}: $e');
      return {};
    }
  }

  /// 根据路径获取YAML中的值
  dynamic _getValueByPath(dynamic yaml, String path) {
    try {
      // 处理数组索引和截取范围，如 Envs[0].value 或 Envs[0].value[0-14]
      if (path.contains('[')) {
        final parts = path.split('.');
        dynamic current = yaml;

        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          if (part.contains('[')) {
            // 检查是否是截取范围，如 value[0-14]
            if (part.contains('-') && part.contains(']')) {
              final match = RegExp(r'(.+)\[(\d+)-(\d+)\]').firstMatch(part);
              if (match != null) {
                final key = match.group(1)!;
                final start = int.parse(match.group(2)!);
                final end = int.parse(match.group(3)!);
                final value = current[key].toString();
                // 截取指定范围的字符串
                if (start < value.length &&
                    end < value.length &&
                    start <= end) {
                  current = value.substring(start, end + 1);
                } else {
                  current = value; // 如果范围不合法，返回完整字符串
                }
                continue;
              }
            }

            // 处理数组访问，如 Envs[0]
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
        // 简单路径访问
        final parts = path.split('.');
        dynamic current = yaml;
        for (var part in parts) {
          current = current[part];
        }
        return current;
      }
    } catch (e) {
      _addLogMessage('获取路径值时出错 $path: $e');
      return null;
    }
  }

  /// 比较两个值映射是否相等
  bool _areValuesEqual(
    Map<String, dynamic> values1,
    Map<String, dynamic> values2,
  ) {
    // 比较所有value_开头的字段
    for (var key in values1.keys) {
      if (key.startsWith('value_')) {
        final v1 = values1[key];
        final v2 = values2[key];

        // 如果任一值为null而另一个不为null，则不相等
        if ((v1 == null) != (v2 == null)) {
          return false;
        }

        // 如果都不为null但值不相等，则不相等
        if (v1 != null && v2 != null && v1.toString() != v2.toString()) {
          return false;
        }
      }
    }
    return true;
  }

  /// 对比两个文件夹中的同名文件
  Future<void> _compareFolders() async {
    if (_folder1Controller.text.isEmpty) {
      _addLogMessage('请选择第一个文件夹');
      return;
    }

    if (_folder2Controller.text.isEmpty) {
      _addLogMessage('请选择第二个文件夹');
      return;
    }

    setState(() {
      _isProcessing = true;
      _logMessages.clear();
      _comparisonResults.clear();
    });

    try {
      final folder1 = Directory(_folder1Controller.text);
      final folder2 = Directory(_folder2Controller.text);

      if (!await folder1.exists()) {
        _addLogMessage('错误: 第一个文件夹不存在');
        return;
      }

      if (!await folder2.exists()) {
        _addLogMessage('错误: 第二个文件夹不存在');
        return;
      }

      _addLogMessage('开始对比文件夹...');
      _addLogMessage('文件夹1: ${folder1.path}');
      _addLogMessage('文件夹2: ${folder2.path}');
      _addLogMessage('文件类型: $_selectedFileType');
      _addLogMessage('过滤重复记录: $_filterDuplicates');

      // 获取两个文件夹中的文件列表
      final files1 = <String, File>{};
      final files2 = <String, File>{};

      await for (var entity in folder1.list()) {
        if (entity is File && entity.path.endsWith('.$_selectedFileType')) {
          final fileName = entity.uri.pathSegments.last;
          files1[fileName] = entity;
        }
      }

      await for (var entity in folder2.list()) {
        if (entity is File && entity.path.endsWith('.$_selectedFileType')) {
          final fileName = entity.uri.pathSegments.last;
          files2[fileName] = entity;
        }
      }

      _addLogMessage('文件夹1中有 ${files1.length} 个 $_selectedFileType 文件');
      _addLogMessage('文件夹2中有 ${files2.length} 个 $_selectedFileType 文件');

      // 对比同名文件
      int comparedCount = 0;
      int filteredCount = 0;
      for (var entry in files1.entries) {
        final fileName = entry.key;
        if (files2.containsKey(fileName)) {
          _addLogMessage('正在对比文件: $fileName');

          // 解析两个文件的内容
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

          // 检查是否过滤重复记录
          if (_filterDuplicates && _areValuesEqual(values1, values2)) {
            // 如果勾选了过滤重复记录且值相等，则跳过
            filteredCount++;
            _addLogMessage('跳过重复记录: $fileName');
          } else if (!_areValuesEqual(values1, values2)) {
            // 如果值不相等，则添加到结果中
            final result = ComparisonResult(
              fileName: fileName,
              key: values1['key']?.toString() ?? fileName,
              values1: values1,
              values2: values2,
            );
            _comparisonResults.add(result);
            _addLogMessage('发现差异: $fileName');
          } else {
            // 如果未勾选过滤重复记录且值相等，也添加到结果中（用于显示相同记录）
            final result = ComparisonResult(
              fileName: fileName,
              key: values1['key']?.toString() ?? fileName,
              values1: values1,
              values2: values2,
            );
            _comparisonResults.add(result);
            _addLogMessage('记录相同: $fileName');
          }

          comparedCount++;
        }
      }

      _addLogMessage(
        '对比完成，共对比 $comparedCount 个文件，过滤掉 $filteredCount 个重复记录，发现 ${_comparisonResults.length} 个结果',
      );

      // 显示结果
      if (_comparisonResults.isNotEmpty) {
        _addLogMessage('点击"导出结果"按钮将结果保存为CSV文件');
      } else {
        _addLogMessage('未发现任何需要导出的记录');
      }
    } catch (e) {
      _addLogMessage('对比文件夹时出现错误: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// 导出结果为CSV文件
  Future<void> _exportToCsv() async {
    if (_comparisonResults.isEmpty) {
      _addLogMessage('没有差异结果可导出');
      return;
    }

    try {
      _addLogMessage('正在导出结果为CSV文件...');

      // 准备CSV数据
      final csvData = <List<String>>[];

      // 添加表头
      final headers = ['服务名', '文件名'];
      // 根据表达式添加列标题
      final valueExprs = _valueExpressionController.text.split(',');
      for (var i = 0; i < valueExprs.length; i++) {
        headers.add('第一个文件夹的${_getDisplayName(valueExprs[i])}');
        headers.add('第二个文件夹的${_getDisplayName(valueExprs[i])}');
      }
      csvData.add(headers);

      // 添加数据行
      for (var result in _comparisonResults) {
        final row = <String>[];
        row.add(result.key);
        row.add(result.fileName);

        // 添加值对比
        for (var i = 0; i < valueExprs.length; i++) {
          final v1 = result.values1['value_$i']?.toString() ?? '';
          final v2 = result.values2['value_$i']?.toString() ?? '';
          row.add(v1);
          row.add(v2);
        }

        csvData.add(row);
      }

      // 转换为CSV字符串
      final csvString = const ListToCsvConverter().convert(csvData);

      // 选择保存位置
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '请选择CSV文件保存位置',
        fileName: '对比结果.csv',
        allowedExtensions: ['csv'],
        type: FileType.custom,
      );

      if (savePath != null) {
        final file = File(savePath);
        await file.writeAsString(csvString);
        _addLogMessage('CSV文件已保存到: $savePath');
      } else {
        _addLogMessage('用户取消了文件保存');
      }
    } catch (e) {
      _addLogMessage('导出CSV文件时出现错误: $e');
    }
  }

  /// 获取表达式的显示名称
  String _getDisplayName(String expression) {
    // 简单映射一些常见的表达式到中文名称
    if (expression.contains('JAVA_MEM_OPTIONS')) {
      return 'JVM参数';
    } else if (expression.contains('ReplicaCount')) {
      return '副本数';
    } else if (expression.contains('Name')) {
      return '服务名';
    }
    return expression;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件夹对比工具'),
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
                      const Text(
                        '请选择要对比的两个文件夹',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _folder1Controller,
                              decoration: const InputDecoration(
                                labelText: '第一个文件夹',
                                hintText: '请输入文件夹路径',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _selectFolder1,
                            icon: const Icon(Icons.folder),
                            label: const Text('选择'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _folder2Controller,
                              decoration: const InputDecoration(
                                labelText: '第二个文件夹',
                                hintText: '请输入文件夹路径',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _selectFolder2,
                            icon: const Icon(Icons.folder),
                            label: const Text('选择'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 对比配置部分
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '对比配置',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '配置对比参数',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      // 文件类型选择
                      Row(
                        children: [
                          const Text('文件类型:'),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _selectedFileType,
                            items: _fileTypes.map((String type) {
                              return DropdownMenuItem<String>(
                                value: type,
                                child: Text(type.toUpperCase()),
                              );
                            }).toList(),
                            onChanged: _isProcessing
                                ? null
                                : (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _selectedFileType = newValue;
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(width: 16),
                          // 添加过滤重复记录的复选框
                          Row(
                            children: [
                              Checkbox(
                                value: _filterDuplicates,
                                onChanged: _isProcessing
                                    ? null
                                    : (bool? value) {
                                        setState(() {
                                          _filterDuplicates = value ?? false;
                                        });
                                      },
                              ),
                              const Text('过滤重复记录'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Key表达式
                      TextField(
                        controller: _keyExpressionController,
                        decoration: const InputDecoration(
                          labelText: 'Key表达式',
                          hintText: '例如: Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Value表达式
                      TextField(
                        controller: _valueExpressionController,
                        decoration: const InputDecoration(
                          labelText: 'Value表达式',
                          hintText: '例如: Envs[0].value,ReplicaCount',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _compareFolders,
                            icon: _isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.compare),
                            label: Text(_isProcessing ? '对比中...' : '开始对比'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed:
                                _isProcessing || _comparisonResults.isEmpty
                                ? null
                                : _exportToCsv,
                            icon: const Icon(Icons.download),
                            label: const Text('导出结果'),
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
              const SizedBox(height: 16),
              // 对比结果部分
              if (_comparisonResults.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '对比结果',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('发现 ${_comparisonResults.length} 个差异'),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            itemCount: _comparisonResults.length,
                            itemBuilder: (context, index) {
                              final result = _comparisonResults[index];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '文件: ${result.fileName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text('服务名: ${result.key}'),
                                      // 显示具体差异
                                      ..._buildDifferenceWidgets(result),
                                    ],
                                  ),
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
      ),
    );
  }

  /// 构建差异显示组件
  List<Widget> _buildDifferenceWidgets(ComparisonResult result) {
    final widgets = <Widget>[];
    final valueExprs = _valueExpressionController.text.split(',');

    for (var i = 0; i < valueExprs.length; i++) {
      final expr = valueExprs[i].trim();
      final v1 = result.values1['value_$i']?.toString() ?? '';
      final v2 = result.values2['value_$i']?.toString() ?? '';

      if (v1 != v2) {
        widgets.add(
          Text(
            '${_getDisplayName(expr)}: $v1 -> $v2',
            style: const TextStyle(color: Colors.red),
          ),
        );
      }
    }

    return widgets;
  }
}

/// 对比结果数据类
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
