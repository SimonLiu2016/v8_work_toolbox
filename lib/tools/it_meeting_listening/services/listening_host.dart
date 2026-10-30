/// 主进程侧的"宿主"：持有播放控制器、素材库与迷你窗句柄。
///
/// **播放状态在主进程**（design D7）：迷你窗是独立 Dart isolate，只渲染
/// 状态 + 发指令。宿主是这个状态的唯一持有者，全局热键也走这里。
library;

import 'dart:async';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../models/listening_models.dart';
import 'clip_library.dart';
import 'it_listening_mini_bridge.dart';
import 'listening_hot_key_service.dart';
import 'listening_player_controller.dart';
import 'listening_progress_store.dart';
import 'pronunciation_audio_backend.dart';
import 'resume_recorder.dart';
import 'vocabulary_list_player_controller.dart';
import 'vocabulary_study_store.dart';

/// 迷你播放窗的 `arguments` 前缀。
///
/// 主进程用它在已开窗口里认出"这是迷你窗"，从而前置而不是重复创建。
/// 子窗口侧按 `startsWith` 判断，所以后面可以追加标识（例如播放会话 id）
/// 而不破坏识别。
const String kItListeningWindowArgPrefix = 'it-listening-mini';

/// 迷你窗的播放模式。
///
/// `clip` 播放会议片段（显示场景/标题/进度/变速）；`vocab` 顺序朗读词汇列表
/// （显示「词汇」/当前词/词序，无变速）。两模式互斥。
enum MiniPlaybackMode {
  /// 会议片段播放（现有行为）。
  clip,

  /// 词汇列表磨耳朵。
  vocab,
}

/// 主进程宿主。
class ListeningHost {
  ListeningHost._();
  static final ListeningHost instance = ListeningHost._();

  ClipLibrary? _library;
  ClipIndex _index = const ClipIndex();

  /// 播放控制器。**由 host 惰性创建，进程生命周期内不释放**——
  /// 它是主进程唯一的播放状态来源（迷你窗与全局热键都指向它），
  /// 释放它等于让所有视图失去状态。
  ListeningPlayerController? _controller;

  /// 应用生命周期监听：退后台/退出请求时立即落盘播放进度。
  AppLifecycleListener? _lifecycleListener;

  /// 迷你窗的窗口控制器（未打开时为 null）。
  WindowController? _miniWindow;

  /// 迷你窗的窗口 id（用于定位）。
  String? _miniWindowId;

  /// 迷你窗当前激活的播放模式（`clip` 为片段，`vocab` 为词汇磨耳朵）。
  ///
  /// 迷你窗与全局热键都按它分流指令；两模式互斥，由宿主负责切换时停掉另一方。
  MiniPlaybackMode _mode = MiniPlaybackMode.clip;

  /// 词汇列表播放控制器（惰性创建，进程内不释放）。
  ///
  /// 词汇播放与片段播放互斥：词汇模式激活时片段 controller 暂停，
  /// 片段播放启动时词汇 controller 停止。
  VocabularyListPlayerController? _vocabPlayer;

  /// 待重放的请求（从术语本跳回某个片段的指定时间点）。
  ///
  /// 术语本是主窗口里的另一个工具页，它没法直接驱动听力工具的播放器——
  /// 它把「要听哪一段」记在这里，听力工具页在下次构建时消费它。
  ({String clipId, int offsetMs})? pendingReplay;

  /// 取出并清空待重放请求。
  ({String clipId, int offsetMs})? takePendingReplay() {
    final p = pendingReplay;
    pendingReplay = null;
    return p;
  }

  /// 素材库。
  ClipLibrary get library =>
      _library ??= ClipLibrary(AppPaths.itMeetingListeningDir);

  /// 当前索引。
  ClipIndex get index => _index;

