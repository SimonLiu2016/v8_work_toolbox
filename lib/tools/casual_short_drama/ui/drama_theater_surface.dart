import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../services/casual_short_drama_controller.dart';
import 'widgets/drama_cover_widget.dart';

/// 桌面端 16:9 沉浸式宽屏剧场播放视窗
///
/// 具备：
/// - 16:9 大屏画幅框架
/// - 原生 macOS 窗口真全屏联动（F 键全屏，Esc 退出全屏，鼠标静止自动隐退控制栏）
/// - 视频居中垂直自适应，两侧采用纯黑底色与微弱氛围底纹
/// - 悬浮式播放控制条（进度条、选集、倍速、音量、下载、全屏）
/// - 桌面全局键盘快捷键响应（空格、方向键、M、F、Esc）
class DramaTheaterSurface extends StatefulWidget {
  final CasualShortDramaController controller;
  final VoidCallback onToggleDrawer;
  final VoidCallback? onBackToCatalog;
  final ValueChanged<bool>? onFullscreenChanged;

  const DramaTheaterSurface({
    super.key,
    required this.controller,
    required this.onToggleDrawer,
    this.onBackToCatalog,
    this.onFullscreenChanged,
  });

  @override
  State<DramaTheaterSurface> createState() => _DramaTheaterSurfaceState();
}

class _DramaTheaterSurfaceState extends State<DramaTheaterSurface> {
  final FocusNode _focusNode = FocusNode();
  bool _showControls = true;
  bool _isFullscreen = false;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cancelHideControlsTimer();
    if (_isFullscreen) {
      windowManager.setFullScreen(false);
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      widget.controller.togglePlayPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.seekRelative(const Duration(seconds: -5));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.seekRelative(const Duration(seconds: 5));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.controller.playPrevEpisode();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.controller.playNextEpisode();
    } else if (key == LogicalKeyboardKey.keyM) {
      widget.controller.toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape && _isFullscreen) {
      _toggleFullscreen();
    }
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    setState(() {
      _isFullscreen = next;
    });
    try {
      await windowManager.setFullScreen(next);
    } catch (_) {}
    widget.onFullscreenChanged?.call(next);

