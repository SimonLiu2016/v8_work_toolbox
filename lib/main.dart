import 'dart:async' show runZonedGuarded;
import 'dart:ui' show PlatformDispatcher;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'services/ai_config_store.dart';
import 'services/app_paths.dart';
import 'services/context_services_bridge.dart';
import 'services/launcher_service.dart';
import 'services/local_dictionary_bridge.dart';
import 'services/note_capture_service.dart';
import 'services/privacy_security_service.dart';
import 'tools/lookup_panel/ui/lookup_window.dart';
import 'tools/vocab_book/services/vocab_store.dart';
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

  /// 查词独立浮窗：轻量词典查询、发音与 AI 深度解析
  lookupPanel,
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
      // 该窗口渲染 themed MaterialApp，必须能读到持久化的 themeMode；
      // 缺了它 themeModeNotifier 会停在 ThemeMode.system，暗色偏好静默失效。
      ..._settingsStore,
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
    WindowKind.lookupPanel: [
      ..._appPaths,
      ..._settingsStore,
      ..._proxy,
      ..._aiConfig,
      ..._noteStore,
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

/// 带全局错误兜底的 runApp。
///
/// 历史上六个窗口入口都是裸 `runApp(...)`：任何从 `onPressed` 之类回调里逃逸的
/// async 异常会被静默吞掉——用户侧表现是"点了按钮没反应、也没有任何日志"
/// （笔记本「导入文档」缺 entitlement 时就正是如此）。
///
/// 三层兜底：
///   1. `runZonedGuarded` 接住未捕获的 async 异常；
///   2. `FlutterError.onError` 接住 framework 层的 build/layout 错误；
///   3. `PlatformDispatcher.instance.onError` 接住平台层未捕获错误。
/// release 下都要落到 stderr，开发期另走 debugPrint。
void runAppWithErrorHandling(Widget app) {
  runZonedGuarded(() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[未捕获 FlutterError] ${details.exceptionAsString()}');
      if (details.stack != null) {
        debugPrint(details.stack.toString());
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[未捕获平台错误] $error');
      debugPrint(stack.toString());
      return true;
    };
    runApp(app);
  }, (error, stack) {
    debugPrint('[未捕获异常] $error');
    debugPrint(stack.toString());
  });
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
    await _sizeSubWindow(const Size(900, 600));
    runAppWithErrorHandling(const _PasswordVaultWindowApp());
    return;
  }

  if (isSubWindow && subWindowArgument == 'notebook') {
    await WindowServices.initFor(WindowKind.notebook);
    await _sizeSubWindow(const Size(1100, 700));
    runAppWithErrorHandling(const _NotebookWindowApp());
    return;
  }

  if (isSubWindow && subWindowArgument == 'ops-tool') {
    await WindowServices.initFor(WindowKind.opsTool);
    await _sizeSubWindow(const Size(1200, 800));
    runAppWithErrorHandling(const _OpsToolWindowApp());
    return;
  }

  if (isSubWindow && subWindowArgument.startsWith('note:')) {
    // Sub-window mode for a single note.
    final noteId = subWindowArgument.substring('note:'.length);
    await WindowServices.initFor(WindowKind.singleNote);
    await _sizeSubWindow(const Size(900, 650));
    runAppWithErrorHandling(_SingleNoteWindowApp(noteId: noteId));
    return;
  }

  if (isSubWindow && subWindowArgument.startsWith('lookup:')) {
    // arguments 形态是 'lookup:<mode>:<query>'，mode 缺省视为 dict。
    // 旧版本只写 'lookup:<query>'，所以 split 后要能两种都认。
    final rest = subWindowArgument.substring('lookup:'.length);
    final splitAt = rest.indexOf(':');
    final hasMode = splitAt > 0 && (rest.startsWith('dict:') || rest.startsWith('ai:'));
    final mode = hasMode ? rest.substring(0, splitAt) : 'dict';
    final query = hasMode ? rest.substring(splitAt + 1) : rest;
    await WindowServices.initFor(WindowKind.lookupPanel);
    runAppWithErrorHandling(
      LookupWindowApp(initialQuery: query, initialMode: parseLookupStartMode(mode)),
    );
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

  // 进程级终止信号：与 [_MainWindowCloseListener] 收敛到同一清理逻辑。
  // `onWindowClose` 只在窗口关闭时触发，`kill -TERM` 不会触发它——这正是
  // 历史上 mihomo 子进程反复变成 PPID=1 孤儿的根因。清理失败不阻止退出。
  ProcessSignal.sigterm.watch().listen((_) => runShutdownCleanup());

  // 初始化上下文服务桥接（macOS Services + 热键）
  ContextServicesBridge.instance.init();
  ContextServicesBridge.instance.onLookup = (text, mode) {
    debugPrint('[Bridge] lookup: $text (mode: $mode)');
    // 深链带来的 mode 决定首屏走哪条路：'ai' 直接问 AI，其余词典优先。
    LookupWindowLauncher.open(
      text,
      mode: parseLookupStartMode(mode),
    );
  };

  ContextServicesBridge.instance.onAddToVocab = (text) {
    debugPrint('[Bridge] addToVocab: $text');
    _addWordToVocabFromBridge(text);
  };
  ContextServicesBridge.instance.onSaveNote = ({
    required text,
    required html,
    required sourceApp,
    url,
    title,
  }) async {
    debugPrint('[Bridge] saveNote from $sourceApp: ${text.length} chars');
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      await NoteCaptureService.instance.captureNote(
        text: text,
        html: html,
        sourceApp: sourceApp,
        context: ctx,
        directUrl: url,
        directTitle: title,
      );
    }
  };

  // 启动本地词典桥（浏览器伴侣扩展经此查询词典）。端口被占等故障只记诊断
  // 信号，不阻断启动——热键、macOS Services、深度链接三条查词路径都不依赖它
  // （spec: local-dictionary-bridge「桥故障不得影响宿主应用」）。
  try {
    await LocalDictionaryBridge.instance.start();
  } catch (e, stack) {
    debugPrint('[main] 本地词典桥启动异常（查词浮窗不受影响）: $e\n$stack');
  }

  runAppWithErrorHandling(const V8WorkToolboxApp());
}