  /// 播放控制器（惰性创建）。
  ListeningPlayerController get controller {
    final existing = _controller;
    if (existing != null) return existing;
    final created = ListeningPlayerController(
      recorder: ResumeRecorder(
        store: ListeningProgressStore(AppPaths.itMeetingListeningProgressFile),
      ),
      defaultFilePathFor: _pathFor,
      onError: (msg) => debugPrint('[ListeningHost] 播放错误: $msg'),
    );
    created.addListener(_onClipControllerChanged);
    _controller = created;
    _ensureLifecycleListener();
    return created;
  }

  /// 片段控制器变化：先做互斥（片段开始播放时停词汇），再推状态。
  ///
  /// 主窗口的播放按钮直接调 `controller.play()`，不经迷你窗指令或热键——
  /// 若只在指令入口做互斥，从主窗口播片段时词汇会继续发声。这里从控制器侧
  /// 兜住，保证任何片段播放路径都会停掉词汇。
  void _onClipControllerChanged() {
    if (_mode == MiniPlaybackMode.vocab && _controller?.isPlaying == true) {
      unawaited(deactivateVocabPlayback());
      return;
    }
    _pushStateToMini();
  }

  /// 当前控制器的断点记录器。
  ResumeRecorder get recorder => controller.recorder;

  /// 词汇列表播放控制器（惰性创建，进程内不释放）。
  ///
  /// 默认复用 [VocabularyStudyStore] 默认基目录（同一 `vocab_tts_cache/` 磁盘缓存，
  /// 对话框播过的词零合成延迟）与 [AudioplayersPronunciationBackend]。
  VocabularyListPlayerController get vocabPlayer {
    final existing = _vocabPlayer;
    if (existing != null) return existing;
    final created = VocabularyListPlayerController(
      studyStore: VocabularyStudyStore(),
      backend: AudioplayersPronunciationBackend(),
    );
    created.addListener(_pushStateToMini);
    _vocabPlayer = created;
    return created;
  }

  /// 当前迷你窗激活的播放模式。
  MiniPlaybackMode get playbackMode => _mode;

  void _ensureLifecycleListener() {
    if (_lifecycleListener != null) return;
    try {
      // 仅在 WidgetsBinding 已初始化的环境下注册。
      WidgetsBinding.instance;
      _lifecycleListener = AppLifecycleListener(
        onInactive: () => unawaited(_controller?.flushProgress()),
        onPause: () => unawaited(_controller?.flushProgress()),
        onDetach: () => unawaited(_controller?.flushProgress()),
        onExitRequested: () async {
          await _controller?.flushProgress();
          return AppExitResponse.exit;
        },
      );
    } catch (_) {
      // 某些纯 Dart 单测未初始化 WidgetsBinding，忽略即可。
    }
  }

  /// 索引是否已预置（测试注入）。
  bool _indexPreloaded = false;

  /// 载入索引。
  ///
  /// 若索引已被预置（测试注入），直接返回——**不再读磁盘**。
  /// 这不只是为了快：widget 测试跑在 FakeAsync 里，真实的文件 IO 在那里
  /// 永不完成，页面会永远停在 loading 态。
  Future<ClipIndex> loadIndex() async {
    if (_indexPreloaded) return _index;
    _index = await library.loadIndex();
    return _index;
  }

  /// 预置索引（测试注入点）。
  @visibleForTesting
  void setIndexForTesting(ClipIndex index) {
    _index = index;
    _indexPreloaded = true;
  }

  /// 替换播放控制器（测试注入点）。
  @visibleForTesting
  void setControllerForTesting(ListeningPlayerController? controller) {
    _controller?.removeListener(_onClipControllerChanged);
    if (controller != null) {
      controller.addListener(_onClipControllerChanged);
    }
    _controller = controller;
  }

  /// 替换词汇播放控制器（测试注入点）。
  @visibleForTesting
  void setVocabPlayerForTesting(VocabularyListPlayerController? controller) {
    _vocabPlayer?.removeListener(_pushStateToMini);
    if (controller != null) {
      controller.addListener(_pushStateToMini);
    }
    _vocabPlayer = controller;
  }

