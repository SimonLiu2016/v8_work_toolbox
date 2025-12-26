import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform, Process, ProcessResult;

class BcConfigHomePage extends StatefulWidget {
  const BcConfigHomePage({super.key});

  @override
  State<BcConfigHomePage> createState() => _BcConfigHomePageState();
}

class _BcConfigHomePageState extends State<BcConfigHomePage> {
  String get defaultBcDir =>
      '/Users/${getCurrentUsername()}/Library/Application Support/Beyond Compare';
  String bcDir = '/Users/simon/Library/Application Support/Beyond Compare';
  bool _isProcessing = false;
  List<String> _logMessages = [];
  bool _bcStateModified = false;
  bool _bcSessionsModified = false;
  bool _bcLaunched = false;
  bool _useTerminalScript = false;

  String getCurrentUsername() {
    if (Platform.isMacOS || Platform.isLinux) {
      // Unix-like系统：从环境变量获取
      return Platform.environment['USER'] ?? '未知用户';
    } else if (Platform.isWindows) {
      // Windows系统：从环境变量获取
      return Platform.environment['USERNAME'] ?? '未知用户';
    } else {
      return '未知用户';
    }
  }

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
        // 尝试使用默认目录
        bcDir = defaultBcDir;
        final defaultDirectory = Directory(bcDir);
        if (!await defaultDirectory.exists()) {
          _addLogMessage('默认目录也不存在，请手动选择配置文件目录');
          return;
        }
      }

      _addLogMessage('正在处理配置文件...');
      _addLogMessage('配置目录: $bcDir');

      // 首先尝试直接修改
      bool directModificationSuccess = await _tryDirectModification();

      if (!directModificationSuccess) {
        // 如果直接修改失败，尝试使用终端脚本
        _addLogMessage('直接修改失败，尝试使用终端脚本...');
        await _modifyBcConfigWithTerminalScript();
      } else {
        _addLogMessage('✓ 直接修改成功');
      }

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

  /// 尝试直接修改配置文件
  Future<bool> _tryDirectModification() async {
    try {
      // 步骤1: 修改 BCState.xml 文件
      await _modifyBcStateFile();

      // 步骤2: 修改 BCSessions.xml 文件
      await _modifyBcSessionsFile();

      return true;
    } catch (e) {
      // 检查是否是权限错误
      if (e.toString().contains('Operation not permitted') ||
          e.toString().contains('errno = 1') ||
          e is PathAccessException) {
        _addLogMessage('❌ 权限错误，将尝试使用终端脚本');
        return false;
      } else {
        _addLogMessage('❌ 修改配置文件时出现错误: $e');
        return false;
      }
    }
  }

  Future<void> _modifyBcStateFile() async {
    final bcStateFile = File('$bcDir/BCState.xml');
    if (await bcStateFile.exists()) {
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
    } else {
      _addLogMessage('警告: BCState.xml 文件不存在');
    }
  }

  Future<void> _modifyBcSessionsFile() async {
    final bcSessionsFile = File('$bcDir/BCSessions.xml');

    // 先检查目录是否存在
    if (!await Directory(bcDir).exists()) {
      _addLogMessage('❌ 错误: 目录 $bcDir 不存在');
      return;
    }

    if (await bcSessionsFile.exists()) {
      // 创建备份文件
      final backupPath = '$bcDir/BCSessions.xml.bak';
      final backupFile = File(backupPath);

      // 如果备份文件已存在，先删除
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      await bcSessionsFile.copy(backupPath);
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
    } else {
      _addLogMessage('警告: BCSessions.xml 文件不存在');
    }
  }

  /// 使用终端脚本修改配置文件
  Future<void> _modifyBcConfigWithTerminalScript() async {
    _addLogMessage('🔧 使用终端脚本修改配置文件...');

    try {
      // 获取项目根目录
      String projectRoot = Directory.current.path;
      String scriptPath = '$projectRoot/fix_bc_config.sh';

      _addLogMessage('脚本路径: $scriptPath');
      _addLogMessage('配置目录: $bcDir');

      // 检查脚本是否存在
      File scriptFile = File(scriptPath);
      if (!await scriptFile.exists()) {
        _addLogMessage('❌ 错误: 终端脚本不存在: $scriptPath');
        _addLogMessage('💡 请确保 fix_bc_config.sh 文件在项目根目录中');
        return;
      }

      // 确保脚本有执行权限
      await Process.run('chmod', ['+x', scriptPath]);
      _addLogMessage('✓ 脚本权限已设置');

      // 执行脚本
      _addLogMessage('正在执行终端脚本...');
      ProcessResult result = await Process.run(scriptPath, [bcDir]);

      // 输出脚本执行结果
      if (result.stdout.isNotEmpty) {
        List<String> lines = result.stdout.toString().split('\n');
        for (String line in lines) {
          if (line.trim().isNotEmpty) {
            _addLogMessage('脚本输出: $line');
          }
        }
      }

      if (result.stderr.isNotEmpty) {
        _addLogMessage('脚本错误输出: ${result.stderr}');
      }

      if (result.exitCode == 0) {
        _addLogMessage('✓ 终端脚本执行成功');
        setState(() {
          _bcStateModified = true;
          _bcSessionsModified = true;
        });
      } else {
        _addLogMessage('❌ 终端脚本执行失败，退出码: ${result.exitCode}');
        _addLogMessage('💡 提示: 您也可以手动在终端中运行:');
        _addLogMessage('   $scriptPath "$bcDir"');
      }
    } catch (e) {
      _addLogMessage('❌ 执行终端脚本时出现错误: $e');
      _addLogMessage('💡 您可以手动在终端中运行以下命令:');
      _addLogMessage('   chmod +x fix_bc_config.sh');
      _addLogMessage('   ./fix_bc_config.sh "$bcDir"');
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

  Future<void> _openSystemSettings() async {
    _addLogMessage('正在打开系统设置...');
    try {
      // 打开系统设置的安全性与隐私页面
      final result = await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security',
      ]);
      if (result.exitCode == 0) {
        _addLogMessage('✓ 系统设置已打开，请在"隐私"选项卡中授予权限');
      } else {
        _addLogMessage('打开系统设置时出现错误: ${result.stderr}');
        // 备用方案：打开通用系统设置
        final fallbackResult = await Process.run('open', [
          'x-apple.systempreferences:',
        ]);
        if (fallbackResult.exitCode != 0) {
          _addLogMessage('备用方案也失败了: ${fallbackResult.stderr}');
        }
      }
    } catch (e) {
      _addLogMessage('打开系统设置时出现异常: $e');
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
                    const SizedBox(height: 8),
                    const Text(
                      '🔒 权限说明:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      '• 首次运行需授权文件访问权限',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                    const Text(
                      '• 遇权限错误将自动使用终端脚本',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(text: bcDir),
                            decoration: const InputDecoration(
                              hintText: 'Beyond Compare 配置目录路径',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                bcDir = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isProcessing
                              ? null
                              : () async {
                                  String? selectedDirectory = await FilePicker
                                      .platform
                                      .getDirectoryPath();
                                  if (selectedDirectory != null) {
                                    setState(() {
                                      bcDir = selectedDirectory;
                                    });
                                    _addLogMessage('已选择目录: $selectedDirectory');
                                  }
                                },
                          child: const Text('选择'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
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
                          label: Text(_isProcessing ? '处理中...' : '执行修改'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _openSystemSettings,
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text('系统设置'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 2, // 增加日志区域的比例
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
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
