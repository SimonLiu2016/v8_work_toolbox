/// 常驻迷你播放窗。
///
/// 形态是音乐播放器：单行优先的信息密度 + 一行控件。它 MUST NOT 抢焦点——
/// 播放时用户要能切回 IDE 继续写代码（spec「悬浮窗播放时保持后台」）。
///
/// **播放状态由主进程持有**（design D7）：本窗口只渲染状态 + 发指令，
/// 通过 `WindowController.invokeMethod` 与主进程通信。
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../theme/app_theme.dart';
import '../services/it_listening_mini_bridge.dart';

/// 迷你窗收到的状态载荷。
class MiniPlayerState {
  /// 播放模式：`clip`（会议片段）或 `vocab`（词汇磨耳朵）。
  final String mode;

  final String sceneLabel;
  final String clipTitle;
  final int positionMs;
  final int durationMs;
  final double speed;
  final bool playing;
  final bool continuous;

  const MiniPlayerState({
    this.mode = 'clip',
    this.sceneLabel = '',
    this.clipTitle = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.speed = 1.0,
    this.playing = false,
    this.continuous = false,
  });

  /// 是否处于词汇磨耳朵模式。
  bool get isVocab => mode == 'vocab';

  /// 词汇模式下的词序进度文本（如 `3/24`）；片段模式返回空。
  String get wordProgressText => isVocab ? '$positionMs/$durationMs' : '';

  Map<String, dynamic> toMap() => {
        'mode': mode,
        'sceneLabel': sceneLabel,
        'clipTitle': clipTitle,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'speed': speed,
        'playing': playing,
        'continuous': continuous,
      };

  factory MiniPlayerState.fromMap(Map<dynamic, dynamic> map) => MiniPlayerState(
        mode: map['mode'] as String? ?? 'clip',
        sceneLabel: map['sceneLabel'] as String? ?? '',
        clipTitle: map['clipTitle'] as String? ?? '',
        positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        speed: (map['speed'] as num?)?.toDouble() ?? 1.0,
        playing: map['playing'] as bool? ?? false,
        continuous: map['continuous'] as bool? ?? false,
      );
}

/// 迷你播放窗应用。
class ItListeningMiniPlayerApp extends StatefulWidget {
  const ItListeningMiniPlayerApp({super.key});

  @override
  State<ItListeningMiniPlayerApp> createState() =>
      _ItListeningMiniPlayerAppState();
}

class _ItListeningMiniPlayerAppState extends State<ItListeningMiniPlayerApp> {
  MiniPlayerState _state = const MiniPlayerState();

  @override
  void initState() {
    super.initState();
    _initWindow();
  }

  Future<void> _initWindow() async {
    // 通道注册与窗口样式**分开兜底**：通道注册失败不应连带把窗口样式
    // 一起跳过——那样窗口会变成没有置顶、没有尺寸的裸窗。
    try {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(420, 96), animate: false);
      await windowManager.setMinimumSize(const Size(360, 80));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setTitle('会议音频');
      await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden, windowButtonVisibility: false);
      await windowManager.setHasShadow(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.center();
    } catch (e) {
      debugPrint('[ItListeningMini] 窗口初始化失败: $e');
    }

