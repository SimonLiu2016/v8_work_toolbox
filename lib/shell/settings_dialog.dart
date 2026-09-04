import 'package:flutter/material.dart';

import '../components/app_components.dart';
import '../services/launcher_service.dart';
import '../services/settings_store.dart';
import '../theme/app_theme.dart';

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
  bool _isRegistering = false;
  String? _statusMessage;
  bool _statusSuccess = true;

  final List<HotKeyConfig> _availableHotKeys = const [
    HotKeyConfig.defaultHotKey,
    HotKeyConfig.ctrlOptK,
    HotKeyConfig.optK,
  ];

  @override
  void initState() {
    super.initState();
    _currentHotKey = SettingsStore.instance.getHotKeyConfig();
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
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(AppTheme.space20),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: AppTheme.borderRadiusMedium,
            border: Border.all(color: AppTheme.borderStrong),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.settings, size: 18, color: AppTheme.accent),
                  const SizedBox(width: AppTheme.space8),
                  const Text('应用设置', style: AppTheme.fontTitle),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: AppTheme.textTertiary,
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space16),
              const Divider(height: 1, color: AppTheme.borderSubtle),
              const SizedBox(height: AppTheme.space16),

              // HotKey Section
              Text(
                '全局唤起快捷键',
                style: AppTheme.fontCaption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTheme.space4),
              Text(
                '在任意应用中按下快捷键可快速呼出或隐藏主窗口',
                style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
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
                        color: isSelected ? AppTheme.bgSelected : AppTheme.bgInput,
                        borderRadius: AppTheme.borderRadiusSmall,
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.accent.withValues(alpha: 0.6)
                              : AppTheme.borderSubtle,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 16,
                            color: isSelected ? AppTheme.accent : AppTheme.textTertiary,
                          ),
                          const SizedBox(width: AppTheme.space12),
                          Text(
                            hk.label,
                            style: AppTheme.fontBody.copyWith(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (hk == HotKeyConfig.defaultHotKey)
                            const AppBadge(label: '默认', color: AppTheme.accentSubtle, textColor: AppTheme.accentLight),
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
              const Divider(height: 1, color: AppTheme.borderSubtle),
              const SizedBox(height: AppTheme.space16),

              // Storage Info
              Text(
                '统一配置存储位置',
                style: AppTheme.fontCaption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTheme.space4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.space8),
                decoration: BoxDecoration(
                  color: AppTheme.bgInput,
                  borderRadius: AppTheme.borderRadiusSmall,
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Text(
                  '~/Library/Application Support/V8WorkToolbox/',
                  style: AppTheme.fontMono.copyWith(fontSize: 11, color: AppTheme.textSecondary),
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
    );
  }
}
