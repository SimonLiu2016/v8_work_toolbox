import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components/app_components.dart';
import 'theme/app_theme.dart';

class AppShortcutToolPage extends StatefulWidget {
  const AppShortcutToolPage({super.key});

  @override
  State<AppShortcutToolPage> createState() => _AppShortcutToolPageState();
}

class _AppShortcutToolPageState extends State<AppShortcutToolPage> {
  final TextEditingController _appNameController = TextEditingController();
  final TextEditingController _savePathController = TextEditingController();

  String _targetAppName = '';
  String _savePath = '';
  bool _isLoading = false;
  String _statusMessage = '请输入目标应用名称并选择保存目录';
  AppBannerType _statusType = AppBannerType.info;
  List<Map<String, String>> _shortcuts = [];

  static const platform = MethodChannel('app_manager_channel');

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _appNameController.dispose();
    _savePathController.dispose();
    super.dispose();
  }

  Future<void> _selectAppFromList() async {
    try {
      final runningApps = await _getRunningApps();
      if (!mounted) return;
      if (runningApps.isEmpty) {
        setState(() {
          _statusMessage = '没有找到正在运行的应用，请确保目标应用已启动';
          _statusType = AppBannerType.warning;
        });
        return;
      }

      final selectedApp = await showDialog<String>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (BuildContext context) {
          String filter = '';
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final filtered = runningApps.where((app) {
                final name = (app['name'] ?? '').toLowerCase();
                final bundle = (app['bundleId'] ?? '').toLowerCase();
                final q = filter.toLowerCase();
                return name.contains(q) || bundle.contains(q);
              }).toList();

              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 520,
                    height: 480,
                    padding: const EdgeInsets.all(AppTheme.space16),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderStrong),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.apps, size: 18, color: AppTheme.accent),
                            const SizedBox(width: AppTheme.space8),
                            const Text('选择运行中的应用', style: AppTheme.fontTitle),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              color: AppTheme.textTertiary,
                              splashRadius: 14,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.space12),
                        AppTextField(
                          hintText: '过滤应用名称或 Bundle ID...',
                          prefixIcon: const Icon(Icons.search, size: 14, color: AppTheme.textTertiary),
                          onChanged: (val) {
                            setDialogState(() => filter = val);
                          },
                        ),
                        const SizedBox(height: AppTheme.space12),
                        const Divider(height: 1, color: AppTheme.borderSubtle),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Text(
                                    '无匹配应用',
                                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1, color: AppTheme.borderSubtle),
                                  itemBuilder: (context, index) {
                                    final app = filtered[index];
                                    return AppListItem(
                                      title: app['name'] ?? '',
                                      subtitle: 'Bundle ID: ${app['bundleId'] ?? ''}',
                                      trailing: Text(
                                        app['executableName'] ?? '',
                                        style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                                      ),
                                      onTap: () => Navigator.pop(context, app['name']),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (selectedApp != null) {
        setState(() {
          _targetAppName = selectedApp;
          _appNameController.text = selectedApp;
        });
      }
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = '获取应用列表时发生错误: "${e.message}"';
        _statusType = AppBannerType.error;
      });
    }
  }

  Future<void> _selectSavePath() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择快捷键导出文件保存目录',
    );
    if (selectedDirectory != null) {
      setState(() {
        _savePath = selectedDirectory;
        _savePathController.text = selectedDirectory;
      });
    }
  }

  Future<void> _extractShortcuts() async {
    if (_targetAppName.isEmpty) {
      setState(() {
        _statusMessage = '请输入或选择目标应用名称';
        _statusType = AppBannerType.warning;
      });
      return;
    }

    if (_savePath.isEmpty) {
      setState(() {
        _statusMessage = '请选择快捷键导出保存目录';
        _statusType = AppBannerType.warning;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '正在通过系统 Accessibility 提取快捷键信息...';
      _statusType = AppBannerType.info;
      _shortcuts.clear();
    });

    try {
      await Future.delayed(const Duration(seconds: 1));
      final shortcuts = await _getAppShortcuts(_targetAppName);

      setState(() {
        _shortcuts = shortcuts;
      });

      if (shortcuts.isNotEmpty) {
        await _saveShortcutsToFile(shortcuts);
        setState(() {
          _statusMessage = '成功提取 ${shortcuts.length} 个快捷键，并已导出至: $_savePath';
          _statusType = AppBannerType.success;
        });
      } else {
        final lower = _targetAppName.toLowerCase();
        final isSecurityRestricted = lower.contains('iterm') ||
            lower.contains('terminal') ||
            lower.contains('console') ||
            lower.contains('password') ||
            lower.contains('keychain') ||
            lower.contains('encrypt');

        setState(() {
          if (isSecurityRestricted) {
            _statusMessage =
                '未找到 "$_targetAppName" 的快捷键信息。该应用可能因系统安全限制阻止了外部辅助功能读取菜单。';
          } else {
            _statusMessage =
                '未找到应用 "$_targetAppName" 的快捷键，请确保应用已启动运行且辅助功能权限已授予。';
          }
          _statusType = AppBannerType.warning;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '提取发生异常: $e';
        _statusType = AppBannerType.error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<Map<String, String>>> _getRunningApps() async {
    try {
      final result = await platform.invokeMethod('getRunningApps');
      if (result != null && result is List) {
        final List<Map<String, String>> apps = [];
        for (final item in result) {
          if (item is Map) {
            apps.add({
              'name': (item['name'] as String?) ?? '',
              'bundleId': (item['bundleId'] as String?) ?? '',
              'executableName': (item['executableName'] as String?) ?? '',
            });
          }
        }
        return apps;
      }
      return [];
    } on PlatformException catch (e) {
      debugPrint('获取运行应用时发生错误: "${e.message}"');
      return [];
    }
  }

  Future<List<Map<String, String>>> _getAppShortcuts(String appName) async {
    try {
      final result = await platform.invokeMethod('getAppShortcuts', {
        'appName': appName,
      });

      if (result != null && result is List<dynamic>) {
        return result.map((item) {
          final mapItem = item as Map<Object?, Object?>;
          return {
            'description': (mapItem['description'] as String?)?.toString() ?? '',
            'shortcut': (mapItem['shortcut'] as String?)?.toString() ?? '',
            'category': (mapItem['category'] as String?)?.toString() ?? appName,
          };
        }).toList();
      }
      return [];
    } on PlatformException catch (e) {
      debugPrint('获取快捷键出错: "${e.message}"');
      return [];
    }
  }

  Future<void> _saveShortcutsToFile(List<Map<String, String>> shortcuts) async {
    final fileName = '${_targetAppName.replaceAll(' ', '_')}_shortcuts.txt';
    final fullPath = '$_savePath/$fileName';

    final buffer = StringBuffer();
    for (final s in shortcuts) {
      final description = s['description'] ?? '';
      final shortcutKey = s['shortcut'] ?? '';
      final category = s['category'] ?? _targetAppName;
      buffer.writeln('$description|$shortcutKey|$category');
    }

    final file = File(fullPath);
    await file.writeAsString(buffer.toString());
  }

  void _clearResults() {
    setState(() {
      _shortcuts.clear();
      _statusMessage = '已清空结果';
      _statusType = AppBannerType.info;
    });
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
                const Icon(Icons.keyboard, size: 22, color: AppTheme.accent),
                const SizedBox(width: AppTheme.space8),
                const Text('应用快捷键获取', style: AppTheme.fontHeadline),
                const Spacer(),
                if (_shortcuts.isNotEmpty)
                  AppBadge(
                    label: '已提取 ${_shortcuts.length} 项',
                    color: AppTheme.accentSubtle,
                    textColor: AppTheme.accentLight,
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              '通过 macOS 辅助功能接口提取运行中应用的全部菜单快捷键并导出为文本',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space16),

            // 操作配置卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _appNameController,
                          label: '目标应用名称',
                          hintText: '如：Finder、Safari、Visual Studio Code',
                          onChanged: (val) => _targetAppName = val.trim(),
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '从列表选择',
                          icon: Icons.list_alt,
                          size: AppButtonSize.regular,
                          onPressed: _selectAppFromList,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space12),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _savePathController,
                          label: '导出保存路径',
                          hintText: '点击右侧按钮选择保存目录',
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: AppTheme.space8),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: AppButton.secondary(
                          label: '选择目录',
                          icon: Icons.folder_open,
                          size: AppButtonSize.regular,
                          onPressed: _selectSavePath,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space16),
                  Row(
                    children: [
                      AppButton.primary(
                        label: '开始提取快捷键',
                        icon: Icons.download_outlined,
                        size: AppButtonSize.regular,
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _extractShortcuts,
                      ),
                      const SizedBox(width: AppTheme.space8),
                      if (_shortcuts.isNotEmpty)
                        AppButton.ghost(
                          label: '清空结果',
                          icon: Icons.delete_outline,
                          size: AppButtonSize.regular,
                          onPressed: _clearResults,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space12),

            // 状态提示条
            if (_statusMessage.isNotEmpty)
              AppBanner(
                message: _statusMessage,
                type: _statusType,
              ),

            const SizedBox(height: AppTheme.space12),

            // 快捷键预览列表
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: AppTheme.borderRadiusMedium,
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: _shortcuts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.keyboard_outlined, size: 36, color: AppTheme.textDisabled),
                            const SizedBox(height: AppTheme.space8),
                            Text(
                              '暂无提取结果',
                              style: AppTheme.fontBody.copyWith(color: AppTheme.textTertiary),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.space16,
                              AppTheme.space12,
                              AppTheme.space16,
                              AppTheme.space8,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '快捷键列表 (${_shortcuts.length} 项)',
                                  style: AppTheme.fontTitle.copyWith(fontSize: 13),
                                ),
                                const Spacer(),
                                Text(
                                  '格式: 功能描述 | 键位 | 菜单分类',
                                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: AppTheme.borderSubtle),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.space8,
                                vertical: AppTheme.space4,
                              ),
                              itemCount: _shortcuts.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, color: AppTheme.borderSubtle),
                              itemBuilder: (context, index) {
                                final s = _shortcuts[index];
                                final shortcutKey = s['shortcut'] ?? '';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.space8,
                                    vertical: AppTheme.space6,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          s['description'] ?? '',
                                          style: AppTheme.fontBody,
                                        ),
                                      ),
                                      const SizedBox(width: AppTheme.space8),
                                      if (shortcutKey.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.bgInput,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppTheme.borderStrong),
                                          ),
                                          child: Text(
                                            shortcutKey,
                                            style: AppTheme.fontMono.copyWith(
                                              color: AppTheme.accentLight,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: AppTheme.space16),
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          s['category'] ?? '',
                                          style: AppTheme.fontCaption.copyWith(
                                            color: AppTheme.textTertiary,
                                          ),
                                          textAlign: TextAlign.right,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
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
          ],
        ),
      ),
    );
  }
}
