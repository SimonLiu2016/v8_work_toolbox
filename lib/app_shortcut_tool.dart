import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class AppShortcutToolPage extends StatefulWidget {
  const AppShortcutToolPage({super.key});

  @override
  State<AppShortcutToolPage> createState() => _AppShortcutToolPageState();
}

class _AppShortcutToolPageState extends State<AppShortcutToolPage> {
  String _targetAppName = '';
  String _savePath = '';
  bool _isLoading = false;
  String _statusMessage = '';
  List<Map<String, String>> _shortcuts = [];

  @override
  void initState() {
    super.initState();
    _statusMessage = '请输入应用名称并选择保存路径';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用快捷键获取工具'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '说明：此工具将获取指定应用的所有快捷键信息，并导出为txt文件',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: '目标应用名称',
                              hintText: '例如：Finder、Safari、Visual Studio Code',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _targetAppName = value;
                              });
                            },
                            controller: TextEditingController(
                              text: _targetAppName,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _selectAppFromList,
                            child: const Text('选择应用'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: '保存路径',
                              hintText: '选择保存快捷键文件的位置',
                            ),
                            enabled: false,
                            controller: TextEditingController(text: _savePath),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _selectSavePath,
                            child: const Text('选择'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _extractShortcuts,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : const Text('开始提取'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _clearResults,
                            child: const Text('清空结果'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_statusMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColor(),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_statusMessage),
              ),
            const SizedBox(height: 16),
            if (_shortcuts.isNotEmpty)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '提取结果预览 (前20条)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _shortcuts.length > 20
                                ? 20
                                : _shortcuts.length,
                            itemBuilder: (context, index) {
                              final shortcut = _shortcuts[index];
                              return ListTile(
                                title: Text(shortcut['description'] ?? ''),
                                subtitle: Text(
                                  '${shortcut['shortcut'] ?? ''} | ${shortcut['category'] ?? ''}',
                                ),
                                dense: true,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '共找到 ${_shortcuts.length} 个快捷键',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (_statusMessage.contains('成功')) {
      return Colors.green.shade100;
    } else if (_statusMessage.contains('错误') || _statusMessage.contains('失败')) {
      return Colors.red.shade100;
    } else {
      return Colors.blue.shade100;
    }
  }

  Future<void> _selectAppFromList() async {
    try {
      final runningApps = await _getRunningApps();
      if (runningApps.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有找到正在运行的应用')));
        return;
      }

      final selectedApp = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('选择应用'),
            content: SizedBox(
              width: 500,
              height: 400,
              child: ListView.builder(
                itemCount: runningApps.length,
                itemBuilder: (context, index) {
                  final app = runningApps[index];
                  return ListTile(
                    title: Text(app['name'] ?? ''),
                    subtitle: Text('Bundle ID: ${app['bundleId'] ?? ''}'),
                    trailing: Text(
                      'Executable: ${app['executableName'] ?? ''}',
                    ),
                    onTap: () {
                      Navigator.pop(context, app['name']);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );

      if (selectedApp != null) {
        setState(() {
          _targetAppName = selectedApp;
        });
      }
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取应用列表时发生错误: "${e.message}"')));
    }
  }

  Future<void> _selectSavePath() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _savePath = selectedDirectory;
      });
    }
  }

  Future<void> _extractShortcuts() async {
    if (_targetAppName.isEmpty) {
      setState(() {
        _statusMessage = '请输入目标应用名称';
      });
      return;
    }

    if (_savePath.isEmpty) {
      setState(() {
        _statusMessage = '请选择保存路径';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '正在提取快捷键信息...';
      _shortcuts.clear();
    });

    try {
      // 模拟提取快捷键的过程
      // 在实际实现中，这里会调用系统API获取应用的快捷键信息
      await Future.delayed(const Duration(seconds: 2)); // 模拟API调用时间

      // 这里是模拟数据，实际实现需要调用系统的Accessibility API
      List<Map<String, String>> shortcuts = await _getAppShortcuts(
        _targetAppName,
      );

      setState(() {
        _shortcuts = shortcuts;
      });

      if (shortcuts.isNotEmpty) {
        await _saveShortcutsToFile(shortcuts);
        setState(() {
          _statusMessage = '成功提取 ${shortcuts.length} 个快捷键，并已保存到: $_savePath';
        });
      } else {
        // 检查是否是安全限制的应用
        String lowerAppName = _targetAppName.toLowerCase();
        bool isSecurityRestricted =
            lowerAppName.contains('iterm') ||
            lowerAppName.contains('terminal') ||
            lowerAppName.contains('console') ||
            lowerAppName.contains('password') ||
            lowerAppName.contains('keychain') ||
            lowerAppName.contains('encrypt');

        setState(() {
          if (isSecurityRestricted) {
            _statusMessage =
                '未找到 "$_targetAppName" 的快捷键信息。此应用可能因安全限制阻止了外部访问其菜单信息，这是正常的安全保护机制。';
          } else {
            _statusMessage = '未找到应用 "$_targetAppName" 的快捷键信息，请确保应用正在运行且名称正确';
          }
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '提取过程中发生错误: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  static const platform = MethodChannel('app_manager_channel');

  Future<List<Map<String, String>>> _getRunningApps() async {
    try {
      final result = await platform.invokeMethod('getRunningApps');
      if (result != null && result is List) {
        List<Map<String, String>> apps = [];
        for (var item in result) {
          if (item is Map) {
            apps.add({
              'name': (item['name'] as String?) ?? '',
              'bundleId': (item['bundleId'] as String?) ?? '',
              'executableName': (item['executableName'] as String?) ?? '',
            });
          }
        }
        return apps;
      } else {
        return [];
      }
    } on PlatformException catch (e) {
      print('获取运行应用时发生错误: "${e.message}"');
      return [];
    }
  }

  Future<List<Map<String, String>>> _getAppShortcuts(String appName) async {
    // 这里需要使用平台特定的代码来获取应用的快捷键
    // 通过MethodChannel调用原生macOS代码
    try {
      print('开始获取应用快捷键，应用名称: $appName');
      final result = await platform.invokeMethod('getAppShortcuts', {
        'appName': appName,
      });

      print('原生插件返回结果: $result');

      if (result != null && result is List<dynamic>) {
        if (result.isEmpty) {
          print('警告: 获取到的快捷键列表为空');
        }

        return result.cast<Map<String, dynamic>>().map((item) {
          return {
            'description': item['description']?.toString() ?? '',
            'shortcut': item['shortcut']?.toString() ?? '',
            'category': item['category']?.toString() ?? appName,
          };
        }).toList();
      } else {
        print('返回结果为空或非列表类型');
        // 如果原生代码无法获取快捷键，则返回空列表
        return [];
      }
    } on PlatformException catch (e) {
      print('获取应用快捷键时发生错误: "${e.message}"');
      // 发生错误时返回空列表
      return [];
    }
  }

  Future<void> _saveShortcutsToFile(List<Map<String, String>> shortcuts) async {
    String fileName = '${_targetAppName.replaceAll(' ', '_')}_shortcuts.txt';
    String fullPath = '$_savePath/$fileName';

    StringBuffer buffer = StringBuffer();
    for (var shortcut in shortcuts) {
      String description = shortcut['description'] ?? '';
      String shortcutKey = shortcut['shortcut'] ?? '';
      String category = shortcut['category'] ?? _targetAppName;

      buffer.writeln('$description|$shortcutKey|$category');
    }

    File file = File(fullPath);
    await file.writeAsString(buffer.toString());
  }

  void _clearResults() {
    setState(() {
      _shortcuts.clear();
      _statusMessage = '';
    });
  }
}
