import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../theme/app_theme.dart';
import '../services/ai_subtitle_service.dart';
import '../services/media_history_store.dart';
import '../services/private_player_controller.dart';
import '../services/private_storage_manager.dart';

/// 播放器主视口组件（包含视频渲染、自隐藏控制层、实时字幕渲染与全屏控制）
class PrivatePlayerView extends StatefulWidget {
  final PrivatePlayerController controller;
  final VoidCallback? onOpenSubtitlesDialog;

  const PrivatePlayerView({
    super.key,
    required this.controller,
    this.onOpenSubtitlesDialog,
  });

  @override
  State<PrivatePlayerView> createState() => _PrivatePlayerViewState();
}

class _PrivatePlayerViewState extends State<PrivatePlayerView> {
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isDraggingSlider = false;
  double _dragPositionMs = 0.0;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (widget.controller.isPlaying && !_isDraggingSlider) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _onUserInteraction() {
    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _startHideTimer();
  }

  Future<void> _pickLocalMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4', 'mkv', 'mov', 'webm', 'flv', 'ts', 'avi',
        'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'
      ],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      await widget.controller.open(path, title: name);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final hasMedia = ctrl.currentSource != null;

        if (!hasMedia) {
          return _buildEmptyState();
        }

        return MouseRegion(
          onHover: (_) => _onUserInteraction(),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _showControls = !_showControls;
              });
              if (_showControls) _startHideTimer();
            },
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. 视频渲染底层
                  Center(
                    child: Video(
                      controller: ctrl.videoController,
                      controls: NoVideoControls,
                    ),
                  ),

                  // 2. 缓冲动画
                  if (ctrl.isBuffering)
                    const Center(
                      child: CircularProgressIndicator(color: AppTheme.accent),
                    ),

                  // 3. 实时字幕悬浮图层
                  if (ctrl.showSubtitles && ctrl.currentSubtitleText.isNotEmpty)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: _showControls ? 88 : 28,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: 1.0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              ctrl.currentSubtitleText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                                shadows: [
                                  Shadow(
                                    offset: Offset(0, 1),
                                    blurRadius: 3,
                                    color: Colors.black,
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 4. 控制遮罩层 (淡入淡出)
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 顶部渐变遮罩与工具栏
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _buildTopBar(ctrl),
                          ),

                          // 底部渐变遮罩与控制条
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: _buildBottomBar(ctrl),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(PrivatePlayerController ctrl) {
    final isFav = ctrl.currentSource != null &&
        MediaHistoryStore.instance.isFavorite(ctrl.currentSource!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              ctrl.currentTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // 收藏按钮
          IconButton(
            icon: Icon(
              isFav ? Icons.star_rounded : Icons.star_border_rounded,
              color: isFav ? Colors.amber : Colors.white70,
            ),
            tooltip: isFav ? '已收藏' : '加入收藏',
            onPressed: () {
              if (ctrl.currentSource != null) {
                MediaHistoryStore.instance.toggleFavorite(
                  urlOrPath: ctrl.currentSource!,
                  title: ctrl.currentTitle,
                  duration: ctrl.duration,
                  thumbnail: ctrl.currentThumbnail,
                );
              }
            },
          ),
          // 打开本地私密目录
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white70),
            tooltip: '打开私密存储目录 (Finder)',
            onPressed: () {
              PrivateStorageManager.instance.revealInFinder();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(PrivatePlayerController ctrl) {
    final currentMs = _isDraggingSlider ? _dragPositionMs : ctrl.position.inMilliseconds.toDouble();
    final maxMs = ctrl.duration.inMilliseconds.toDouble();
    final validMax = maxMs > 0 ? maxMs : 1.0;
    final clampedValue = currentMs.clamp(0.0, validMax);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppTheme.accent,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: clampedValue,
              min: 0.0,
              max: validMax,
              onChangeStart: (val) {
                setState(() {
                  _isDraggingSlider = true;
                  _dragPositionMs = val;
                });
              },
              onChanged: (val) {
                setState(() {
                  _dragPositionMs = val;
                });
              },
              onChangeEnd: (val) {
                _isDraggingSlider = false;
                ctrl.seek(Duration(milliseconds: val.toInt()));
                _startHideTimer();
              },
            ),
          ),

          // 下方控制按钮行
          Row(
            children: [
              // 播放/暂停
              IconButton(
                icon: Icon(
                  ctrl.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: () => ctrl.playOrPause(),
              ),

              // 快退 10s
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 20),
                tooltip: '快退 10 秒',
                onPressed: () {
                  final newPos = ctrl.position - const Duration(seconds: 10);
                  ctrl.seek(newPos < Duration.zero ? Duration.zero : newPos);
                },
              ),

              // 快进 10s
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 20),
                tooltip: '快进 10 秒',
                onPressed: () {
                  final newPos = ctrl.position + const Duration(seconds: 10);
                  ctrl.seek(newPos > ctrl.duration ? ctrl.duration : newPos);
                },
              ),

              const SizedBox(width: 8),

              // 时间文本 (00:12 / 14:30)
              Text(
                '${_formatDuration(ctrl.position)} / ${_formatDuration(ctrl.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),

              const Spacer(),

              // 挂载外部字幕文件
              IconButton(
                icon: const Icon(Icons.file_upload_outlined, color: Colors.white70, size: 19),
                tooltip: '挂载外部字幕 (.srt / .vtt)',
                onPressed: () => _pickAndMountSubtitle(context, ctrl),
              ),

              // 离线极速生成全量字幕
              IconButton(
                icon: const Icon(Icons.bolt_rounded, color: Colors.amber, size: 21),
                tooltip: '极速生成全量字幕 (原生直取/内嵌提取/极速转录)',
                onPressed: () => _triggerFastSubtitleGeneration(context, ctrl),
              ),

              // 字幕显隐开关与加载提示
              IconButton(
                icon: Icon(
                  ctrl.showSubtitles ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
                  color: ctrl.showSubtitles ? AppTheme.accent : Colors.white38,
                  size: 20,
                ),
                tooltip: ctrl.showSubtitles
                    ? '关闭字幕显示'
                    : (ctrl.subtitles.isNotEmpty ? '开启字幕显示 (${ctrl.subtitles.length} 句)' : '开启字幕显示 (暂无字幕)'),
                onPressed: () => ctrl.toggleSubtitles(),
              ),

              // AI 字幕高级配置弹窗
              if (widget.onOpenSubtitlesDialog != null)
                IconButton(
                  icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white70, size: 19),
                  tooltip: 'AI 字幕高级设置与导出',
                  onPressed: widget.onOpenSubtitlesDialog,
                ),

              // 倍速选择
              PopupMenuButton<double>(
                tooltip: '播放倍速',
                initialValue: ctrl.rate,
                onSelected: (r) => ctrl.setRate(r),
                itemBuilder: (context) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
                    .map((r) => PopupMenuItem(
                          value: r,
                          child: Text('${r}x', style: TextStyle(color: r == ctrl.rate ? AppTheme.accent : null)),
                        ))
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '${ctrl.rate}x',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),

              // 音量滑块按钮
              _buildVolumeWidget(ctrl),

              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeWidget(PrivatePlayerController ctrl) {
    return PopupMenuButton<void>(
      tooltip: '音量调节',
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, setVolState) {
              return SizedBox(
                width: 140,
                child: Row(
                  children: [
                    Icon(
                      ctrl.volume == 0 ? Icons.volume_off : Icons.volume_up,
                      color: AppTheme.textSecondary,
                      size: 18,
                    ),
                    Expanded(
                      child: Slider(
                        value: ctrl.volume,
                        min: 0,
                        max: 100,
                        activeColor: AppTheme.accent,
                        onChanged: (v) {
                          setVolState(() {});
                          ctrl.setVolume(v);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          ctrl.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: Colors.white70,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(AppTheme.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.play_circle_outline_rounded,
                size: 38,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: AppTheme.space20),
            Text(
              '私密影音播放器',
              style: AppTheme.fontTitle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: AppTheme.space8),
            Text(
              '支持播放本地各种格式音视频，或在“在线解析”栏目解析在线流媒体直接播放',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.space24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('选择本地音视频文件'),
              onPressed: _pickLocalMedia,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndMountSubtitle(BuildContext context, PrivatePlayerController ctrl) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt'],
    );
    if (res == null || res.files.isEmpty || res.files.single.path == null) return;

    final path = res.files.single.path!;
    try {
      final count = await ctrl.mountSubtitleFile(path, autoEnable: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功挂载字幕: ${path.split('/').last} (共 $count 句)'),
          backgroundColor: AppTheme.bgCard,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('字幕挂载失败: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _triggerFastSubtitleGeneration(BuildContext context, PrivatePlayerController ctrl) async {
    if (ctrl.currentSource == null || ctrl.currentSource!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先播放视频，然后再点击生成字幕'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
            ),
            SizedBox(width: 12),
            Text('正在以极速方式生成/提取字幕 (优先直取原生或内嵌轨)...'),
          ],
        ),
        backgroundColor: AppTheme.bgCard,
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final segments = await AiSubtitleService.instance.fastGenerateSubtitles(
        videoPathOrUrl: ctrl.currentSource!,
        title: ctrl.currentTitle,
        duration: ctrl.duration,
      );

      if (segments.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未能在该媒体中提取或生成有效字幕'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }

      ctrl.setSubtitles(segments);
      ctrl.toggleSubtitles(true);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('字幕提取/生成完成！已加载 ${segments.length} 条字幕并自动上屏'),
          backgroundColor: AppTheme.bgCard,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('字幕生成失败: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}