    // 迷你窗只渲染状态 + 发指令：注册通道的接收端。
    try {
      await ItListeningMiniBridge.instance.attachAsMini(
        onState: (map) => applyState(map),
      );
    } catch (e) {
      debugPrint('[ItListeningMini] 通道注册失败（播放控制将不可用）: $e');
    }
  }

  /// 接收主进程推送的状态。
  void applyState(Map<dynamic, dynamic> map) {
    if (!mounted) return;
    setState(() => _state = MiniPlayerState.fromMap(map));
  }

  /// 向主进程发指令。
  void _command(String action) {
    ItListeningMiniBridge.instance.sendCommand(action);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bg = isDark ? context.bgCard : AppTheme.lightBgCard;
    final textPrimary = isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final isVocab = _state.isVocab;
    final ratio = isVocab
        ? 0.0
        : (_state.durationMs > 0
            ? (_state.positionMs / _state.durationMs).clamp(0.0, 1.0)
            : 0.0);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        backgroundColor: bg,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _state.sceneLabel.isEmpty ? '—' : _state.sceneLabel,
                      style: TextStyle(
                          fontSize: 10, color: accent, letterSpacing: 0.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _state.clipTitle.isEmpty
                          ? (isVocab ? '未在播放' : '未在播放')
                          : _state.clipTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: textPrimary),
                    ),
                  ),
                  if (isVocab)
                    Text(
                      _state.wordProgressText,
                      style: TextStyle(fontSize: 10, color: textSecondary),
                    )
                  else
                    Text(
                      '${_fmt(_state.positionMs)} / ${_fmt(_state.durationMs)}',
                      style: TextStyle(fontSize: 10, color: textSecondary),
                    ),
                  const SizedBox(width: 4),
                  // 关闭入口：隐藏窗口，**不终止播放**（播放状态在主进程）。
                  // 没有它的话，用户只能重启应用才能关掉这个常驻置顶的窗口。
                  _closeButton(context, textSecondary),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 2,
                backgroundColor: isDark ? context.bgInput : AppTheme.lightBgInput,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconButton(Icons.skip_previous_rounded, '上一段',
                      () => _command('previous'), textSecondary),
                  const SizedBox(width: 4),
                  _iconButton(
                    _state.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    '播放/暂停',
                    () => _command('toggle'),
                    accent,
                    size: 22,
                  ),
                  const SizedBox(width: 4),
                  _iconButton(Icons.skip_next_rounded, '下一段',
                      () => _command('next'), textSecondary),
                  const Spacer(),
                  if (!isVocab) ...[
                    _speedButton(context, accent, textSecondary),
                    const SizedBox(width: 6),
                  ],
                  _iconButton(
                    Icons.repeat_rounded,
                    '连续播放',
                    () => _command('toggleContinuous'),
                    _state.continuous ? accent : textSecondary,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 关闭按钮。
  ///
  /// 用 `windowManager.hide()` 隐藏本窗口——**不调 close()**：销毁窗口会断开
  /// `WindowMethodChannel` 的双向配对，重开时通道要重新注册，而播放状态
  /// 仍在主进程持有，隐藏才是与"关闭不终止播放"一致的动作。
  ///
  /// 词汇模式下先发 `close` 指令（宿主侧**停止**词汇播放——词表无其它控制面，
  /// 留着会成孤儿音频），再隐藏；片段模式下宿主仅保存进度继续播。
  Widget _closeButton(BuildContext context, Color color) {
    return Tooltip(
      message: '关闭悬浮窗（播放继续）',
      child: InkWell(
        onTap: () async {
          // 一律发 `close`：宿主按模式分流——片段模式仅保存进度继续播，
          // 词汇模式**停止**词汇播放（词表无其它控制面，留着会成孤儿音频）。
          _command('close');
          try {
            await windowManager.hide();
          } catch (e) {
            debugPrint('[ItListeningMini] 隐藏窗口失败: $e');
          }
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.close_rounded, size: 13, color: color),
        ),
      ),
    );
  }

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
    Color color, {
    double size = 18,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }

  Widget _speedButton(
      BuildContext context, Color accent, Color textSecondary) {
    const steps = [0.75, 0.9, 1.0, 1.25];
    final current = steps.contains(_state.speed) ? _state.speed : 1.0;
    return PopupMenuButton<double>(
      tooltip: '播放速度',
      color: context.bgCardHover,
      onSelected: (v) => _command('speed:$v'),
      itemBuilder: (context) => [
        for (final s in steps)
          PopupMenuItem<double>(
            value: s,
            child: Text('${s}x',
                style: TextStyle(
                    fontSize: 12,
                    color: s == current ? accent : null)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text('${current}x',
            style: TextStyle(fontSize: 11, color: textSecondary)),
      ),
    );
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
