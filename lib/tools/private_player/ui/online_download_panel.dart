import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../theme/app_theme.dart';
import '../services/ai_subtitle_service.dart';
import '../services/download_queue_manager.dart';
import '../services/private_storage_manager.dart';
import '../services/ytdlp_video_parser.dart';
import 'media_thumbnail_widget.dart';

/// 在线流媒体解析、批量下载与任务管理面板
class OnlineDownloadPanel extends StatefulWidget {
  final void Function(String urlOrPath, {String? title, String? thumbnail}) onPlayMedia;

  const OnlineDownloadPanel({
    super.key,
    required this.onPlayMedia,
  });

  @override
  State<OnlineDownloadPanel> createState() => _OnlineDownloadPanelState();
}

class _OnlineDownloadPanelState extends State<OnlineDownloadPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // 单视频解析状态
  final TextEditingController _urlController = TextEditingController();
  bool _isParsing = false;
  ParsedVideoInfo? _parsedInfo;
  VideoFormatOption? _selectedFormat;
  String _parseError = '';

  // 批量下载状态
  final TextEditingController _batchController = TextEditingController();

  final DownloadQueueManager _queue = DownloadQueueManager.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _handleParse() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isParsing = true;
      _parseError = '';
      _parsedInfo = null;
    });

    try {
      final info = await YtdlpVideoParser.instance.parseUrl(url);
      if (mounted) {
        setState(() {
          _parsedInfo = info;
          _selectedFormat = info.formats.firstOrNull;
          _isParsing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _parseError = e.toString().replaceAll('Exception: ', '');
          _isParsing = false;
        });
      }
    }
  }

  void _handleBatchDownload() {
    final text = _batchController.text.trim();
    if (text.isEmpty) return;

    final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) return;

    _queue.addBatch(lines);
    _batchController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加 ${lines.length} 个下载任务至队列'),
        backgroundColor: context.bgCard,
      ),
    );

    _tabController.animateTo(2); // 切换到任务列表 Tab
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部 Tab 栏
        Container(
          height: 44,
          color: context.bgCard,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: context.accentSolid,
                labelColor: context.accentText,
                unselectedLabelColor: context.textSecondary,
                tabs: [
                  const Tab(text: '单链接解析'),
                  const Tab(text: '批量下载'),
                  ListenableBuilder(
                    listenable: _queue,
                    builder: (context, _) {
                      final activeCount = _queue.tasks.where((t) =>
                          t.status == DownloadStatus.downloading ||
                          t.status == DownloadStatus.merging ||
                          t.status == DownloadStatus.queued).length;
                      return Tab(
                        child: Row(
                          children: [
                            const Text('任务队列'),
                            if (activeCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.accentText,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$activeCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              Spacer(),
              // 快速打开下载文件夹
              TextButton.icon(
                icon: Icon(Icons.folder_open_rounded, size: 16),
                label: Text('下载目录', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: context.textSecondary),
                onPressed: () {
                  PrivateStorageManager.instance.revealInFinder(
                    PrivateStorageManager.instance.downloadsDir,
                  );
                },
              ),
            ],
          ),
        ),

        // Tab 视图内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSingleParseTab(),
              _buildBatchTab(),
              _buildQueueTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleParseTab() {
    return ListView(
      padding: EdgeInsets.all(AppTheme.space20),
      children: [
        // 输入框与解析按钮
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '输入 B站 / YouTube / Pornhub / PornLulu / MissAV 等视频链接',
                  hintStyle: TextStyle(color: context.textSecondary, fontSize: 13),
                  prefixIcon: Icon(Icons.link_rounded, size: 18, color: context.textSecondary),
                  suffixIcon: _urlController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 16),
                          onPressed: () {
                            setState(() {
                              _urlController.clear();
                              _parsedInfo = null;
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: context.bgCard,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.accentSolid),
                  ),
                ),
                onSubmitted: (_) => _handleParse(),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentSolid,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _isParsing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search_rounded, size: 18),
              label: Text(_isParsing ? '解析中...' : '一键解析'),
              onPressed: _isParsing ? null : _handleParse,
            ),
          ],
        ),

        if (_parseError.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          Container(
            padding: const EdgeInsets.all(AppTheme.space12),
            decoration: BoxDecoration(
              color: context.errorText.withValues(alpha: 0x1F / 255),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.errorText.withValues(alpha: 0.3)),
            ),
            child: Text(
              _parseError,
              style: TextStyle(color: context.errorText, fontSize: 13),
            ),
          ),
        ],

        if (_parsedInfo != null) ...[
          SizedBox(height: AppTheme.space20),
          _buildParsedInfoCard(_parsedInfo!),
        ],
      ],
    );
  }

  Widget _buildParsedInfoCard(ParsedVideoInfo info) {
    return Container(
      padding: EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              if (info.thumbnailUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    info.thumbnailUrl!,
                    width: 160,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 160,
                      height: 96,
                      color: context.bgCard,
                      child: Icon(Icons.movie_outlined, color: context.textSecondary),
                    ),
                  ),
                ),
              const SizedBox(width: AppTheme.space16),
              // 标题与来源平台
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.accentText.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            info.platform,
                            style: TextStyle(color: context.accentText, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (info.author != null) ...[
                          SizedBox(width: 8),
                          Text(
                            info.author!,
                            style: TextStyle(color: context.textSecondary, fontSize: 12),
                          ),
                        ],
                        Spacer(),
                        Text(
                          '时长: ${info.duration.inMinutes}:${(info.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      info.title,
                      style: AppTheme.fontTitle.copyWith(fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    // 操作按钮：立即播放 / 加入下载
                    Row(
                      children: [
                        if (info.directStreamUrl != null)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.accentSolid,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: Icon(Icons.play_arrow_rounded, size: 18),
                            label: Text('立即在线播放'),
                            onPressed: () {
                              widget.onPlayMedia(
                                info.directStreamUrl!,
                                title: info.title,
                                thumbnail: info.thumbnailUrl,
                              );
                            },
                          ),
                        SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.textPrimary,
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            side: BorderSide(color: context.borderSubtle),
                          ),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('添加至下载队列'),
                          onPressed: () {
                            _queue.addTask(
                              info.originalUrl,
                              title: info.title,
                              formatId: _selectedFormat?.formatId ?? 'bestvideo+bestaudio/best',
                              thumbnailUrl: info.thumbnailUrl,
                            );
                            _tabController.animateTo(2);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 清晰度与格式选择
          if (info.formats.isNotEmpty) ...[
            Divider(color: context.borderSubtle, height: 28),
            Text(
              '选择下载画质规格：',
              style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: info.formats.map((fmt) {
                final isSelected = _selectedFormat?.formatId == fmt.formatId;
                return ChoiceChip(
                  label: Text(fmt.displayName, style: TextStyle(fontSize: 12, color: isSelected ? context.onAccentSolid : context.textPrimary)),
                  selected: isSelected,
                  selectedColor: context.accentSolid,
                  backgroundColor: context.bgCard,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedFormat = fmt;
                      });
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBatchTab() {
    return Padding(
      padding: EdgeInsets.all(AppTheme.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('批量视频链接下载', style: AppTheme.fontTitle.copyWith(fontSize: 15)),
          SizedBox(height: 4),
          Text(
            '每行粘贴一个视频链接，点击“加入批量下载”将自动加入并发调度队列中',
            style: AppTheme.fontCaption.copyWith(color: context.textSecondary),
          ),
          SizedBox(height: AppTheme.space16),
          Expanded(
            child: TextField(
              controller: _batchController,
              maxLines: null,
              expands: true,
              style: TextStyle(color: context.textPrimary, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=...\nhttps://www.bilibili.com/video/BV...\nhttps://missav.ws/...',
                hintStyle: TextStyle(color: context.textSecondary, fontSize: 13),
                filled: true,
                fillColor: context.bgCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.borderSubtle)),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentSolid,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
              label: const Text('加入批量下载队列'),
              onPressed: _handleBatchDownload,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueTab() {
    return ListenableBuilder(
      listenable: _queue,
      builder: (context, _) {
        final tasks = _queue.tasks;

        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: context.textSecondary.withValues(alpha: 0.5)),
                SizedBox(height: 12),
                Text('暂无下载任务', style: TextStyle(color: context.textSecondary, fontSize: 13)),
              ],
            ),
          );
        }

        return Column(
          children: [
            // 队列顶栏操作
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: context.bgCard,
              child: Row(
                children: [
                  Text('共 ${tasks.length} 个任务', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                  Spacer(),
                  TextButton.icon(
                    icon: Icon(Icons.clear_all_rounded, size: 16),
                    label: Text('清空已完成', style: TextStyle(fontSize: 12)),
                    onPressed: () => _queue.clearFinished(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: tasks.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: context.borderSubtle),
                itemBuilder: (context, idx) {
                  final task = tasks[idx];
                  return _buildTaskTile(task);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTaskTile(DownloadTask task) {
    return ListenableBuilder(
      listenable: task,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 视频缩略图与状态角标
              Stack(
                children: [
                  MediaThumbnailWidget(
                    thumbnailPath: task.thumbnailUrl,
                    videoPathOrUrl: task.outputPath ?? task.url,
                    isOnline: task.url.startsWith('http'),
                    width: 64,
                    height: 44,
                    borderRadius: 6,
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _buildStatusIcon(task.status),
                    ),
                  ),
                ],
              ),
              SizedBox(width: 14),

              // 标题与进度
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 6),
                    // 进度条
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: task.status == DownloadStatus.completed
                            ? 1.0
                            : (task.progress > 0 ? task.progress : null),
                        backgroundColor: context.bgCard,
                        valueColor: AlwaysStoppedAnimation(
                          task.status == DownloadStatus.failed
                              ? context.errorSolid
                              : context.accentSolid,
                        ),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          task.status.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: task.status == DownloadStatus.failed
                                ? context.errorSolid
                                : (task.status == DownloadStatus.completed
                                    ? context.successSolid
                                    : context.accentSolid),
                          ),
                        ),
                        if (task.speed.isNotEmpty) ...[
                          SizedBox(width: 8),
                          Text('速度: ${task.speed}', style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        ],
                        if (task.eta.isNotEmpty) ...[
                          SizedBox(width: 8),
                          Text('剩余: ${task.eta}', style: TextStyle(color: context.textSecondary, fontSize: 11)),
                        ],
                        if (task.errorMessage != null && task.errorMessage!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              task.errorMessage!,
                              style: TextStyle(color: context.errorText, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // 操作按钮 (播放 / 离线生成中文字幕 / 访达 / 取消 / 重试)
              if (task.status == DownloadStatus.completed && task.outputPath != null) ...[
                IconButton(
                  icon: Icon(Icons.play_circle_fill_rounded, color: context.accentText, size: 24),
                  tooltip: '在播放器中播放',
                  onPressed: () {
                    widget.onPlayMedia(task.outputPath!, title: task.title, thumbnail: task.thumbnailUrl);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.subtitles_rounded, color: Colors.amber, size: 20),
                  tooltip: '离线生成并翻译中文字幕',
                  onPressed: () => _handleGenerateChineseSubtitles(task),
                ),
                IconButton(
                  icon: Icon(Icons.folder_open_rounded, color: context.textSecondary, size: 20),
                  tooltip: '在访达中显示',
                  onPressed: () {
                    PrivateStorageManager.instance.revealInFinder();
                  },
                ),
              ] else if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued) ...[
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.white70, size: 20),
                  tooltip: '取消任务',
                  onPressed: () => _queue.cancelTask(task.id),
                ),
              ] else if (task.status == DownloadStatus.failed || task.status == DownloadStatus.cancelled) ...[
                IconButton(
                  icon: const Icon(Icons.replay_rounded, color: Colors.white70, size: 20),
                  tooltip: '重试任务',
                  onPressed: () => _queue.retryTask(task.id),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleGenerateChineseSubtitles(DownloadTask task) async {
    final path = task.outputPath;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本地视频文件不存在，无法生成字幕'),
          backgroundColor: context.errorSolid,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OfflineSubtitleDialog(
        videoPath: path,
        title: task.title,
        onPlayMedia: (urlOrPath, title) => widget.onPlayMedia(urlOrPath, title: title, thumbnail: task.thumbnailUrl),
      ),
    );
  }

  Widget _buildStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return Icon(Icons.check_circle_rounded, color: context.successText, size: 14);
      case DownloadStatus.downloading:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: context.accentText),
        );
      case DownloadStatus.merging:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber),
        );
      case DownloadStatus.failed:
        return Icon(Icons.error_outline_rounded, color: context.errorText, size: 14);
      case DownloadStatus.cancelled:
        return const Icon(Icons.cancel_outlined, color: Colors.white38, size: 14);
      case DownloadStatus.queued:
        return const Icon(Icons.hourglass_empty_rounded, color: Colors.white54, size: 14);
    }
  }
}

/// 离线生成并翻译中文字幕进度弹窗
class _OfflineSubtitleDialog extends StatefulWidget {
  final String videoPath;
  final String title;
  final void Function(String path, String title) onPlayMedia;

  const _OfflineSubtitleDialog({
    required this.videoPath,
    required this.title,
    required this.onPlayMedia,
  });

  @override
  State<_OfflineSubtitleDialog> createState() => _OfflineSubtitleDialogState();
}

class _OfflineSubtitleDialogState extends State<_OfflineSubtitleDialog> {
  bool _isProcessing = true;
  String _statusText = '正在准备提取音频...';
  double? _progress;
  String _errorText = '';
  String? _savedSubtitlePath;

  @override
  void initState() {
    super.initState();
    _startOfflineSubtitles();
  }

  Future<void> _startOfflineSubtitles() async {
    try {
      final segments = await AiSubtitleService.instance.generateAndTranslateLocalSubtitles(
        localVideoPath: widget.videoPath,
        title: widget.title,
        bilingual: true,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _statusText = status;
              _progress = progress;
            });
          }
        },
      );

      final safeTitle = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final zhPath = p.join(PrivateStorageManager.instance.subtitlesDir.path, '${safeTitle}_zh.srt');

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _savedSubtitlePath = zhPath;
          _statusText = '字幕已成功生成并翻译完成！(共 ${segments.length} 句双语字幕)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorText = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderSubtle),
      ),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(AppTheme.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.subtitles_rounded, color: Colors.amber, size: 20),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '离线生成中文字幕',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                      Text(
                        widget.title,
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!_isProcessing)
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: context.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
            SizedBox(height: AppTheme.space20),
            if (_isProcessing) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: context.bgCard,
                  valueColor: AlwaysStoppedAnimation(Colors.amber),
                  minHeight: 6,
                ),
              ),
              SizedBox(height: 12),
              Text(
                _statusText,
                style: TextStyle(fontSize: 13, color: context.accentText),
              ),
              SizedBox(height: 6),
              Text(
                '全自动流水线：轻量音频切片 -> 并发语音转录 -> AI 文本大模型翻译为双语字幕',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ] else if (_errorText.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.errorText.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.errorText.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: context.errorText, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorText,
                        style: TextStyle(fontSize: 12, color: context.errorText),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.space16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
                    onPressed: () {
                      setState(() {
                        _isProcessing = true;
                        _errorText = '';
                        _statusText = '准备重试...';
                      });
                      _startOfflineSubtitles();
                    },
                    child: const Text('重试', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.successText.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.successText.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: context.successText, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusText,
                            style: TextStyle(fontSize: 13, color: context.successText, fontWeight: FontWeight.w500),
                          ),
                          if (_savedSubtitlePath != null) ...[
                            SizedBox(height: 4),
                            Text(
                              '已保存至: ${p.basename(_savedSubtitlePath!)}',
                              style: TextStyle(fontSize: 11, color: context.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.space20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentSolid,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                    label: const Text('立即播放'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onPlayMedia(widget.videoPath, widget.title);
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
