import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'services/ai_config_store.dart';
import 'services/launcher_service.dart';
import 'services/privacy_security_service.dart';
import 'services/scheduled_news_service.dart';
import 'services/settings_store.dart';
import 'services/unattended_service.dart';
import 'shell/app_shell.dart';
import 'shell/settings_dialog.dart';
import 'theme/app_theme.dart';
import 'tools/notebook/note_database.dart';
import 'tools/notebook/note_store.dart';
import 'tools/notebook/ui/note_editor.dart';
import 'tools/notebook/ui/notebook_page.dart';
import 'tools/private_player/services/media_history_store.dart';
import 'tools/private_player/services/private_storage_manager.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // window_manager 必须在任何子窗口启动前初始化：单篇笔记子窗口的关闭监听、
  // 主窗口的焦点监听都依赖它。初始化失败不应阻断启动。
  try {
    await windowManager.ensureInitialized();
  } catch (e) {
    debugPrint('windowManager.ensureInitialized failed: $e');
  }

  // Check if this is a sub-window by looking at args
  // desktop_multi_window passes ["multi_window", windowId, arguments] for sub-windows
  final isSubWindow = args.isNotEmpty && args.first == 'multi_window';
  final subWindowArgument = isSubWindow && args.length > 2 ? args[2] : '';

  if (isSubWindow && subWindowArgument == 'notebook') {
    // Sub-window mode for notebook.
    try {
      await NoteStore.instance.init();
    } catch (e, stack) {
      debugPrint('Failed to initialize NoteStore in sub-window: $e\n$stack');
    }
    runApp(const _NotebookWindowApp());
    return;
  }

  if (isSubWindow && subWindowArgument.startsWith('note:')) {
    // Sub-window mode for a single note.
    final noteId = subWindowArgument.substring('note:'.length);
    try {
      await NoteStore.instance.init();
    } catch (e, stack) {
      debugPrint('Failed to initialize NoteStore in sub-window: $e\n$stack');
    }
    runApp(_SingleNoteWindowApp(noteId: noteId));
    return;
  }

  // 主窗口：注册窗口焦点监听，用于感知子窗口中的笔记编辑。
  windowManager.addListener(_notebookFocusListener);

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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
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
  const _NotebookWindowApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '笔记本 - V8 工作工具箱',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      home: const Scaffold(
        body: NotebookPage(),
      ),
    );
  }
}

/// 主窗口焦点监听：重新获得焦点时通知笔记本页面刷新列表。
/// 子窗口中的编辑通过同一个 SQLite 文件持久化，焦点驱动刷新即可让
/// 中间列感知最新标题与摘要（见设计文档决策 3）。
class _NotebookWindowFocusListener extends WindowListener {
  @override
  void onWindowFocus() => NotebookFocusBridge.instance.notifyWindowFocused();
}

final _notebookFocusListener = _NotebookWindowFocusListener();


/// 单篇笔记子窗口 app：仅渲染目标笔记的编辑器。
class _SingleNoteWindowApp extends StatefulWidget {
  const _SingleNoteWindowApp({required this.noteId});

  final String noteId;

  @override
  State<_SingleNoteWindowApp> createState() => _SingleNoteWindowAppState();
}

class _SingleNoteWindowAppState extends State<_SingleNoteWindowApp> {
  late Future<Note?> _noteFuture;

  @override
  void initState() {
    super.initState();
    _noteFuture = NoteStore.instance.noteById(widget.noteId);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '笔记 - V8 工作工具箱',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      home: Scaffold(
        body: FutureBuilder<Note?>(
          future: _noteFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data == null) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.note_outlined, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('笔记不存在或已删除'),
                    ],
                  ),
                ),
              );
            }
            return NoteEditor(
              key: ValueKey(snapshot.data!.id),
              note: snapshot.data,
              onSaved: () {},
            );
          },
        ),
      ),
    );
  }
}