/// 子窗口尺寸声明。
///
/// [size] 由各窗口种类自己决定：查词浮窗是 420×520 的贴口气泡，单篇笔记
/// 900×650，笔记本克隆主窗口的 1100×700，运维工具多面板要 1200×800，
/// 密码库 900×600。原生的 MainFlutterWindow 原来会把所有子窗口一律
/// setFrame(screen.visibleFrame) 铺满屏幕，那里现在只管样式；尺寸交给
/// 持有着 arguments、知道自己是哪种窗口的这一侧。
///
/// 失败不抛：窗口尺寸声明失败时窗口仍会打开（用包默认的 800×600），
/// 比让窗口打不开好。
Future<void> _sizeSubWindow(Size size) async {
  try {
    await windowManager.setSize(size, animate: false);
    await windowManager.center();
  } catch (e) {
    debugPrint('[main] 子窗口尺寸声明失败: $e');
  }
}

/// 从浏览器深链来的加生词请求。
///
/// 不开窗口、不查词典 —— 用户点的就是「加入词本」，那本该只是个数据写入。
/// 判重靠 [VocabStore.existsWord]：重复点击不该产生重复词条。
///
/// 注意本函数运行在主窗口进程，而生词本页面也在主窗口里；浮窗进程写库后
/// 页面不刷新的问题由 `refresh-vocab-book-on-window-focus` 负责，不在这里
/// 顺手解决——那是另一个 change 的范围。
Future<void> _addWordToVocabFromBridge(String text) async {
  final word = text.trim();
  if (word.isEmpty) return;
  try {
    if (await VocabStore.instance.existsWord(word)) {
      debugPrint("[Bridge] addToVocab: '$word' 已在生词本，跳过");
      return;
    }
    await VocabStore.instance.insertFromDictionary(
      word: word,
      definitions: const [],
      examples: const [],
    );
    debugPrint("[Bridge] addToVocab: '$word' 已加入生词本");
  } catch (e, stack) {
    debugPrint('[Bridge] addToVocab 失败 ($word): $e\n$stack');
  }
}