  /// 打开迷你播放窗。
  ///
  /// 已存在则前置（不重复创建）；窗口关闭**不终止播放**——播放状态在主进程，
  /// 关闭的只是视图。
  Future<void> openMiniWindow() async {
    try {
      // 先按 arguments 找已有窗口——**不看 _miniWindowId**：
      // 用户可能关掉过迷你窗（id 还在但窗口已隐藏），此时再点按钮
      // 应该前置那个窗口，而不是新建一个。
      final all = await WindowController.getAll();
      for (final w in all) {
        if (w.arguments.startsWith(kItListeningWindowArgPrefix)) {
          await w.show();
          _miniWindow = w;
          _miniWindowId = w.windowId;
          _pushStateToMini();
          return;
        }
      }
      _miniWindowId = null;
      final created = await WindowController.create(
        WindowConfiguration(
          arguments: kItListeningWindowArgPrefix,
          hiddenAtLaunch: false,
        ),
      );
      _miniWindow = created;
      _miniWindowId = created.windowId;
      // 新窗口就绪后立刻推一次状态，避免它显示空白。
      Future.delayed(const Duration(milliseconds: 600), _pushStateToMini);
    } catch (e) {
      debugPrint('[ListeningHost] 打开迷你窗失败: $e');
    }
  }

  /// 打开迷你窗并进入**词汇播放模式**。
  ///
  /// 送入 [words]（展示形态）后迷你窗自动开播（[autoplay]）。与片段播放互斥：
  /// 先暂停片段 controller，再停掉词汇控制器既有的计时（`setWords` 内部处理），
  /// 然后切模式开播。
  Future<void> openMiniWindowWithVocab(
    List<String> words, {
    bool autoplay = true,
  }) async {
    // 互斥：词汇激活前先暂停片段播放，避免重叠音频。
    final c = _controller;
    if (c != null && (c.isPlaying || c.state != ListeningPlaybackState.stopped)) {
      await c.pause();
    }
    _mode = MiniPlaybackMode.vocab;
    final player = vocabPlayer;
    player.setWords(words);
    await player.start(autoplay: autoplay);
    await openMiniWindow();
  }

  /// 停掉词汇播放（片段播放激活时调用，保证无重叠音频）。
  Future<void> deactivateVocabPlayback() async {
    if (_mode != MiniPlaybackMode.vocab) return;
    await _vocabPlayer?.stop();
    _mode = MiniPlaybackMode.clip;
    _pushStateToMini();
  }

  /// 关闭迷你窗（播放继续，立即保存当前进度）。
  Future<void> closeMiniWindow() async {
    await _controller?.flushProgress();
    try {
      await _miniWindow?.hide();
    } catch (e) {
      debugPrint('[ListeningHost] 隐藏迷你窗失败: $e');
    }
  }

  /// 迷你窗是否已打开。
  bool get isMiniWindowOpen => _miniWindowId != null;

  /// 处理来自迷你窗的指令。
  ///
  /// 按当前激活模式分流：词汇模式把 `toggle/previous/next/toggleContinuous`
  /// 路由到词汇控制器（`speed:` 忽略——词汇走 TTS 固定语速），片段模式走原有
  /// 片段控制器。`close` 在词汇模式下**停止**词汇播放（词表无其它控制面，
  /// 留着会成孤儿音频），片段模式下仅保存进度继续播。
  Future<void> handleMiniCommand(String action) async {
    if (_mode == MiniPlaybackMode.vocab) {
      await _handleVocabMiniCommand(action);
      return;
    }
    final c = controller;
    if (action.startsWith('speed:')) {
      final value = double.tryParse(action.substring('speed:'.length));
      if (value != null) await c.setSpeed(value);
      return;
    }
    switch (action) {
      case 'toggle':
        await _deactivateVocabIfActivating();
        await c.togglePlay();
      case 'previous':
        await _deactivateVocabIfActivating();
        await c.previous(filePathFor: _pathFor);
      case 'next':
        await _deactivateVocabIfActivating();
        await c.next(filePathFor: _pathFor);
      case 'toggleContinuous':
        await _deactivateVocabIfActivating();
        c.setContinuous(!c.isContinuous);
      case 'close':
        await c.flushProgress();
    }
  }