    if (next) {
      _startHideControlsTimer();
    } else {
      _cancelHideControlsTimer();
      setState(() {
        _showControls = true;
      });
    }
  }

  void _onMouseMove() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    if (_isFullscreen) {
      _startHideControlsTimer();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isFullscreen) {
        setState(() => _showControls = false);
      }
    });
  }

  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final drama = widget.controller.currentDrama;
    final theme = Theme.of(context);

    return ClipRect(
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          onEnter: (_) => _onMouseMove(),
          onHover: (_) => _onMouseMove(),
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. 背景层：纯黑沉浸底色与微弱暗色海报底纹（无需 BackdropFilter，彻底杜绝全局灰色模糊溢出）
                if (drama?.cover != null && drama!.cover.isNotEmpty)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.12,
                      child: DramaCoverWidget(
                        coverUrl: drama.cover,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),

                // 2. 视频主视窗：居中大屏自适应渲染 (自适应 9:16 或 16:9)
                Center(
                  child: widget.controller.isPlayerReady
                      ? Video(
                          controller: widget.controller.videoController,
                          controls: null,
                          fit: BoxFit.contain,
                        )
                      : const SizedBox.shrink(),
                ),

                // 3. 播放错误/重试提示
                if (widget.controller.playError != null)
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.amberAccent, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            widget.controller.playError!,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () => widget.controller.playEpisode(widget.controller.currentEp),
                            child: const Text('重试播放'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 4. 加载中或缓冲指示器
                if (widget.controller.isLoadingPlay || widget.controller.isBuffering)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white70),
                          SizedBox(height: 12),
                          Text(
                            '精彩加载中...',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),

              // 4. 顶部操作栏
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                top: _showControls ? 0 : -80,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      if (widget.onBackToCatalog != null)
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                          tooltip: '返回短剧目录',
                          onPressed: widget.onBackToCatalog,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              drama?.title ?? '随心短剧',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '当前播放：第 ${widget.controller.currentEp} 集 / 共 ${drama?.totalEpisodes ?? drama?.episodes.length ?? 0} 集',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          widget.controller.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: widget.controller.isFavorite ? Colors.redAccent : Colors.white,
                        ),
                        tooltip: widget.controller.isFavorite ? '取消私密收藏' : '添加至私密收藏',
                        onPressed: () => widget.controller.toggleFavorite(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_for_offline_rounded, color: Colors.white),
                        tooltip: '一键下载本集至私密库',
                        onPressed: () async {
                          final task = await widget.controller.downloadCurrentEpisode();
                          if (context.mounted && task != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已加入私密下载队列: ${task.title}')),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.format_list_bulleted_rounded, color: Colors.white),
                        tooltip: '选集抽屉',
                        onPressed: widget.onToggleDrawer,
                      ),
                    ],
                  ),
                ),
              ),

              // 5. 底部悬浮控制台
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                bottom: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 进度条
                      Row(
                        children: [
                          Text(
                            _formatDuration(widget.controller.position),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                activeTrackColor: theme.colorScheme.primary,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                              ),
                              child: Slider(
                                min: 0.0,
                                max: widget.controller.duration.inMilliseconds > 0
                                    ? widget.controller.duration.inMilliseconds.toDouble()
                                    : 1.0,
                                value: widget.controller.position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                      0.0,
                                      widget.controller.duration.inMilliseconds > 0
                                          ? widget.controller.duration.inMilliseconds.toDouble()
                                          : 1.0,
                                    ),
                                onChanged: (val) {
                                  widget.controller.seek(Duration(milliseconds: val.toInt()));
                                },
                              ),
                            ),
                          ),
                          Text(
                            _formatDuration(widget.controller.duration),
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // 控制按钮排
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 26),
                            tooltip: '上一集 (↑)',
                            onPressed: () => widget.controller.playPrevEpisode(),
                          ),
                          IconButton(
                            icon: Icon(
                              widget.controller.isPlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_filled_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                            tooltip: widget.controller.isPlaying ? '暂停 (空格)' : '播放 (空格)',
                            onPressed: () => widget.controller.togglePlayPause(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
                            tooltip: '下一集 (↓)',
                            onPressed: () => widget.controller.playNextEpisode(),
                          ),
                          const SizedBox(width: 12),

                          // 音量控制
                          IconButton(
                            icon: Icon(
                              widget.controller.isMuted || widget.controller.volume <= 0
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                            tooltip: '静音 (M)',
                            onPressed: () => widget.controller.toggleMute(),
                          ),
                          SizedBox(
                            width: 80,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                              ),
                              child: Slider(
                                min: 0.0,
                                max: 100.0,
                                value: widget.controller.volume,
                                onChanged: (val) => widget.controller.setVolume(val),
                              ),
                            ),
                          ),

                          const Spacer(),

                          // 倍速选择
                          DropdownButton<double>(
                            value: widget.controller.rate,
                            dropdownColor: const Color(0xFF222222),
                            underline: const SizedBox.shrink(),
                            icon: const Icon(Icons.speed_rounded, color: Colors.white70, size: 18),
                            items: const [
                              DropdownMenuItem(value: 0.75, child: Text('0.75x', style: TextStyle(color: Colors.white, fontSize: 12))),
                              DropdownMenuItem(value: 1.0, child: Text('1.0x', style: TextStyle(color: Colors.white, fontSize: 12))),
                              DropdownMenuItem(value: 1.25, child: Text('1.25x', style: TextStyle(color: Colors.white, fontSize: 12))),
                              DropdownMenuItem(value: 1.5, child: Text('1.5x', style: TextStyle(color: Colors.white, fontSize: 12))),
                              DropdownMenuItem(value: 2.0, child: Text('2.0x', style: TextStyle(color: Colors.white, fontSize: 12))),
                            ],
                            onChanged: (val) {
                              if (val != null) widget.controller.setPlaybackRate(val);
                            },
                          ),
                          const SizedBox(width: 8),

                          // 快捷键提示弹窗/提示
                          IconButton(
                            icon: const Icon(Icons.keyboard_outlined, color: Colors.white70, size: 20),
                            tooltip: '快捷键：空格(暂停/播)  ←/→(快退/进5s)  ↑/↓(上下集)  M(静音)  F(全屏)',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  duration: Duration(seconds: 4),
                                  content: Text('桌面快捷键：空格键 播放/暂停；左右方向键 快退/快进 5秒；上下方向键 切集；M 静音；F 全屏'),
                                ),
                              );
                            },
                          ),

                          // 全屏
                          IconButton(
                            icon: Icon(
                              _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            tooltip: '全屏 (F)',
                            onPressed: _toggleFullscreen,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