/// 主应用全局导航 Key，供平台服务在需要时弹出对话框
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 测试注入点：替代 `exit()`，使清理路径可在测试中驱动而不终止 test runner。
/// 生产代码始终为 null（走真实 `exit(0)`）。
@visibleForTesting
void Function(int code)? exitOverride;

/// SIGTERM / 测试共用的清理逻辑本体。[forTest] 为 true 时不调用 `exit()`——
/// 测试进程只要调用 `exit()`，flutter_tester 就以 "Shell subprocess ended
/// cleanly" 判负（实测 3 个用例全部 did not complete）。生产路径
/// [forTest] = false，行为即真实退出。
@visibleForTesting
Future<void> runShutdownCleanup({bool forTest = false}) async {
  // 守卫说明：清理抛异常时仍必须退出——信号方已要求进程终止，卡在清理上
  // 会让子进程继续存活，比放弃清理更糟（spec: cleanup failure MUST NOT
  // block exit）。
  try {
    await NetworkProxyService.instance.shutdown();
  } catch (e, stack) {
    debugPrint('[main] SIGTERM 清理失败（仍然退出）: $e\n$stack');
  }
  // 本地词典桥：不关就会留下孤儿监听持有端口，下次启动只能落在 fail-soft
  // 分支上（与 mihomo 子进程同一类问题，故并入同一清理函数）。
  try {
    await LocalDictionaryBridge.instance.stop();
  } catch (e, stack) {
    debugPrint('[main] 本地词典桥关闭失败（仍然退出）: $e\n$stack');
  }
  if (forTest) {
    exitOverride?.call(0);
    return;
  }
  exit(0);
}

/// SIGTERM 清理入口，测试可直接调用（真实信号会杀死测试进程自身，故不通过
/// `ProcessSignal` 发送）。
@visibleForTesting
Future<void> gracefulShutdownForTesting() => runShutdownCleanup(forTest: true);

/// Main app
class V8WorkToolboxApp extends StatelessWidget {
  const V8WorkToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'V8 工作工具箱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentThemeMode,
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
      },
    );
  }
}

/// 密码工具子窗口 app
class _PasswordVaultWindowApp extends StatelessWidget {
  const _PasswordVaultWindowApp();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: '密码工具 - V8 工作工具箱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentThemeMode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          home: const PasswordPage(),
        );
      },
    );
  }
}

/// 笔记本独立子窗口 app
class _NotebookWindowApp extends StatelessWidget {
  const _NotebookWindowApp();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: '笔记本 - V8 工作工具箱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentThemeMode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          home: const Scaffold(body: NotebookPage()),
        );
      },
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

/// 主窗口关闭监听：退出前停止 mihomo 子进程与本地词典桥，避免孤儿进程/端口。
class _MainWindowCloseListener extends WindowListener {
  @override
  Future<void> onWindowClose() async {
    try {
      await NetworkProxyService.instance.shutdown();
    } catch (_) {}
    try {
      await LocalDictionaryBridge.instance.stop();
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: '笔记 - V8 工作工具箱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentThemeMode,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          home: Scaffold(
            backgroundColor: context.bgWindow,
            body: Padding(
              padding: const EdgeInsets.only(top: 28), // macOS 沉浸式红绿灯避让
              child: FutureBuilder<Note?>(
                future: _noteFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data == null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.note_outlined, size: 40, color: context.textTertiary),
                          const SizedBox(height: 8),
                          Text('笔记不存在或已删除',
                              style: TextStyle(color: context.textSecondary)),
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
      },
    );
  }
}

class _OpsToolWindowApp extends StatelessWidget {
  const _OpsToolWindowApp();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: '磐石运维工具',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentThemeMode,
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
      },
    );
  }
}

