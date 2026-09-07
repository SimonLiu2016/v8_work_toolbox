import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'services/ai_config_store.dart';
import 'services/launcher_service.dart';
import 'services/privacy_security_service.dart';
import 'services/settings_store.dart';
import 'tools/private_player/services/media_history_store.dart';
import 'tools/private_player/services/private_storage_manager.dart';
import 'services/unattended_service.dart';
import 'shell/app_shell.dart';
import 'shell/settings_dialog.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 初始化统一配置存储与迁移
  await SettingsStore.instance.init();

  // 初始化 AI 平台级配置存储
  await AiConfigStore.instance.init();

  // 初始化无人值守服务状态与代理脚本
  await UnattendedService.instance.init();

  // 初始化隐私空间安全服务与私密存储
  await PrivacySecurityService.instance.init();
  await PrivateStorageManager.instance.init();
  await MediaHistoryStore.instance.init();

  // 注册全局快捷键
  final hotKey = SettingsStore.instance.getHotKeyConfig();
  await LauncherService.instance.registerHotKey(hotKey);

  runApp(const V8WorkToolboxApp());
}

class V8WorkToolboxApp extends StatelessWidget {
  const V8WorkToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'V8 工作工具箱',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          return AppShell(
            initialRecentToolIds: SettingsStore.instance.getRecentToolIds(),
            onToolUsed: (toolId) {
              SettingsStore.instance.recordToolUsed(toolId);
            },
            onOpenSettings: () {
              SettingsDialog.show(context);
            },
          );
        },
      ),
    );
  }
}
