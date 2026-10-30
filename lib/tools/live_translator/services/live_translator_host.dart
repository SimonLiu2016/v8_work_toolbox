/// 实时翻译主进程宿主
///
/// 持有唯一的 [LiveTranslatorCoordinator]（识别、翻译、记录的唯一状态来源），
/// 并管理字幕悬浮窗的开关与跨窗口通信（design D4：状态在主进程，悬浮窗纯视图）。
library;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import '../../../services/context_services_bridge.dart';
import '../services/live_caption_bridge.dart';
import '../services/live_caption_hotkey_service.dart';
import '../services/live_translator_coordinator.dart';

/// 实时翻译主进程宿主（单例）。
class LiveTranslatorHost {
  LiveTranslatorHost._();
  static final LiveTranslatorHost instance = LiveTranslatorHost._();

  LiveTranslatorCoordinator? _coordinator;

  WindowController? _captionWindow;
  String? _captionWindowId;

  /// 协调器（懒创建）。
  LiveTranslatorCoordinator get coordinator => _coordinator ??= LiveTranslatorCoordinator();

  /// 字幕悬浮窗的 arguments 前缀（供 main.dart 子窗口分支识别）。
  static const String windowArgPrefix = 'live-caption:';

  bool get isCaptionWindowOpen => _captionWindowId != null;

  /// 打开字幕悬浮窗（已存在则前置）。
  Future<void> openCaptionWindow() async {
    try {
      final all = await WindowController.getAll();
      for (final w in all) {
        if (w.arguments.startsWith(windowArgPrefix)) {
          await w.show();
          _captionWindow = w;
          _captionWindowId = w.windowId;
          LiveCaptionBridge.instance.pushState(_serializeState(coordinator.state));
          await ContextServicesBridge.instance.styleLiveCaptionWindow();
          return;
        }
      }
      _captionWindowId = null;
      final created = await WindowController.create(
        WindowConfiguration(
          arguments: windowArgPrefix,
          hiddenAtLaunch: false,
        ),
      );
      _captionWindow = created;
      _captionWindowId = created.windowId;
      await ContextServicesBridge.instance.styleLiveCaptionWindow();
      Future.delayed(const Duration(milliseconds: 300), () {
        ContextServicesBridge.instance.styleLiveCaptionWindow();
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        LiveCaptionBridge.instance.pushState(_serializeState(coordinator.state));
      });
    } catch (e) {
      debugPrint('[LiveTranslatorHost] 打开字幕窗失败: $e');
    }
  }

  /// 隐藏字幕悬浮窗（识别继续）。
  Future<void> hideCaptionWindow() async {
    try {
      await _captionWindow?.hide();
    } catch (e) {
      debugPrint('[LiveTranslatorHost] 隐藏字幕窗失败: $e');
    }
  }

  /// 关闭字幕悬浮窗：先停识别与捕获，再隐藏子窗口。
  ///
  /// 注意：不要销毁子窗口（不调 windowManager.close），否则会破坏
  /// WindowMethodChannel 的双向配对。这里仅调用 hideCaptionWindow()，
  /// 保持引用与 IPC 通道畅通，下次打开直接复用 show() 与 focus()。
  Future<void> closeCaptionWindow() async {
    try {
      await coordinator.stop();
      await hideCaptionWindow();
    } catch (e) {
      debugPrint('[LiveTranslatorHost] 关闭字幕窗失败: $e');
    }
  }

  /// 接线主进程侧通道与热键。
  void attachBridge() {
    LiveCaptionBridge.instance.onCommand = _handleCaptionCommand;
    LiveCaptionBridge.instance.attachAsHost();

    final hotkeys = LiveCaptionHotKeyService.instance;
    hotkeys.init();
    hotkeys.onAction = _handleHotKeyAction;
    hotkeys.register();

    coordinator.stateStream.listen((state) {
      LiveCaptionBridge.instance.pushState(_serializeState(state));
    });
  }

  void _handleHotKeyAction(String action) {
    if (action == LiveCaptionAction.toggle) {
      // ⌥T 开关字幕窗：隐藏（识别继续）/ 重新呼出。
      if (isCaptionWindowOpen) {
        hideCaptionWindow();
      } else {
        openCaptionWindow();
      }
      return;
    }
    _handleCaptionCommand(action);
  }

  void _handleCaptionCommand(String action) {
    switch (action) {
      case 'speaker:0':
        coordinator.setActiveSpeaker(0);
        break;
      case 'speaker:1':
        coordinator.setActiveSpeaker(1);
        break;
      case 'speaker:2':
        coordinator.setActiveSpeaker(2);
        break;
      case 'clear':
        coordinator.clearCaptions();
        break;
      case 'toggleRecording':
        if (coordinator.state.isRecording) {
          coordinator.stopRecording();
        } else {
          coordinator.startRecording();
        }
        break;
      case 'hide':
        hideCaptionWindow();
        break;
      case 'close':
        // 悬浮窗自己的关闭按钮：只关窗口进程（识别已在子窗口侧发指令前
        // 由用户选择"关闭"语义 = 停止识别，主进程在 hide 分支处理视图）。
        // 这里区分：来自子窗口 UI 的 close = 停识别 + 关进程。
        closeCaptionWindow();
        break;
    }
  }

  Map<String, dynamic> _serializeState(LiveState state) {
    return {
      'status': state.status.name,
      'isRecording': state.isRecording,
      'translationEnabled': state.translationEnabled,
      'targetLanguage': state.targetLanguage,
      'activeSpeaker': state.speaker.activeIndex,
      'speakerNames': state.speaker.slots.map((s) => s.name).toList(),
      'lastError': state.lastError,
      'captions': state.captions
          .map((c) => {
                'id': c.id,
                'text': c.text,
                'speakerSlot': c.speakerSlot,
                'startMs': c.startMs,
                'endMs': c.endMs,
                'translation': c.translation,
                'translationStatus': c.translationStatus.name,
                'isFinal': c.isFinal,
              })
          .toList(),
    };
  }
}
