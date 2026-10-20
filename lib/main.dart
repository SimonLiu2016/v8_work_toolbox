import 'dart:async' show runZonedGuarded;
import 'dart:ui' show PlatformDispatcher;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'services/ai_config_store.dart';
import 'services/app_paths.dart';
import 'services/context_services_bridge.dart';
import 'services/launcher_service.dart';
import 'services/local_dictionary_bridge.dart';
import 'services/note_capture_service.dart';
import 'services/privacy_security_service.dart';
import 'tools/artex_engine/services/artex_compose_service.dart';
import 'tools/dola_pool/services/dola_account_store.dart';
import 'tools/dola_pool/services/dola_config_store.dart';
import 'tools/infinite_canvas/services/infinite_canvas_compose_service.dart';
import 'tools/infinite_canvas/services/infinite_canvas_bridge_server.dart';
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
import 'tools/agnes_playground/ui/playground_page.dart';
import 'tools/ai_video_studio/services/studio_preset_store.dart';
import 'tools/ai_video_studio/ui/studio_shell.dart';
import 'tools/notebook/asset_reminder_service.dart';
import 'tools/notebook/note_database.dart';
import 'tools/notebook/note_store.dart';
import 'tools/notebook/ui/note_editor.dart';
import 'tools/notebook/ui/notebook_page.dart';
import 'tools/ops_tool/ui/ops_tool_main_page.dart';
import 'tools/password/ui/password_page.dart';
import 'tools/private_player/services/media_history_store.dart';
import 'tools/private_player/services/private_storage_manager.dart';
import 'tools/security_toolbox/ui/security_toolbox_main_page.dart';

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

  /// 安全工具箱独立窗口：渗透工作流，长任务扫描，复用 AI 配置与代理
  securityToolbox,

  /// AI 短视频工坊独立窗口：长时合成（FFmpeg / 云端图生视频），复用 AI 配置与代理
  aiVideoStudio,

  /// Agnes 试炼场独立窗口：三通道直连调用，复用 AI 配置与代理
  agnesPlayground,
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

  /// Dola 号池：账号元数据 + 能力覆盖配置。
  ///
  /// 必须在任何可能展示号池状态或触发号池出片的窗口里初始化。漏一项的后果
  /// 不是崩溃而是「号池显示为空」——用户以为没配账号，实际是没加载
  /// （spec: 号池数据初始化由应用启动保证）。
  static const List<ServiceInit> _dolaStore = [
    ServiceInit('DolaAccountStore', _initDolaAccountStore),
    ServiceInit('DolaConfigStore', _initDolaConfigStore),
  ];

  /// AI 短视频工坊全局美学风格与时代题材预设库。
  static const List<ServiceInit> _studioPresetStore = [
    ServiceInit('StudioPresetStore', _initStudioPresetStore),
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
      // 主窗口的 AI 配置页有「Dola 号池」tab，必须能读到账号。
      ..._dolaStore,
      ..._studioPresetStore,
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
    WindowKind.securityToolbox: [
      ..._appPaths,
      ..._settingsStore,
      ..._proxy,
      ..._aiConfig,
    ],
    WindowKind.aiVideoStudio: [
      ..._appPaths,
      ..._settingsStore,
      ..._proxy,
      ..._aiConfig,
      // 该窗口的分镜看板可以直接提交视频生成，Dola 是可选引擎之一——
      // 漏了它号池在此窗口显示为空，用户以为没配账号。
      ..._dolaStore,
      ..._studioPresetStore,
    ],
    // 试炼场不需要 Dola 号池：它只调用户自己配的 Agnes 供应商，不像工坊
    // 那样把免费号池当可选引擎。漏列 _aiConfig 才会出问题——那会让供应商
    // 列表为空，用户看不到任何可选型号。
    WindowKind.agnesPlayground: [
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
  static Future<void> _initDolaAccountStore() =>
      DolaAccountStore.instance.init();
  static Future<void> _initDolaConfigStore() =>
      DolaConfigStore.instance.init();
  static Future<void> _initStudioPresetStore() =>
      StudioPresetStore.instance.init();
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

  // 【一次性计时，验证完启动链优化即删】黑屏时长归因用：引擎启动到 runApp
  // 之间每一段各占多少 ms。见 change fix-notebook-window-launch-black-and-size
  // 的 task 1.1/1.2。
  final bootWatch = Stopwatch()..start();
  void bootMark(String label) {
    debugPrint('[boot] $label: +${bootWatch.elapsedMilliseconds}ms');
  }

  if (isSubWindow && subWindowArgument == 'password-vault') {
    // 密码工具子窗口：VaultStore 自管加载与 DEK，不消费 AI。
    await WindowServices.initFor(WindowKind.passwordVault);
    bootMark('password-vault initFor');
    await _sizeSubWindow(const Size(900, 600));
    bootMark('password-vault sized');
    runAppWithErrorHandling(const _PasswordVaultWindowApp());
    bootMark('password-vault runApp');
    return;
  }

  if (isSubWindow && subWindowArgument == 'notebook') {
    bootMark('notebook branch entered');
    await _sizeNotebookSubWindowToWorkArea();
    bootMark('notebook sized');
    await _applyNotebookWindowFallbackBackground();
    bootMark('notebook bg');
    await WindowServices.initFor(WindowKind.notebook);
    bootMark('notebook initFor');
    // 启动链跑完才让窗口可见。窗口是以 hiddenAtLaunch: true 创建的，若不在此
    // 处 show，用户点了「笔记本」会毫无反应。
    await _showNotebookWindowWhenReady();
    bootMark('notebook shown');
    runAppWithErrorHandling(const _NotebookWindowApp());
    bootMark('notebook runApp');
    return;
  }

  if (isSubWindow && subWindowArgument == 'ops-tool') {
    await WindowServices.initFor(WindowKind.opsTool);
    bootMark('ops-tool initFor');
    await _sizeSubWindow(const Size(1200, 800));
    bootMark('ops-tool sized');
    runAppWithErrorHandling(const _OpsToolWindowApp());
    bootMark('ops-tool runApp');
    return;
  }

  if (isSubWindow && subWindowArgument == 'security-toolbox') {
    await WindowServices.initFor(WindowKind.securityToolbox);
    bootMark('security-toolbox initFor');
    await _sizeSubWindow(const Size(1300, 850));
    bootMark('security-toolbox sized');
    runAppWithErrorHandling(const _SecurityToolboxWindowApp());
    bootMark('security-toolbox runApp');
    return;
  }

  if (isSubWindow && subWindowArgument == 'ai-video-studio') {
    // 分镜看板可直接提交视频生成，且资产库有视频预览——该窗口消费多媒体运行时。
    MediaKit.ensureInitialized();
    bootMark('ai-video-studio MediaKit');
    await _sizeSubWindow(const Size(1400, 900));
    bootMark('ai-video-studio sized');
    await WindowServices.initFor(WindowKind.aiVideoStudio);
    bootMark('ai-video-studio initFor');
    runAppWithErrorHandling(const _AiVideoStudioWindowApp());
    bootMark('ai-video-studio runApp');
    return;
  }

  if (isSubWindow && subWindowArgument == 'agnes-playground') {
    await WindowServices.initFor(WindowKind.agnesPlayground);
    bootMark('agnes-playground initFor');
    await _sizeSubWindow(const Size(1100, 800));
    bootMark('agnes-playground sized');
    runAppWithErrorHandling(const _AgnesPlaygroundWindowApp());
    bootMark('agnes-playground runApp');
    return;
  }

  if (isSubWindow && subWindowArgument.startsWith('note:')) {
    // Sub-window mode for a single note.
    final noteId = subWindowArgument.substring('note:'.length);
    await _sizeSubWindow(const Size(900, 650));
    bootMark('single-note sized');
    await WindowServices.initFor(WindowKind.singleNote);
    bootMark('single-note initFor');
    runAppWithErrorHandling(_SingleNoteWindowApp(noteId: noteId));
    bootMark('single-note runApp');
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
    // 查词浮窗刻意不在此处设尺寸：它的 420×520 由 _setupWindowStyle() 在
    // 首帧后自己声明（同时设透明背景与无边框）。见 lookup_window.dart。
    await WindowServices.initFor(WindowKind.lookupPanel);
    bootMark('lookup initFor');
    runAppWithErrorHandling(
      LookupWindowApp(initialQuery: query, initialMode: parseLookupStartMode(mode)),
    );
    bootMark('lookup runApp');
    return;
  }

  // 主窗口：注册窗口焦点监听，用于感知子窗口中的笔记编辑。
  windowManager.addListener(_notebookFocusListener);
  // 主窗口：注册关闭监听，退出前清理 mihomo 进程。
  windowManager.addListener(_mainWindowCloseListener);

  // 主窗口承载私有播放器（嵌入而非独立窗口），多媒体运行时在此初始化。
  MediaKit.ensureInitialized();
  bootMark('main MediaKit');

  // Main window mode
  // 主窗口的服务初始化走同一份清单（见 WindowServices.required）。
  await WindowServices.initFor(WindowKind.main);
  bootMark('main initFor');

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

/// 笔记本子窗口：让窗口在启动链跑完后可见。
///
/// 窗口以 `hiddenAtLaunch: true` 创建（原生侧因此不会 `setIsVisible`），
/// 所以必须由这一侧显式 show，否则用户点了「笔记本」毫无反应。
///
/// 放在 `runApp` **之前**而不是等首帧：`runApp` 返回后首帧还要经过一次
/// 引擎的 build/layout/paint，等它会把可见时机推迟到更晚；而此刻尺寸、
/// 背景色、服务都已就绪，窗口一可见就是终态。spec 要求的是「引擎完成服务
/// 初始化并具备渲染首帧条件之前保持不可见」——此处即该临界点。
///
/// 失败不抛：show 本身失败时窗口确实不会出现，但启动链仍继续走到 runApp
/// （fail-soft 契约），并留下诊断信号。这比让整个窗口打不开好。
///
/// **show 超时兜底**：`windowManager.show()` 走平台通道，若原生侧无响应
/// （窗口控制器未注册等），这个 await 会一直挂着——用户看到的就是「点了
/// 笔记本什么都没发生」。加一道超时：到点后不再等待，让启动链继续走，
/// 并留下诊断信号。窗口最终仍会由原生侧那次 setIsVisible 补上（或由用户
/// 再次点击触发 show），至少不是永久无响应。
Future<void> _showNotebookWindowWhenReady() async {
  try {
    await windowManager.show().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint(
          '[main] 笔记本窗口 show 超时（5s 未响应，启动链继续；'
          '窗口可能延迟可见或不可见）',
        );
      },
    );
  } catch (e) {
    debugPrint('[main] 笔记本窗口 show 失败（窗口可能不可见）: $e');
  }
}

