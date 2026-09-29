import 'package:flutter/material.dart';

import '../components/app_components.dart';
import '../services/launcher_service.dart';
import '../services/note_capture_service.dart';
import '../services/settings_store.dart';
import '../theme/app_theme.dart';
import '../tools/notebook/note_database.dart';
import '../tools/notebook/note_store.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late HotKeyConfig _currentHotKey;
  late ThemeMode _currentThemeMode;
  bool _isRegistering = false;
  String? _statusMessage;
  bool _statusSuccess = true;

  final List<HotKeyConfig> _availableHotKeys = const [
    HotKeyConfig.defaultHotKey,
    HotKeyConfig.ctrlOptK,
    HotKeyConfig.optK,
  ];

  List<Notebook> _notebooks = [];
  String? _defaultCaptureNotebookId;

  @override
  void initState() {
    super.initState();
    _currentHotKey = SettingsStore.instance.getHotKeyConfig();
    _currentThemeMode = SettingsStore.instance.themeMode;
    _loadNotebooks();
  }

  Future<void> _applyThemeMode(ThemeMode mode) async {
    setState(() {
      _currentThemeMode = mode;
    });
    await SettingsStore.instance.setThemeMode(mode);
  }

  Future<void> _loadNotebooks() async {
    try {
      final nbs = await NoteStore.instance.allNotebooks();
      final defId = await NoteCaptureService.instance.getDefaultNotebookId();
      if (mounted) {
        setState(() {
          _notebooks = nbs;
          _defaultCaptureNotebookId = defId;
        });
      }
    } catch (_) {}
  }

  Future<void> _applyHotKey(HotKeyConfig config) async {
    setState(() {
      _isRegistering = true;
      _statusMessage = null;
    });

    final success = await LauncherService.instance.registerHotKey(config);

    if (success) {
      await SettingsStore.instance.setHotKeyConfig(config);
      setState(() {
        _currentHotKey = config;
        _isRegistering = false;
        _statusMessage = '全局快捷键已更新并生效';
        _statusSuccess = true;
      });
    } else {
      setState(() {
        _isRegistering = false;
        _statusMessage = '快捷键注册失败：可能已被系统或其他应用占用，请更换其他选项';
        _statusSuccess = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 颜色统一从 ThemeExtension 解析，不在此处维护第二份亮暗映射
    final isDark = context.isDarkMode;
    final colors = context.colors;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 680),
          padding: const EdgeInsets.all(AppTheme.space20),
          decoration: BoxDecoration(
            color: colors.bgCard,
            borderRadius: AppTheme.borderRadiusMedium,
            border: Border.all(color: colors.borderStrong),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        width: 28,
                        height: 28,
                        errorBuilder: (_, __, ___) => Icon(Icons.settings, size: 20, color: context.accentText),
                      ),
                    ),
                    const SizedBox(width: AppTheme.space10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('V8 工作工具箱', style: AppTheme.fontTitle.copyWith(color: colors.textPrimary)),
                        Text('v0.1.0 • 现代开发者多维工作台', style: AppTheme.fontCaption.copyWith(color: colors.textTertiary)),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      color: colors.textTertiary,
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space16),
                Divider(height: 1, color: colors.borderSubtle),
                const SizedBox(height: AppTheme.space16),

                // Theme Section
                Text(
                  '外观与主题',
                  style: AppTheme.fontCaption.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.space4),
                Text(
                  '选择全局界面显示主题，支持跟随系统自动切换',
                  style: AppTheme.fontCaption.copyWith(color: colors.textTertiary),
                ),
                const SizedBox(height: AppTheme.space12),

                Row(
                  children: [
                    _buildThemeOption(
                      mode: ThemeMode.system,
                      label: '跟随系统',
                      icon: Icons.brightness_auto_rounded,
                      isSelected: _currentThemeMode == ThemeMode.system,
                    ),
                    const SizedBox(width: AppTheme.space8),
                    _buildThemeOption(
                      mode: ThemeMode.light,
                      label: '浅色模式',
                      icon: Icons.light_mode_rounded,
                      isSelected: _currentThemeMode == ThemeMode.light,
                    ),
                    const SizedBox(width: AppTheme.space8),
                    _buildThemeOption(
                      mode: ThemeMode.dark,
                      label: '深色模式',
                      icon: Icons.dark_mode_rounded,
                      isSelected: _currentThemeMode == ThemeMode.dark,
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.space16),
                Divider(height: 1, color: colors.borderSubtle),
                const SizedBox(height: AppTheme.space16),


              // HotKey Section
              Text(
                '全局唤起快捷键',
                style: AppTheme.fontCaption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTheme.space4),
              Text(
                '在任意应用中按下快捷键可快速呼出或隐藏主窗口',
                style: AppTheme.fontCaption.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: AppTheme.space12),

              // Hotkey options
              ..._availableHotKeys.map((hk) {
                final isSelected = _currentHotKey == hk;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space8),
                  child: InkWell(
                    onTap: _isRegistering ? null : () => _applyHotKey(hk),
                    borderRadius: AppTheme.borderRadiusSmall,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space12,
                        vertical: AppTheme.space8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? colors.bgSelected : colors.bgInput,
                        borderRadius: AppTheme.borderRadiusSmall,
                        border: Border.all(
                          color: isSelected
                              ? context.accentSolid.withValues(alpha: 0.6)
                              : colors.borderSubtle,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 16,
                            color: isSelected ? context.accentText : colors.textTertiary,
                          ),
                          const SizedBox(width: AppTheme.space12),
                          Text(
                            hk.label,
                            style: AppTheme.fontBody.copyWith(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? (isDark ? Colors.white : context.accentText) : colors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (hk == HotKeyConfig.defaultHotKey)
                            AppBadge(label: '默认', color: context.accentSubtle, textColor: context.accentText),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              if (_statusMessage != null) ...[
                const SizedBox(height: AppTheme.space8),
                AppBanner(
                  message: _statusMessage!,
                  type: _statusSuccess ? AppBannerType.success : AppBannerType.error,
                ),
              ],

              const SizedBox(height: AppTheme.space16),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: AppTheme.space16),

              // Note Capture Section
              Text(
                '外部选区笔记捕获 (⌥S / 右键服务)',
                style: AppTheme.fontCaption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTheme.space4),
              Text(
                '选中文本按下 ⌥S 或通过右键"服务"保存笔记的目标笔记本',
                style: AppTheme.fontCaption.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: AppTheme.space8),
              if (_notebooks.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _defaultCaptureNotebookId,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderSide: BorderSide(color: colors.borderSubtle)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  dropdownColor: colors.bgCard,
                  items: _notebooks
                      .map(
                        (nb) => DropdownMenuItem(
                          value: nb.id,
                          child: Text('${nb.icon} ${nb.name}', style: TextStyle(fontSize: 13, color: colors.textPrimary)),
                        ),
                      )
                      .toList(),
                  onChanged: (val) async {
                    if (val != null) {
                      await NoteCaptureService.instance.setDefaultNotebookId(val);
                      setState(() => _defaultCaptureNotebookId = val);
                    }
                  },
                  hint: Text('选择默认笔记本', style: TextStyle(fontSize: 13, color: colors.textTertiary)),
                )
              else
                Text(
                  '暂无笔记本，请先在笔记本工具中创建',
                  style: AppTheme.fontCaption.copyWith(color: colors.textTertiary),
                ),

              const SizedBox(height: AppTheme.space16),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: AppTheme.space16),

              // Storage Info
              Text(
                '统一配置存储位置',
                style: AppTheme.fontCaption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTheme.space4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.space8),
                decoration: BoxDecoration(
                  color: colors.bgInput,
                  borderRadius: AppTheme.borderRadiusSmall,
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Text(
                  '~/Library/Application Support/V8WorkToolbox/',
                  style: AppTheme.fontMono.copyWith(fontSize: 11, color: colors.textSecondary),
                ),
              ),

              const SizedBox(height: AppTheme.space20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton.primary(
                    label: '完成',
                    size: AppButtonSize.small,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildThemeOption({
    required ThemeMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    final colors = context.colors;
    return Expanded(
      child: InkWell(
        onTap: () => _applyThemeMode(mode),
        borderRadius: AppTheme.borderRadiusSmall,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space10,
            vertical: AppTheme.space10,
          ),
          decoration: BoxDecoration(
            color: isSelected ? colors.bgSelected : colors.bgInput,
            borderRadius: AppTheme.borderRadiusSmall,
            border: Border.all(
              color: isSelected ? context.accentText : colors.borderSubtle,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? context.accentText : colors.textPrimary,
              ),
              const SizedBox(height: AppTheme.space6),
              Text(
                label,
                style: AppTheme.fontCaption.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? context.accentText : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
