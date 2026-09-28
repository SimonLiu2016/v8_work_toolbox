import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'services/ai_config_store.dart';
import 'services/app_paths.dart';
import 'services/launcher_service.dart';
import 'services/privacy_security_service.dart';
import 'services/proxy_settings.dart';
import 'services/scheduled_news_service.dart';
import 'services/settings_store.dart';
import 'services/unattended_service.dart';
import 'shell/app_shell.dart';
import 'tools/network_proxy/services/network_proxy_service.dart';
import 'shell/settings_dialog.dart';
import 'theme/app_theme.dart';
import 'tools/notebook/asset_reminder_service.dart';
import 'tools/notebook/note_database.dart';
import 'tools/notebook/note_store.dart';
import 'tools/notebook/ui/note_editor.dart';
import 'tools/notebook/ui/notebook_page.dart';
import 'tools/ops_tool/ui/ops_tool_main_page.dart';
import 'tools/password/ui/password_page.dart';
import 'tools/private_player/services/media_history_store.dart';
import 'tools/private_player/services/private_storage_manager.dart';

// ---------------------------------------------------------------------------
// 窗口类型与必需服务清单
// ---------------------------------------------------------------------------

/// 窗口类型。与 `desktop_multi_window` 的 `arguments` 对应。
///
/// **新增平台级单例时必须更新对应窗口的 [WindowServices.required] 条目**——
/// 单例状态是进程级的，每个子窗口进程都会完整重跑 `main()`，漏一项的后果是
/// 该功能在子窗口里静默失效（如笔记本子窗口曾因未初始化 AI 配置存储而
/// 报「槽位无可用候选供应商」，而同机主窗口的调用全部正常）。
enum WindowKind {
  /// 主窗口：全部工具与全部平台级服务。
  main,

  /// 笔记本独立窗口（`openInNewWindow`）：富文本编辑 + AI 问答/整理。
  notebook,

  /// 密码工具独立窗口：本地加密密码库，不消费 AI。
  passwordVault,

  /// 单篇笔记独立窗口：仅编辑器，但编辑器可打开资产/整理弹窗，故需要 AI。
  singleNote,

  /// 磐石运维工具独立窗口：DevOps、数据源与报告调度，复用 AI 配置。
  opsTool,
}

/// 按窗口类型声明的必需服务。
///
/// 用一份显式清单取代「每个子窗口分支手写自己需要的 init」，使遗漏在代码审查
/// 与测试中可见。条目内的服务**按拓扑序串行执行**——`ProxySettings.load()` 读
/// `SettingsStore`，`AiConfigStore.init()` 内部初始化 `KeychainService`。
class WindowServices {
  const WindowServices._();

  /// 本地数据路径源必须最先就绪：其余服务（设置、AI 配置、笔记、运维工具）
  /// 全部从 `AppPaths` 派生自己的落盘位置。
  static const List<ServiceInit> _appPaths = [
    ServiceInit('AppPaths', _initAppPaths),
  ];

  static const List<ServiceInit> _settingsStore = [
    ServiceInit('SettingsStore', _initSettingsStore),
  ];

  static const List<ServiceInit> _proxy = [
    ServiceInit('ProxySettings', _initProxySettings),
  ];

  static const List<ServiceInit> _aiConfig = [
    ServiceInit('AiConfigStore', _initAiConfigStore),
  ];

  static const List<ServiceInit> _noteStore = [
    ServiceInit('NoteStore', _initNoteStore),
  ];

  /// 每个窗口类型的必需服务，按依赖拓扑序排列。
  ///
  /// 主窗口包含 [WindowKind.notebook] 与 [WindowKind.singleNote] 的全部条目
  /// （外加自己的独有服务）——主窗口既是所有工具的外壳，也是这些子窗口的超集。
  static Map<WindowKind, List<ServiceInit>> get required => {
    WindowKind.main: [
      ..._appPaths,
      ..._settingsStore,
      ..._proxy,
      ..._aiConfig,
      ..._noteStore,
    ],
    WindowKind.notebook: [
      ..._appPaths,
      ..._settingsStore,
      ..._proxy,
      ..._aiConfig,
      ..._noteStore,
    ],
    WindowKind.passwordVault: [
      ..._appPaths,
    ],
    WindowKind.singleNote: [
      ..._appPaths,
      ..._settingsStore,
      ..._proxy,
      ..._aiConfig,
      ..._noteStore,
    ],
    WindowKind.opsTool: [
      ..._appPaths,
      ..._settingsStore,
      ..._proxy,
      ..._aiConfig,
    ],
  };

  /// 该窗口类型的必需服务名列表（供测试断言清单覆盖）。
  static List<String> requiredNames(WindowKind kind) =>
      required[kind]!.map((s) => s.name).toList();

  /// 按清单初始化指定窗口类型的所有服务。
  ///
  /// 单项失败不阻断 `runApp`（main() 的 fail-soft 契约：任何 init 抛异常都会让
  /// 整个窗口黑屏），但会记录明确的错误信号，使「服务未就绪」可被诊断而非
  /// 表现为下游功能拿到空状态。
  static Future<void> initFor(WindowKind kind) async {
    for (final service in required[kind]!) {
      try {
        await service.init();
      } catch (e, stack) {
        debugPrint(
          '[WindowServices] ${kind.name} 的 $service 初始化失败（窗口继续启动）: $e\n$stack',
        );
      }
    }
  }