/// 笔记本子窗口：设置引擎绘制前的兜底背景色。
///
/// 引擎尚未绘制任何内容时，NSWindow 的 surface 是黑的。窗口以
/// `hiddenAtLaunch: true` 创建后这段黑不再被用户看到；但 show 失败兜底、
/// 或将来有人改回提前可见时，这个底色就是第二道防线——至少不是纯黑。
///
/// 取当前主题对应的窗口底色，与首帧后 `_NotebookWindowApp` 的
/// `Scaffold` 背景一致，避免可见的色差跳变。
///
/// 只对笔记本窗口调用：查词浮窗的窗口必须保持透明（圆角由 macOS 原生层挖出，
/// 见 `lookup_window.dart` 中 `backgroundColor: Colors.transparent` 的注释），
/// 给它设底色会盖掉透明通道。
Future<void> _applyNotebookWindowFallbackBackground() async {
  try {
    final isDark =
        SettingsStore.instance.themeModeNotifier.value == ThemeMode.dark;
    // 与 AppTheme 的 bgWindow / lightBgWindow 对应（app_theme.dart:12 / :49）。
    await windowManager.setBackgroundColor(
      isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8FAFC),
    );
  } catch (e) {
    debugPrint('[main] 笔记本窗口兜底背景色设置失败: $e');
  }
}

