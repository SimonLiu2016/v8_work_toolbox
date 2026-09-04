import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'components/app_components.dart';
import 'theme/app_theme.dart';

class BcConfigHomePage extends StatefulWidget {
  const BcConfigHomePage({super.key});

  @override
  State<BcConfigHomePage> createState() => _BcConfigHomePageState();
}

class _BcConfigHomePageState extends State<BcConfigHomePage> {
  final TextEditingController _bcDirController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  bool _isProcessing = false;
  final List<String> _logMessages = [];
  bool _bcStateModified = false;
  bool _bcSessionsModified = false;
  bool _bcLaunched = false;

  String get defaultBcDir {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      return '$home/Library/Application Support/Beyond Compare';
    }
    final user = Platform.environment['USER'] ?? 'user';
    return '/Users/$user/Library/Application Support/Beyond Compare';
  }

  @override
  void initState() {
    super.initState();
    _bcDirController.text = defaultBcDir;
  }

  @override
  void dispose() {
    _bcDirController.dispose();
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

  Future<void> _selectBcDir() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择 Beyond Compare 配置目录',
      );
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        setState(() {
          _bcDirController.text = selectedDirectory;
        });
        _addLogMessage('已选择目录: $selectedDirectory');
      }
    } catch (e) {
      _addLogMessage('选择目录出错: $e');
    }
  }

  Future<void> _modifyBcConfig() async {
    setState(() {
      _isProcessing = true;
      _logMessages.clear();
      _bcStateModified = false;
      _bcSessionsModified = false;
      _bcLaunched = false;
    });

    final targetDir = _bcDirController.text.trim();

    try {
      final directory = Directory(targetDir);
      if (!await directory.exists()) {
        _addLogMessage('指定的配置目录不存在: $targetDir');
        if (targetDir != defaultBcDir) {
          final defaultDirectory = Directory(defaultBcDir);
          if (await defaultDirectory.exists()) {
            _bcDirController.text = defaultBcDir;
            _addLogMessage('已自动切换到默认目录: $defaultBcDir');
          } else {
            _addLogMessage('默认目录亦不存在，请手动浏览选择有效的 Beyond Compare 支持目录');
            return;
          }
        } else {
          return;
        }
      }

      final activeDir = _bcDirController.text.trim();
      _addLogMessage('开始处理配置文件...');
      _addLogMessage('目标配置目录: $activeDir');

      final directOk = await _tryDirectModification(activeDir);

      if (!directOk) {
        _addLogMessage('直接写文件失败，尝试运行本地终端修复脚本...');
        await _modifyBcConfigWithTerminalScript(activeDir);
      } else {
        _addLogMessage('✓ 配置文件修改成功');
      }

      await _launchBeyondCompare();
      _addLogMessage('全部操作完成！');
    } catch (e) {
      _addLogMessage('处理过程发生异常: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<bool> _tryDirectModification(String dirPath) async {
    try {
      await _modifyBcStateFile(dirPath);
      await _modifyBcSessionsFile(dirPath);
      return true;
    } catch (e) {
      if (e.toString().contains('Operation not permitted') ||
          e.toString().contains('errno = 1') ||
          e is PathAccessException) {
        _addLogMessage('❌ 遭遇系统沙盒/文件权限限制，将尝试终端执行');
      } else {
        _addLogMessage('❌ 修改配置错误: $e');
      }
      return false;
    }
  }

  Future<void> _modifyBcStateFile(String dirPath) async {
    final bcStateFile = File('$dirPath/BCState.xml');
    if (await bcStateFile.exists()) {
      await bcStateFile.copy('$dirPath/BCState.xml.bak');
      _addLogMessage('已创建 BCState.xml.bak 备份');

      String content = await bcStateFile.readAsString();
      content = content.replaceAll(RegExp(r'<CheckID[^>]*>\s*'), '');
      content = content.replaceAll(RegExp(r'<LastChecked[^>]*>\s*'), '');

      await bcStateFile.writeAsString(content);
      _addLogMessage('✓ BCState.xml 清除 CheckID/LastChecked 成功');
      setState(() => _bcStateModified = true);
    } else {
      _addLogMessage('提示: BCState.xml 未找到，跳过');
    }
  }

  Future<void> _modifyBcSessionsFile(String dirPath) async {
    final bcSessionsFile = File('$dirPath/BCSessions.xml');
    if (await bcSessionsFile.exists()) {
      final backupPath = '$dirPath/BCSessions.xml.bak';
      final backupFile = File(backupPath);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      await bcSessionsFile.copy(backupPath);
      _addLogMessage('已创建 BCSessions.xml.bak 备份');

      String content = await bcSessionsFile.readAsString();
      content = content.replaceAll(RegExp(r'Flags="[^"]*"\s*'), '');

      await bcSessionsFile.writeAsString(content);
      _addLogMessage('✓ BCSessions.xml 清除 Flags 成功');
      setState(() => _bcSessionsModified = true);
    } else {
      _addLogMessage('提示: BCSessions.xml 未找到，跳过');
    }
  }

  Future<void> _modifyBcConfigWithTerminalScript(String dirPath) async {
    try {
      final projectRoot = Directory.current.path;
      final scriptPath = '$projectRoot/fix_bc_config.sh';
      final scriptFile = File(scriptPath);

      if (!await scriptFile.exists()) {
        _addLogMessage('❌ 终端脚本不存在: $scriptPath');
        return;
      }

      await Process.run('chmod', ['+x', scriptPath]);
      final result = await Process.run(scriptPath, [dirPath]);

      if (result.stdout.toString().isNotEmpty) {
        for (final line in result.stdout.toString().split('\n')) {
          if (line.trim().isNotEmpty) _addLogMessage('脚本: $line');
        }
      }

      if (result.exitCode == 0) {
        _addLogMessage('✓ 终端修复脚本执行成功');
        setState(() {
          _bcStateModified = true;
          _bcSessionsModified = true;
        });
      } else {
        _addLogMessage('❌ 终端脚本执行失败 (退出码 ${result.exitCode}): ${result.stderr}');
      }
    } catch (e) {
      _addLogMessage('❌ 执行终端脚本异常: $e');
    }
  }

  Future<void> _launchBeyondCompare() async {
    _addLogMessage('正在启动 Beyond Compare...');
    try {
      final result = await Process.run('open', ['-a', 'Beyond Compare']);
      if (result.exitCode == 0) {
        _addLogMessage('✓ Beyond Compare 已启动');
        setState(() => _bcLaunched = true);
      } else {
        _addLogMessage('启动 Beyond Compare 提示: ${result.stderr}');
      }
    } catch (e) {
      _addLogMessage('启动应用失败: $e');
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      await Process.run('open', ['x-apple.systempreferences:com.apple.preference.security']);
      _addLogMessage('已唤起系统设置「隐私与安全性」');
    } catch (e) {
      _addLogMessage('打开系统设置失败: $e');
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
                const Icon(Icons.tune, size: 22, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                const Text('BC 配置工具', style: AppTheme.fontHeadline),
                const Spacer(),
                if (_bcLaunched)
                  const AppBadge(
                    label: '已完成并启动',
                    color: AppTheme.successSubtle,
                    textColor: AppTheme.success,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              '一键重置 Beyond Compare 试用状态与会话标记（自动备份原配置文件）',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space16),

            // 功能配置卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _bcDirController,
                          label: 'Beyond Compare 配置目录',
                          hintText: 'Beyond Compare 数据存放目录...',
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '浏览',
                          icon: Icons.folder_open,
                          size: AppButtonSize.regular,
                          onPressed: _isProcessing ? null : _selectBcDir,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space16),

                  // 处理步骤状态指示
                  Row(
                    children: [
                      _buildStepChip('BCState.xml 修改', _bcStateModified),
                      const SizedBox(width: AppTheme.space8),
                      _buildStepChip('BCSessions.xml 修改', _bcSessionsModified),
                      const SizedBox(width: AppTheme.space8),
                      _buildStepChip('Beyond Compare 启动', _bcLaunched),
                    ],
                  ),

                  const SizedBox(height: AppTheme.space16),
                  Row(
                    children: [
                      AppButton.primary(
                        label: _isProcessing ? '正在处理...' : '一键执行修改并启动',
                        icon: Icons.play_arrow,
                        size: AppButtonSize.regular,
                        isLoading: _isProcessing,
                        onPressed: _isProcessing ? null : _modifyBcConfig,
                      ),
                      const SizedBox(width: AppTheme.space8),
                      AppButton.ghost(
                        label: '系统隐私权限设置',
                        icon: Icons.security,
                        size: AppButtonSize.regular,
                        onPressed: _openSystemSettings,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 权限说明提示条
            const AppBanner(
              message: '首次在 macOS 上操作可能需要授予此工具访问 Application Support 文件夹的权限。若遭遇权限阻拦，会自动调用本地终端脚本协助完成。',
              type: AppBannerType.info,
            ),
            const SizedBox(height: AppTheme.space12),

            // 执行日志
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
                          '操作日志',
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
                                '暂无日志记录',
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

  Widget _buildStepChip(String label, bool isDone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDone ? AppTheme.successSubtle : AppTheme.bgInput,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDone ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 12,
            color: isDone ? AppTheme.success : AppTheme.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.fontCaption.copyWith(
              color: isDone ? AppTheme.success : AppTheme.textSecondary,
              fontWeight: isDone ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
