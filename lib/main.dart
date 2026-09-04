import 'package:flutter/material.dart';

import 'services/ai_config_store.dart';
import 'services/launcher_service.dart';
import 'services/settings_store.dart';
import 'shell/app_shell.dart';
import 'shell/settings_dialog.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化统一配置存储与迁移
  await SettingsStore.instance.init();

  // 初始化 AI 平台级配置存储
  await AiConfigStore.instance.init();

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
