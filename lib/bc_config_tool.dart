import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';

class BcConfigHomePage extends StatefulWidget {
  const BcConfigHomePage({super.key});

  @override
  State<BcConfigHomePage> createState() => _BcConfigHomePageState();
}

class _BcConfigHomePageState extends State<BcConfigHomePage> {
  final String bcDir = '/Users/simon/Library/ApplicationSupport/Beyond Compare';
  bool _isProcessing = false;
  List<String> _logMessages = [];
  bool _bcStateModified = false;
  bool _bcSessionsModified = false;
  bool _bcLaunched = false;

  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().split('.').first}: $message',
      );
    });
  }

  Future<void> _modifyBcConfig() async {
    setState(() {
      _isProcessing = true;
      _logMessages.clear();
      _bcStateModified = false;
      _bcSessionsModified = false;
      _bcLaunched = false;
    });

    try {
      // 检查目录是否存在
      final directory = Directory(bcDir);
      if (!await directory.exists()) {
        _addLogMessage('错误: Beyond Compare 配置目录不存在');
        return;
      }

      _addLogMessage('正在处理配置文件...');

      // 步骤1: 修改 BCState.xml 文件
      await _modifyBcStateFile();

      // 步骤2: 修改 BCSessions.xml 文件
      await _modifyBcSessionsFile();

      // 步骤3: 启动 Beyond Compare
      await _launchBeyondCompare();

      _addLogMessage('所有操作已完成！');
    } catch (e) {
      _addLogMessage('执行过程中出现错误: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _modifyBcStateFile() async {
    final bcStateFile = File('$bcDir/BCState.xml');
    if (await bcStateFile.exists()) {
      try {
        // 创建备份文件
        await bcStateFile.copy('$bcDir/BCState.xml.bak');
        _addLogMessage('已创建 BCState.xml 备份文件');

        // 读取文件内容
        String content = await bcStateFile.readAsString();

        // 删除 CheckID 和 LastChecked 标签
        content = content.replaceAll(RegExp(r'<CheckID[^>]*>\s*'), '');
        content = content.replaceAll(RegExp(r'<LastChecked[^>]*>\s*'), '');

        // 写入修改后的内容
        await bcStateFile.writeAsString(content);
        _addLogMessage('✓ BCState.xml 文件已更新');
        setState(() {
          _bcStateModified = true;
        });
      } catch (e) {
        _addLogMessage('修改 BCState.xml 时出现错误: $e');
      }
    } else {
      _addLogMessage('警告: BCState.xml 文件不存在');
    }
  }

  Future<void> _modifyBcSessionsFile() async {
    final bcSessionsFile = File('$bcDir/BCSessions.xml');
    if (await bcSessionsFile.exists()) {
      try {
        // 创建备份文件
        await bcSessionsFile.copy('$bcDir/BCSessions.xml.bak');
        _addLogMessage('已创建 BCSessions.xml 备份文件');

        // 读取文件内容
        String content = await bcSessionsFile.readAsString();

        // 删除 Flags 属性
        content = content.replaceAll(RegExp(r'Flags="[^"]*"\s*'), '');

        // 写入修改后的内容
        await bcSessionsFile.writeAsString(content);
        _addLogMessage('✓ BCSessions.xml 文件已更新');
        setState(() {
          _bcSessionsModified = true;
        });
      } catch (e) {
        _addLogMessage('修改 BCSessions.xml 时出现错误: $e');
      }
    } else {
      _addLogMessage('警告: BCSessions.xml 文件不存在');
    }
  }

  Future<void> _launchBeyondCompare() async {
    _addLogMessage('正在启动 Beyond Compare...');
    try {
      final result = await Process.run('open', ['-a', 'Beyond Compare']);
      if (result.exitCode == 0) {
        _addLogMessage('✓ Beyond Compare 已启动');
        setState(() {
          _bcLaunched = true;
        });
      } else {
        _addLogMessage('启动 Beyond Compare 时出现错误: ${result.stderr}');
      }
    } catch (e) {
      _addLogMessage('启动 Beyond Compare 时出现异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beyond Compare 配置工具'),
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
                      '功能说明',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('• 修改 BCState.xml 文件，删除 CheckID 和 LastChecked'),
                    const Text('• 修改 BCSessions.xml 文件，删除 Flags 属性'),
                    const Text('• 启动 Beyond Compare 应用程序'),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _modifyBcConfig,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_isProcessing ? '处理中...' : '执行配置修改'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '操作日志',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
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
            ),
          ],
        ),
      ),
    );
  }
}
