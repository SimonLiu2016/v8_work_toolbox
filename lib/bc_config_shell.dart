import 'dart:io' show Platform, Process, ProcessResult, Directory, File;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class BcConfigShellPage extends StatefulWidget {
  const BcConfigShellPage({super.key});

  @override
  State<BcConfigShellPage> createState() => _BcConfigShellPageState();
}

class _BcConfigShellPageState extends State<BcConfigShellPage> {
  bool _isProcessing = false;
  List<String> _logMessages = [];
  String? _scriptPath;
  String? _appDataDir;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePaths();
    });
  }

  Future<void> _initializePaths() async {
    try {
      // 获取应用数据目录
      Directory appDocDir = await getApplicationDocumentsDirectory();
      _appDataDir = appDocDir.path;

      // 设置脚本路径
      _scriptPath = path.join(_appDataDir!, 'fix_bc_config.sh');

      _addLogMessage('应用数据目录: $_appDataDir');
      _addLogMessage('脚本路径: $_scriptPath');
    } catch (e) {
      _addLogMessage('初始化路径时出错: $e');
    }
  }

  Future<Directory> getApplicationDocumentsDirectory() async {
    if (Platform.isMacOS || Platform.isLinux) {
      String? homeDir = Platform.environment['HOME'];
      if (homeDir != null) {
        String appDataPath = path.join(
          homeDir,
          'Library',
          'Application Support',
          'V8WorkToolbox',
        );
        Directory dir = Directory(appDataPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    } else if (Platform.isWindows) {
      String? appData = Platform.environment['APPDATA'];
      if (appData != null) {
        String appDataPath = path.join(appData, 'V8WorkToolbox');
        Directory dir = Directory(appDataPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    }

    // 如果无法获取特定路径，使用当前目录
    return Directory.current;
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(
        '${DateTime.now().toString().split('.').first}: $message',
      );
    });
  }

  Future<void> _copyScriptToAppDir() async {
    if (_scriptPath == null) {
      _addLogMessage('错误: 脚本路径未初始化');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // 尝试从不同可能的位置查找脚本
      String? projectScriptPath;
      File? projectScriptFile;

      // 首先尝试当前工作目录
      String currentDirScript = path.join(
        Directory.current.path,
        'fix_bc_config.sh',
      );
      if (await File(currentDirScript).exists()) {
        projectScriptPath = currentDirScript;
      }

      // 如果当前目录没有，尝试应用 Bundle 内的资源
      if (projectScriptPath == null) {
        // 尝试在应用的资源目录中查找
        String bundleScript = path.join(
          path.dirname(Directory.current.path),
          'Resources',
          'fix_bc_config.sh',
        );
        if (await File(bundleScript).exists()) {
          projectScriptPath = bundleScript;
        }
      }

      // 如果还是没有找到，尝试使用应用文档目录
      if (projectScriptPath == null) {
        // 尝试在应用文档目录中查找，如果之前已复制过
        String appDocDirScript = path.join(_appDataDir!, 'fix_bc_config.sh');
        if (await File(appDocDirScript).exists()) {
          projectScriptPath = appDocDirScript;
        }
      }

      // 如果还是没有找到，尝试在当前可执行文件所在目录
      if (projectScriptPath == null) {
        String executableDir = path.dirname(Platform.resolvedExecutable);
        String execScript = path.join(executableDir, 'fix_bc_config.sh');
        if (await File(execScript).exists()) {
          projectScriptPath = execScript;
        }
      }

      if (projectScriptPath != null) {
        projectScriptFile = File(projectScriptPath);
        _addLogMessage('找到脚本文件: $projectScriptPath');
      } else {
        _addLogMessage('错误: 无法找到 fix_bc_config.sh 脚本文件');
        _addLogMessage('正在尝试从内置内容创建脚本...');

        // 创建脚本内容
        String scriptContent = '''#!/bin/bash

# Beyond Compare 配置修复脚本
# 这个脚本可以直接在终端中运行，避免 macOS 应用程序权限问题

echo "Beyond Compare 配置修复工具"
echo "=========================="

# 检查是否提供了 Beyond Compare 配置目录路径
if [ \$# -eq 0 ]; then
    # 默认路径
    BC_DIR="/Users/\$(whoami)/Library/Application Support/Beyond Compare"
    echo "使用默认路径: \$BC_DIR"
else
    BC_DIR="\$1"
    echo "使用指定路径: \$BC_DIR"
fi

# 检查目录是否存在
if [ ! -d "\$BC_DIR" ]; then
    echo "错误: Beyond Compare 配置目录不存在: \$BC_DIR"
    echo "请确保 Beyond Compare 已安装，或提供正确的配置目录路径"
    echo "用法: ./fix_bc_config.sh [配置目录路径]"
    exit 1
fi

echo "正在处理 Beyond Compare 配置文件..."

# 步骤1: 修改 BCState.xml 文件
BC_STATE_FILE="\$BC_DIR/BCState.xml"
if [ -f "\$BC_STATE_FILE" ]; then
    # 创建备份文件
    cp "\$BC_STATE_FILE" "\$BC_STATE_FILE.bak"
    echo "已创建 BCState.xml 备份文件"
    
    # 删除 CheckID 和 LastChecked 标签
    sed -i '' '/<CheckID/d' "\$BC_STATE_FILE"
    sed -i '' '/<LastChecked/d' "\$BC_STATE_FILE"
    echo "✓ BCState.xml 文件已更新"
else
    echo "警告: BCState.xml 文件不存在: \$BC_STATE_FILE"
fi

# 步骤2: 修改 BCSessions.xml 文件
BC_SESSIONS_FILE="\$BC_DIR/BCSessions.xml"
if [ -f "\$BC_SESSIONS_FILE" ]; then
    # 创建备份文件
    cp "\$BC_SESSIONS_FILE" "\$BC_SESSIONS_FILE.bak"
    echo "已创建 BCSessions.xml 备份文件"
    
    # 删除 Flags 属性
    sed -i '' 's/Flags="[^"]*" //' "\$BC_SESSIONS_FILE"
    echo "✓ BCSessions.xml 文件已更新"
else
    echo "警告: BCSessions.xml 文件不存在: \$BC_SESSIONS_FILE"
fi

# 步骤3: 启动 Beyond Compare
echo "正在启动 Beyond Compare..."
open -a "Beyond Compare"

echo "所有操作已完成！"
echo ""
echo "提示: 如果仍然遇到权限问题，请尝试以下方法:"
echo "1. 在终端中运行此脚本: ./fix_bc_config.sh"
echo "2. 或者手动运行以下命令:"
echo "   cd '/Users/\$(whoami)/Library/Application Support/Beyond Compare'"
echo "   sed -i '' '/<CheckID/d' BCState.xml"
echo "   sed -i '' '/<LastChecked/d' BCState.xml"
echo "   sed -i '' 's/Flags=\\\"[^\\\"]*\\\" //' BCSessions.xml"''';

        // 创建脚本文件
        projectScriptFile = File(_scriptPath!);
        await projectScriptFile.writeAsString(scriptContent);

        // 设置执行权限
        await Process.run('chmod', ['+x', _scriptPath!]);

        _addLogMessage('✓ 脚本已从内置内容创建: ${_scriptPath!}');
        return; // 既然我们已经创建了脚本，就直接返回
      }

      // 复制脚本到应用数据目录
      await projectScriptFile.copy(_scriptPath!);

      // 设置执行权限
      await Process.run('chmod', ['+x', _scriptPath!]);

      _addLogMessage('✓ 脚本已复制到应用数据目录: $_scriptPath');
      _addLogMessage('✓ 脚本权限已设置');
    } catch (e) {
      _addLogMessage('复制脚本时出错: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // 实现打开脚本目录的功能
  Future<void> _openScriptDirectory() async {
    if (_appDataDir == null) {
      _addLogMessage('错误: 应用数据目录未初始化');
      return;
    }

    try {
      String directoryPath = _appDataDir!;
      _addLogMessage('正在打开脚本目录: $directoryPath');

      if (Platform.isMacOS) {
        await Process.run('open', [directoryPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [directoryPath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [directoryPath]);
      }

      _addLogMessage('✓ 脚本目录已打开');
    } catch (e) {
      _addLogMessage('打开脚本目录时出错: $e');
    }
  }

  // 实现调用终端执行脚本的能力
  Future<void> _executeScript() async {
    if (_scriptPath == null) {
      _addLogMessage('错误: 脚本路径未初始化');
      return;
    }

    File scriptFile = File(_scriptPath!);
    if (!await scriptFile.exists()) {
      _addLogMessage('错误: 脚本文件不存在: ${_scriptPath!}');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      _addLogMessage('正在执行脚本: ${_scriptPath!}');

      // 执行脚本
      ProcessResult result = await Process.run(_scriptPath!, []);

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
        _addLogMessage('✓ 脚本执行成功');
      } else {
        _addLogMessage('❌ 脚本执行失败，退出码: ${result.exitCode}');
      }
    } catch (e) {
      _addLogMessage('执行脚本时出错: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // 执行脚本并传入配置目录参数
  Future<void> _executeScriptWithBcDir(String bcDir) async {
    if (_scriptPath == null) {
      _addLogMessage('错误: 脚本路径未初始化');
      return;
    }

    File scriptFile = File(_scriptPath!);
    if (!await scriptFile.exists()) {
      _addLogMessage('错误: 脚本文件不存在: ${_scriptPath!}');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      _addLogMessage('正在执行脚本: ${_scriptPath!}，配置目录: $bcDir');

      // 执行脚本并传入配置目录参数
      ProcessResult result = await Process.run(_scriptPath!, [bcDir]);

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
        _addLogMessage('✓ 脚本执行成功');
      } else {
        _addLogMessage('❌ 脚本执行失败，退出码: ${result.exitCode}');
      }
    } catch (e) {
      _addLogMessage('执行脚本时出错: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // 获取当前用户名
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beyond Compare 脚本管理'),
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
                    const Text('• 将 fix_bc_config.sh 脚本复制到应用数据目录'),
                    const Text('• 提供打开脚本目录的功能'),
                    const Text('• 调用终端执行脚本'),
                    const Text('• 支持指定配置目录参数执行脚本'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _copyScriptToAppDir,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.copy),
                          label: Text(_isProcessing ? '复制中...' : '复制脚本'),
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
                        ElevatedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : _openScriptDirectory,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('打开目录'),
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
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '执行脚本',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _executeScript,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('执行脚本'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _showBcDirDialog,
                            icon: const Icon(Icons.play_arrow_outlined),
                            label: const Text('指定目录'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
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
              flex: 2,
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
                            child: Scrollbar(
                              child: SelectionArea(
                                child: ListView.builder(
                                  itemCount: _logMessages.length,
                                  itemBuilder: (context, index) {
                                    return SelectableText(
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

  Future<void> _showBcDirDialog() async {
    String bcDir =
        '/Users/${getCurrentUsername()}/Library/Application Support/Beyond Compare';

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        String inputBcDir = bcDir;
        return AlertDialog(
          title: const Text('指定 Beyond Compare 配置目录'),
          content: TextField(
            decoration: const InputDecoration(
              hintText: '输入 Beyond Compare 配置目录路径',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: inputBcDir),
            onChanged: (value) {
              inputBcDir = value;
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _executeScriptWithBcDir(inputBcDir);
              },
              child: const Text('执行'),
            ),
          ],
        );
      },
    );
  }
}
