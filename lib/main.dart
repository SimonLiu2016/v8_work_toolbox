import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'services/ai_config_store.dart';
import 'services/launcher_service.dart';
import 'services/privacy_security_service.dart';
import 'services/scheduled_news_service.dart';
import 'services/settings_store.dart';
import 'tools/notebook/ui/notebook_page.dart';
import 'tools/notebook/note_store.dart';
import 'tools/private_player/services/media_history_store.dart';
import 'tools/private_player/services/private_storage_manager.dart';
import 'services/unattended_service.dart';
import 'shell/app_shell.dart';
import 'shell/settings_dialog.dart';
import 'theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if this is a sub-window
  if (args.firstOrNull == 'multi_window') {
    // Sub-window mode
    final windowId = int.parse(args[1]);
    final argument = args.length > 2 ? args[2] : '';

    if (argument == 'notebook') {
      // Initialize notebook store
      await NoteStore.instance.init();

      runApp(_NotebookWindowApp(windowId: windowId));
      return;
    }
  }

  // Main window mode
  MediaKit.ensureInitialized();

  // 初始化统一配置存储与迁移
  await SettingsStore.instance.init();

  // 初始化 AI 平台级配置存储
  await AiConfigStore.instance.init();

  // 初始化定时资讯检索与通知调度
  await ScheduledNewsService.instance.init();

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

/// Main app
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

/// Notebook sub-window app
class _NotebookWindowApp extends StatelessWidget {
  final int windowId;

  const _NotebookWindowApp({required this.windowId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '笔记本 - V8 工作工具箱',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const Scaffold(
        body: NotebookPage(),
      ),
    );
  }
}