  static Future<void> _initAppPaths() => AppPaths.init();
  static Future<void> _initSettingsStore() => SettingsStore.instance.init();
  static Future<void> _initProxySettings() => ProxySettings.instance.load();
  static Future<void> _initAiConfigStore() => AiConfigStore.instance.init();
  static Future<void> _initNoteStore() => NoteStore.instance.init();
}

/// 单个服务的惰性初始化入口。`name` 仅用于诊断与测试断言。
class ServiceInit {
  const ServiceInit(this.name, this.init);

  final String name;
  final Future<void> Function() init;

  @override
  String toString() => name;
}

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

  if (isSubWindow && subWindowArgument == 'password-vault') {
    // 密码工具子窗口：VaultStore 自管加载与 DEK，不消费 AI。
    await WindowServices.initFor(WindowKind.passwordVault);
    runApp(const _PasswordVaultWindowApp());
    return;
  }

  if (isSubWindow && subWindowArgument == 'notebook') {
    await WindowServices.initFor(WindowKind.notebook);
    runApp(const _NotebookWindowApp());
    return;
  }

  if (isSubWindow && subWindowArgument == 'ops-tool') {
    await WindowServices.initFor(WindowKind.opsTool);
    runApp(const _OpsToolWindowApp());
    return;
  }

  if (isSubWindow && subWindowArgument.startsWith('note:')) {
    // Sub-window mode for a single note.
    final noteId = subWindowArgument.substring('note:'.length);
    await WindowServices.initFor(WindowKind.singleNote);
    runApp(_SingleNoteWindowApp(noteId: noteId));
    return;
  }

  // 主窗口：注册窗口焦点监听，用于感知子窗口中的笔记编辑。
  windowManager.addListener(_notebookFocusListener);
  // 主窗口：注册关闭监听，退出前清理 mihomo 进程。
  windowManager.addListener(_mainWindowCloseListener);

  // Main window mode
  MediaKit.ensureInitialized();

  // 主窗口的服务初始化走同一份清单（见 WindowServices.required）。
  await WindowServices.initFor(WindowKind.main);

  // 初始化定时资讯检索与通知调度
  await ScheduledNewsService.instance.init();

  // 初始化笔记本存储与资产到期提醒。
  // 笔记本是资产提醒的依赖，初始化失败时守卫住，不让单个组件故障黑屏。
  try {
    await AssetReminderService.instance.init();
  } catch (e, stack) {
    debugPrint('AssetReminder init failed: $e\n$stack');
  }

  // 初始化无人值守服务状态与代理脚本
  await UnattendedService.instance.init();

  // 初始化内嵌代理管理器（加载持久化状态，若有选中节点则启动 mihomo）
  try {
    await NetworkProxyService.instance.load();
  } catch (e, stack) {
    debugPrint('NetworkProxyService init failed: $e\n$stack');
  }

  // 初始化隐私空间安全服务与私密存储。
  // 密钥/密文异常（DEK 不可用、密文损坏）时保持锁定并继续启动，
  // 不允许单个安全组件的故障黑屏整个应用（异常细节由服务层记录）。
  try {
    await PrivacySecurityService.instance.init();
  } catch (e, stack) {
    debugPrint(
      'PrivacySecurityService init failed, staying locked: $e\n$stack',
    );
  }
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
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
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

/// 密码工具子窗口 app
class _PasswordVaultWindowApp extends StatelessWidget {
  const _PasswordVaultWindowApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '密码工具 - V8 工作工具箱',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: const PasswordPage(),
    );
  }
}

/// 笔记本独立子窗口 app
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
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: const Scaffold(backgroundColor: Colors.white, body: NotebookPage()),
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

/// 主窗口关闭监听：退出前停止 mihomo 子进程，避免孤儿进程。
class _MainWindowCloseListener extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    try {
      await NetworkProxyService.instance.shutdown();
    } catch (_) {}
  }
}

final _mainWindowCloseListener = _MainWindowCloseListener();

/// 单篇笔记子窗口 app：仅渲染目标笔记的编辑器。
class _SingleNoteWindowApp extends StatefulWidget {
  const _SingleNoteWindowApp({required this.noteId});

  final String noteId;

  @override
  State<_SingleNoteWindowApp> createState() => _SingleNoteWindowAppState();
}

class _SingleNoteWindowAppState extends State<_SingleNoteWindowApp> {
  late Future<Note?> _noteFuture;

  /// 资产/关联写入后的最新笔记快照（FutureBuilder 只在首帧用它）。
  Note? _reloadedNote;

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
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.accent,
          surface: Colors.white,
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Padding(
          padding: const EdgeInsets.only(top: 28), // macOS 沉浸式红绿灯避让
          child: FutureBuilder<Note?>(
            future: _noteFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data == null) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.note_outlined, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('笔记不存在或已删除', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              return NoteEditor(
                key: ValueKey(snapshot.data!.id),
                note: _reloadedNote ?? snapshot.data,
                onSaved: () {},
                // 资产/关联写入后刷新编辑器持有的快照，使 chip 反映现值。
                onNoteReloaded: (fresh) {
                  if (!mounted) return;
                  setState(() => _reloadedNote = fresh);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OpsToolWindowApp extends StatelessWidget {
  const _OpsToolWindowApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '磐石运维工具',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.only(top: 28), // macOS 沉浸式红绿灯避让
          child: OpsToolMainPage(),
        ),
      ),
    );
  }
}

