/// 实时字幕悬浮窗应用（子窗口进程入口）。
///
/// 透明、无边框、置顶、不抢焦点、可拖动（spec: live-caption-overlay）。
/// **纯视图**：识别/翻译/记录状态由主进程持有（design D4），本窗口只渲染
/// 推送来的字幕快照并发指令（切说话人/清空/记录）。
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../services/settings_store.dart';
import '../services/live_caption_bridge.dart';

/// 字幕窗收到的一条字幕。
class CaptionItem {
  CaptionItem({
    required this.text,
    required this.speakerSlot,
    this.translation,
    required this.isFinal,
    this.translationStatus = 'pending',
  });

  final String text;
  final int speakerSlot;
  final String? translation;
  final bool isFinal;
  final String translationStatus;

  static CaptionItem fromMap(Map<dynamic, dynamic> m) => CaptionItem(
        text: (m['text'] as String?) ?? '',
        speakerSlot: (m['speakerSlot'] as num?)?.toInt() ?? 0,
        translation: m['translation'] as String?,
        isFinal: (m['isFinal'] as bool?) ?? false,
        translationStatus: (m['translationStatus'] as String?) ?? 'pending',
      );
}

/// 说话人固定色（与主进程 models/speaker_state 一致）。
const _speakerColors = [
  Color(0xFFE5534B),
  Color(0xFF4C8DFF),
  Color(0xFF3FB950),
];

/// 字幕悬浮窗应用。
class LiveCaptionWindowApp extends StatefulWidget {
  const LiveCaptionWindowApp({super.key});

  @override
  State<LiveCaptionWindowApp> createState() => _LiveCaptionWindowAppState();
}

class _LiveCaptionWindowAppState extends State<LiveCaptionWindowApp> {
  static const List<double> _opacityLevels = [0.35, 0.50, 0.70, 0.90];