  /// 片段播放动作要激活时，先停掉词汇播放（无重叠音频）。
  Future<void> _deactivateVocabIfActivating() async {
    if (_mode == MiniPlaybackMode.vocab) {
      await deactivateVocabPlayback();
    }
  }

  /// 词汇模式下的指令分流。
  Future<void> _handleVocabMiniCommand(String action) async {
    final player = _vocabPlayer;
    if (player == null) return;
    switch (action) {
      case 'toggle':
        await player.toggle();
      case 'previous':
        await player.previous();
      case 'next':
        await player.next();
      case 'toggleContinuous':
        player.setLoop(!player.isLooping);
      case 'close':
        // 词汇模式关闭即停播（与片段"关闭继续播"区分——词表无其它控制面）。
        await player.stop();
        _mode = MiniPlaybackMode.clip;
    }
  }

  /// 处理来自全局热键的指令（所有控制动作统一经过 controller 记录进度）。
  Future<void> handleHotKeyAction(String action) async {
    final c = controller;
    switch (action) {
      case ListeningHotKeyAction.toggle:
        await _deactivateVocabIfActivating();
        await c.togglePlay();
      case ListeningHotKeyAction.previous:
        await _deactivateVocabIfActivating();
        await c.previous(filePathFor: _pathFor);
      case ListeningHotKeyAction.next:
        await _deactivateVocabIfActivating();
        await c.next(filePathFor: _pathFor);
      case ListeningHotKeyAction.slower:
        await _deactivateVocabIfActivating();
        await c.slowDown();
      case ListeningHotKeyAction.faster:
        await _deactivateVocabIfActivating();
        await c.speedUp();
    }
  }

  /// 片段音频的绝对路径（供播放控制器使用）。
  String? _pathFor(Clip clip) {
    final file = library.audioFileFor(clip);
    return file.existsSync() ? file.path : null;
  }

  /// 供外部（全局热键）解析片段音频路径。
  String? pathResolver(Clip clip) => _pathFor(clip);

  /// 把当前播放状态推给迷你窗。
  ///
  /// 按激活模式组装：词汇模式推 `mode=vocab`、当前词、词序进度与循环位；
  /// 片段模式推现有字段且 `mode=clip`。迷你窗按 `mode` 切换渲染。
  void _pushStateToMini() {
    if (_mode == MiniPlaybackMode.vocab) {
      _pushVocabStateToMini();
      return;
    }
    final c = _controller;
    if (c == null) return;
    final clip = c.clip;
    try {
      ItListeningMiniBridge.instance.pushState({
        'mode': 'clip',
        'sceneLabel': clip?.scene.label ?? '',
        'clipTitle': clip?.title ?? '',
        'positionMs': c.position.inMilliseconds,
        'durationMs': c.duration.inMilliseconds,
        'speed': c.speed,
        'playing': c.isPlaying,
        'continuous': c.isContinuous,
      });
    } catch (_) {
      // 迷你窗未连接时忽略通道异常。
    }
  }

  /// 推送词汇模式状态。
  void _pushVocabStateToMini() {
    final player = _vocabPlayer;
    if (player == null) return;
    try {
      ItListeningMiniBridge.instance.pushState({
        'mode': 'vocab',
        'sceneLabel': '词汇',
        'clipTitle': player.currentWord ?? '',
        'positionMs': player.wordIndex,
        'durationMs': player.wordCount,
        'speed': 1.0,
        'playing': player.isPlaying,
        'continuous': player.isLooping,
      });
    } catch (_) {
      // 迷你窗未连接时忽略通道异常。
    }
  }

  /// 调试用：素材目录路径。
  String get materialsPath => p.join(AppPaths.itMeetingListeningDir.path, '');
}