/// 子窗口尺寸声明。
///
/// [size] 由各窗口种类自己决定：查词浮窗是 420×520 的贴口气泡，单篇笔记
/// 900×650，运维工具多面板要 1200×800，密码库 900×600。原生的
/// MainFlutterWindow 原来会把所有子窗口一律 setFrame(screen.visibleFrame)
/// 铺满屏幕，那里现在只管样式；尺寸交给持有着 arguments、知道自己是哪种
/// 窗口的这一侧。
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

/// 从候选显示器中挑出光标所在的那一块；都不匹配时返回 null（由调用方回落主屏）。
///
/// 抽成纯函数是为了可测：窗口 frame 的计算是「不超过屏幕可见工作区」这条
/// spec 的核心，不能因为依赖平台通道就只能靠实机点。
@visibleForTesting
Display? displayContainingPoint(List<Display> displays, Offset point) {
  for (final d in displays) {
    final pos = d.visiblePosition;
    final size = d.visibleSize;
    if (pos == null || size == null) continue;
    if (Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height)
        .contains(point)) {
      return d;
    }
  }
  return null;
}

/// 笔记本子窗口：铺满当前屏幕的可见工作区（排除菜单栏与 Dock）。
///
/// 实现 `notebook-tool` spec 的「Maximizing notebook sub-window on creation」。
/// 该要求自 f2c6c0d 起就在 spec 里，但 ff84105 删掉原生侧无条件
/// setFrame(screen.visibleFrame) 时只留下硬编码 1100×700（占 1680×1050
/// 屏幕的 44%），maximize 一直没有实现。
///
/// 为什么不用 `windowManager.maximize()`：macOS 上它是 `mainWindow.zoom(nil)`，
/// 语义是「在用户尺寸与标准尺寸间切换」而非铺满可见区，且会把窗口置为
/// zoomed 态，用户之后点绿箭头回到一个不可预期的尺寸。
///
/// 【已知限制，多屏不修】`window_manager` 的 `setBounds` 与
/// `screen_retriever` 的 `NSRect.topLeft` 扩展都用 `NSScreen.screens[0]`
/// 换算 y 坐标，而 `windowManager.center()` 走的 `calcWindowPosition` 用光标
/// 所在屏。两条路径的屏幕基准不一致：多显示器用户的窗口会被算到主屏。
/// 修它需 patch 第三方包或改为原生侧实现——见 change
/// fix-notebook-window-launch-black-and-size 的 design open question。
/// 本函数只保证单屏正确。
///
/// 失败不抛：声明失败时窗口仍会打开（包默认 800×600 + 原生 (0,0) 原点），
/// 比让窗口打不开好。
Future<void> _sizeNotebookSubWindowToWorkArea() async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isEmpty) return;

    // 光标所在屏即用户正在看的那块；都不匹配时回落主屏（多屏但光标在
    // 屏幕外等异常情形）。
    final cursor = await screenRetriever.getCursorScreenPoint();
    final current =
        displayContainingPoint(displays, cursor) ?? displays.first;

    // 一次 setBounds 同时定位置与尺寸，避免 setSize 后 center 的中间态。
    await windowManager.setBounds(
      Rect.fromLTWH(
        current.visiblePosition!.dx,
        current.visiblePosition!.dy,
        current.visibleSize!.width,
        current.visibleSize!.height,
      ),
      animate: false,
    );
  } catch (e) {
    debugPrint('[main] 笔记本窗口工作区尺寸声明失败: $e');
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
  // ARTEX 引擎容器：按「退出即停」开关决定是否 stop。该方法只调 compose
  // stop，绝不碰数据卷（spec: 应用退出时的容器处置）。
  try {
    await ArtexComposeService.instance.disposeOnExit();
  } catch (e, stack) {
    debugPrint('[main] ARTEX 引擎清理失败（仍然退出）: $e\n$stack');
  }
  // 无限画布容器：同上，只 stop。它的数据全在浏览器本地，stop 不影响。
  try {
    await InfiniteCanvasComposeService.instance.disposeOnExit();
  } catch (e, stack) {
    debugPrint('[main] 无限画布容器清理失败（仍然退出）: $e\n$stack');
  }
  // 资产桥 loopback 服务：退出时关掉，避免孤儿进程持有端口（与本地词典桥
  // 同一类问题）。
  try {
    await InfiniteCanvasBridgeServer.instance.stop();
  } catch (e, stack) {
    debugPrint('[main] 资产桥服务清理失败（仍然退出）: $e\n$stack');
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

class _SecurityToolboxWindowApp extends StatelessWidget {
  const _SecurityToolboxWindowApp();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: '安全工具箱',
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
              child: SecurityToolboxMainPage(),
            ),
          ),
        );
      },
    );
  }
}

/// Agnes 试炼场独立子窗口 app。
class _AgnesPlaygroundWindowApp extends StatelessWidget {
  const _AgnesPlaygroundWindowApp();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: 'Agnes 试炼场',
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
              child: PlaygroundPage(),
            ),
          ),
        );
      },
    );
  }
}

/// AI 短视频工坊独立子窗口 app。
class _AiVideoStudioWindowApp extends StatelessWidget {
  const _AiVideoStudioWindowApp();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: 'AI 短视频工坊',
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
              child: StudioShellPage(),
            ),
          ),
        );
      },
    );
  }
}