  List<CaptionItem> _captions = [];
  int _activeSpeaker = 0;
  bool _isRecording = false;
  List<String> _speakerNames = ['说话人 1', '说话人 2', '说话人 3'];
  double _fontSize = 16;
  double _opacity = 0.50;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _initWindow();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg =
          await SettingsStore.instance.readToolConfig('live-caption-window');
      final savedOpacity = cfg['opacity'] as num?;
      if (savedOpacity != null && mounted) {
        final parsed = savedOpacity.toDouble().clamp(0.2, 1.0);
        setState(() {
          _opacity = parsed;
        });
        await windowManager.setOpacity(parsed);
      }
      final savedFontSize = cfg['fontSize'] as num?;
      if (savedFontSize != null && mounted) {
        setState(() {
          _fontSize = savedFontSize.toDouble().clamp(10, 40);
        });
      }
    } catch (_) {}
  }

  void _saveConfig() {
    SettingsStore.instance.writeToolConfig('live-caption-window', {
      'opacity': _opacity,
      'fontSize': _fontSize,
    });
  }

  Future<void> _cycleOpacity() async {
    final curIdx =
        _opacityLevels.indexWhere((l) => (l - _opacity).abs() < 0.05);
    final nextIdx = curIdx >= 0 ? (curIdx + 1) % _opacityLevels.length : 1;
    final next = _opacityLevels[nextIdx];
    setState(() => _opacity = next);
    await windowManager.setOpacity(next);
    _saveConfig();
  }

  void _changeFontSize(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(10, 40));
    _saveConfig();
  }

  Future<void> _initWindow() async {
    try {
      await windowManager.ensureInitialized();

      // 1. 窗口层基础属性前置（防止通信通道因未就绪报错导致尺寸回退默认 800x600）
      await windowManager.setSize(const Size(560, 220));
      await windowManager.setMinimumSize(const Size(320, 120));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setHasShadow(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setOpacity(_opacity);

      // 2. 跨窗口通信通道接入
      await LiveCaptionBridge.instance.attachAsCaption(
        onState: (map) => _applyState(map),
      );

      // 关闭与隐藏指令均收敛为 hide，杜绝销毁窗口破坏双向 IPC 通道
      LiveCaptionBridge.instance.onCommandFromHost = (action) {
        if (action == 'close' || action == 'hide') {
          windowManager.hide();
        }
      };

      // 3. 读取持久化透明度与字号
      await _loadConfig();
    } catch (e) {
      debugPrint('[LiveCaption] 窗口初始化失败: $e');
    }
  }

  void _applyState(Map<dynamic, dynamic> map) {
    if (!mounted) return;
    final raw = (map['captions'] as List?) ?? const [];
    setState(() {
      _captions = raw
          .map((e) => CaptionItem.fromMap(Map<dynamic, dynamic>.from(e as Map)))
          .toList();
      _activeSpeaker = (map['activeSpeaker'] as num?)?.toInt() ?? 0;
      _isRecording = (map['isRecording'] as bool?) ?? false;
      _speakerNames =
          ((map['speakerNames'] as List?) ?? const []).map((e) => '$e').toList();
      if (_speakerNames.length < 3) {
        _speakerNames = ['说话人 1', '说话人 2', '说话人 3'];
      }
      _lastError = map['lastError'] as String?;
    });
  }

  void _command(String action) => LiveCaptionBridge.instance.sendCommand(action);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: _opacity),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDragBar(),
              if (_lastError != null && _lastError!.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildErrorBanner(_lastError!),
              ],
              const SizedBox(height: 6),
              Expanded(child: _buildCaptionList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragBar() {
    return GestureDetector(
      // 拖动条区域移动窗口。
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Row(
        children: [
          Icon(Icons.drag_indicator, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            '实时字幕',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const Spacer(),
          _speakerButton(0),
          _speakerButton(1),
          _speakerButton(2),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.opacity, size: 16, color: Colors.white70),
            tooltip: '调节透明度 (${(_opacity * 100).round()}%)',
            onPressed: _cycleOpacity,
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.text_decrease, size: 16, color: Colors.white70),
            tooltip: '缩小字号',
            onPressed: () => _changeFontSize(-2),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.text_increase, size: 16, color: Colors.white70),
            tooltip: '放大字号',
            onPressed: () => _changeFontSize(2),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
              size: _isRecording ? 16 : 14,
              color: _isRecording ? Colors.redAccent : Colors.white60,
            ),
            tooltip: _isRecording ? '停止记录（正在记录中）' : '开始记录字幕',
            onPressed: () => _command('toggleRecording'),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.delete_outline, size: 16, color: Colors.white70),
            tooltip: '清空字幕',
            onPressed: () => _command('clear'),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.visibility_off, size: 16, color: Colors.white70),
            tooltip: '隐藏（识别继续）',
            onPressed: () async {
              try {
                await windowManager.hide();
              } catch (_) {}
              _command('hide');
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.close, size: 16, color: Colors.redAccent),
            tooltip: '关闭（停止识别）',
            onPressed: () async {
              try {
                await windowManager.hide();
              } catch (_) {}
              _command('close');
            },
          ),
        ],
      ),
    );
  }

  Widget _speakerButton(int i) {
    final active = _activeSpeaker == i;
    return GestureDetector(
      onTap: () => _command('speaker:$i'),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? _speakerColors[i] : Colors.transparent,
          border: Border.all(color: _speakerColors[i]),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${i + 1}',
          style: TextStyle(
            color: active ? Colors.white : _speakerColors[i],
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionList() {
    if (_captions.isEmpty) {
      if (_lastError != null && _lastError!.isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _lastError!,
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: (_fontSize - 4).clamp(11, 24),
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      return Center(
        child: Text(
          '等待语音…',
          style: TextStyle(color: Colors.white54, fontSize: _fontSize - 4),
        ),
      );
    }
    // 只显示最近 6 条。
    final visible = _captions.length <= 6
        ? _captions
        : _captions.sublist(_captions.length - 6);
    return ListView(
      reverse: true,
      children: [
        for (final c in visible.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 2, right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: _speakerColors[c.speakerSlot.clamp(0, 2)]
                        .withValues(alpha: 0.25),
                    border: Border.all(
                      color: _speakerColors[c.speakerSlot.clamp(0, 2)],
                      width: 0.8,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _speakerNames.length > c.speakerSlot
                        ? _speakerNames[c.speakerSlot]
                        : '说话人 ${c.speakerSlot + 1}',
                    style: TextStyle(
                      color: _speakerColors[c.speakerSlot.clamp(0, 2)],
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.text,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _fontSize,
                          height: 1.25,
                          fontWeight:
                              c.isFinal ? FontWeight.normal : FontWeight.w300,
                        ),
                      ),
                      if (c.translation != null &&
                          c.translation!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          c.translation!,
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: (_fontSize - 2).clamp(10, 36),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
