import 'dart:io' show Platform, Process, Directory, File;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'components/app_components.dart';
import 'theme/app_theme.dart';

class BcConfigShellPage extends StatefulWidget {
  const BcConfigShellPage({super.key});

  @override
  State<BcConfigShellPage> createState() => _BcConfigShellPageState();
}

class _BcConfigShellPageState extends State<BcConfigShellPage> {
  final ScrollController _logScrollController = ScrollController();

  bool _isProcessing = false;
  final List<String> _logMessages = [];
  String? _scriptPath;
  String? _appDataDir;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePaths();
    });
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _initializePaths() async {
    try {
      final appDocDir = await _getApplicationDirectory();
      _appDataDir = appDocDir.path;
      _scriptPath = p.join(_appDataDir!, 'fix_bc_config.sh');

      _addLogMessage('应用支持目录: $_appDataDir');
      _addLogMessage('脚本目标路径: $_scriptPath');
      if (mounted) setState(() {});
    } catch (e) {
      _addLogMessage('初始化路径出错: $e');
    }
  }

  Future<Directory> _getApplicationDirectory() async {
    final homeDir = Platform.environment['HOME'];
    if (homeDir != null && homeDir.isNotEmpty) {
      final appDataPath = p.join(
        homeDir,
        'Library',
        'Application Support',
        'V8WorkToolbox',
      );
      final dir = Directory(appDataPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    return Directory.current;
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

  Future<void> _copyScriptToAppDir() async {
    if (_scriptPath == null) {
      _addLogMessage('错误: 脚本路径未初始化');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      String? projectScriptPath;
      File? projectScriptFile;

      final currentDirScript = p.join(Directory.current.path, 'fix_bc_config.sh');
      if (await File(currentDirScript).exists()) {
        projectScriptPath = currentDirScript;
      }

      if (projectScriptPath == null) {
        final bundleScript = p.join(
          p.dirname(Directory.current.path),
          'Resources',
          'fix_bc_config.sh',
        );
        if (await File(bundleScript).exists()) {
          projectScriptPath = bundleScript;
        }
      }

      if (projectScriptPath == null && _appDataDir != null) {
        final appDocDirScript = p.join(_appDataDir!, 'fix_bc_config.sh');
        if (await File(appDocDirScript).exists()) {
          projectScriptPath = appDocDirScript;
        }
      }

      if (projectScriptPath != null) {
        projectScriptFile = File(projectScriptPath);
        _addLogMessage('检测到外部脚本: $projectScriptPath');
        await projectScriptFile.copy(_scriptPath!);
        await Process.run('chmod', ['+x', _scriptPath!]);
        _addLogMessage('✓ 脚本已同步到应用支持目录并设置执行权限');
      } else {
        _addLogMessage('未检测到外部脚本，正在从内置模板生成...');
        const scriptContent = '''#!/bin/bash
# Beyond Compare 配置修复脚本
echo "Beyond Compare 配置修复工具"
echo "=========================="

if [ \$# -eq 0 ]; then
    BC_DIR="/Users/\$(whoami)/Library/Application Support/Beyond Compare"
    echo "使用默认路径: \$BC_DIR"
else
    BC_DIR="\$1"
    echo "使用指定路径: \$BC_DIR"
fi

if [ ! -d "\$BC_DIR" ]; then
    echo "错误: Beyond Compare 配置目录不存在: \$BC_DIR"
    exit 1
fi

echo "正在处理 Beyond Compare 配置文件..."

BC_STATE_FILE="\$BC_DIR/BCState.xml"
if [ -f "\$BC_STATE_FILE" ]; then
    cp "\$BC_STATE_FILE" "\$BC_STATE_FILE.bak"
    sed -i '' '/<CheckID/d' "\$BC_STATE_FILE"
    sed -i '' '/<LastChecked/d' "\$BC_STATE_FILE"
    echo "✓ BCState.xml 文件已更新"
fi

BC_SESSIONS_FILE="\$BC_DIR/BCSessions.xml"
if [ -f "\$BC_SESSIONS_FILE" ]; then
    cp "\$BC_SESSIONS_FILE" "\$BC_SESSIONS_FILE.bak"
    sed -i '' 's/Flags="[^"]*" //' "\$BC_SESSIONS_FILE"
    echo "✓ BCSessions.xml 文件已更新"
fi

echo "正在启动 Beyond Compare..."
open -a "Beyond Compare"
echo "所有操作已完成！"
''';

        projectScriptFile = File(_scriptPath!);
        await projectScriptFile.writeAsString(scriptContent);
        await Process.run('chmod', ['+x', _scriptPath!]);
        _addLogMessage('✓ 已由内置模板生成 fix_bc_config.sh 并设置权限');
      }
    } catch (e) {
      _addLogMessage('准备脚本出错: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openScriptDirectory() async {
    if (_appDataDir == null) return;
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [_appDataDir!]);
      } else {
        await Process.run('open', [_appDataDir!]);
      }
      _addLogMessage('✓ 已在 Finder 中打开脚本所在目录');
    } catch (e) {
      _addLogMessage('打开目录失败: $e');
    }
  }

  Future<void> _executeScript([String? bcDir]) async {
    if (_scriptPath == null) {
      _addLogMessage('错误: 脚本路径未初始化');
      return;
    }

    final scriptFile = File(_scriptPath!);
    if (!await scriptFile.exists()) {
      _addLogMessage('脚本尚不存在，正在自动生成...');
      await _copyScriptToAppDir();
    }

    setState(() => _isProcessing = true);

    try {
      _addLogMessage(bcDir != null ? '执行脚本，参数: $bcDir' : '执行默认脚本...');
      final args = bcDir != null ? [bcDir] : <String>[];
      final result = await Process.run(_scriptPath!, args);

      if (result.stdout.toString().isNotEmpty) {
        for (final line in result.stdout.toString().split('\n')) {
          if (line.trim().isNotEmpty) _addLogMessage('输出: $line');
        }
      }

      if (result.stderr.toString().isNotEmpty) {
        _addLogMessage('错误: ${result.stderr}');
      }

      if (result.exitCode == 0) {
        _addLogMessage('✓ 脚本执行成功 (Exit 0)');
      } else {
        _addLogMessage('❌ 执行失败，退出码: ${result.exitCode}');
      }
    } catch (e) {
      _addLogMessage('执行脚本异常: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showBcDirDialog() async {
    final home = Platform.environment['HOME'] ?? '';
    final defaultBc = '$home/Library/Application Support/Beyond Compare';
    final controller = TextEditingController(text: defaultBc);

    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.borderRadiusMedium,
            side: const BorderSide(color: AppTheme.borderStrong),
          ),
          title: const Text('指定 Beyond Compare 目录执行', style: AppTheme.fontTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请输入包含 BCState.xml 与 BCSessions.xml 的配置目录:',
                style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: AppTheme.space8),
              AppTextField(
                controller: controller,
                hintText: '如 /Users/xxx/Library/Application Support/Beyond Compare',
              ),
            ],
          ),
          actions: [
            AppButton.ghost(
              label: '取消',
              size: AppButtonSize.small,
              onPressed: () => Navigator.pop(context),
            ),
            AppButton.primary(
              label: '执行脚本',
              size: AppButtonSize.small,
              onPressed: () => Navigator.pop(context, controller.text.trim()),
            ),
          ],
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      await _executeScript(selected);
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
                const Icon(Icons.terminal, size: 22, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                const Text('BC 脚本管理', style: AppTheme.fontHeadline),
                const Spacer(),
                if (_scriptPath != null)
                  const AppBadge(
                    label: 'Shell 工具',
                    color: AppTheme.accentSubtle,
                    textColor: AppTheme.accentLight,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              '管理并独立运行终端修复脚本，解决应用沙盒限制下的 Beyond Compare 配置修改',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space16),

            // 操作卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '脚本存放路径',
                    style: AppTheme.fontCaption.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space12,
                      vertical: AppTheme.space8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgInput,
                      borderRadius: AppTheme.borderRadiusSmall,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Text(
                      _scriptPath ?? '正在初始化路径...',
                      style: AppTheme.fontMono.copyWith(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: AppTheme.space16),
                  Wrap(
                    spacing: AppTheme.space8,
                    runSpacing: AppTheme.space8,
                    children: [
                      AppButton.primary(
                        label: '准备/同步脚本',
                        icon: Icons.copy,
                        size: AppButtonSize.regular,
                        isLoading: _isProcessing,
                        onPressed: _isProcessing ? null : _copyScriptToAppDir,
                      ),
                      AppButton.secondary(
                        label: '在 Finder 中显示',
                        icon: Icons.folder_open,
                        size: AppButtonSize.regular,
                        onPressed: _isProcessing ? null : _openScriptDirectory,
                      ),
                      AppButton.secondary(
                        label: '执行默认配置',
                        icon: Icons.play_arrow,
                        size: AppButtonSize.regular,
                        onPressed: _isProcessing ? null : () => _executeScript(),
                      ),
                      AppButton.ghost(
                        label: '指定目录执行...',
                        icon: Icons.play_circle_outline,
                        size: AppButtonSize.regular,
                        onPressed: _isProcessing ? null : _showBcDirDialog,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 日志终端
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
                          '终端执行日志',
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
                                '暂无输出日志',
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
