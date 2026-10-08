import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/privacy_security_service.dart';
import '../../../services/proxy_settings.dart';
import '../../../shell/app_shell.dart';
import '../../../theme/app_theme.dart';
import '../../private_player/services/ai_subtitle_service.dart';
import '../../private_player/services/download_queue_manager.dart';
import '../../private_player/services/private_player_controller.dart';
import '../../private_player/services/private_storage_manager.dart';
import '../../private_player/services/thumbnail_manager.dart';
import '../../private_player/ui/ai_subtitles_dialog.dart';
import '../../private_player/ui/private_media_player_page.dart';
import '../services/ai_library_assistant_service.dart';
import '../services/private_browser_repository.dart';
import '../services/private_browser_service.dart';
import 'homepage_view.dart';

/// 隐私空间内置私密浏览器工作台页面
class PrivateBrowserPage extends StatefulWidget {
  final void Function(String urlOrPath, {String? title, String? thumbnail})? onPlayMedia;

  const PrivateBrowserPage({
    super.key,
    this.onPlayMedia,
  });

  @override
  State<PrivateBrowserPage> createState() => _PrivateBrowserPageState();
}

class _PrivateBrowserPageState extends State<PrivateBrowserPage> {
  final PrivateBrowserService _browserService = PrivateBrowserService.instance;
  final PrivacySecurityService _privacyService = PrivacySecurityService.instance;
  final DownloadQueueManager _downloadManager = DownloadQueueManager.instance;
  final ProxySettings _proxySettings = ProxySettings.instance;

  final TextEditingController _urlBarController = TextEditingController();
  final FocusNode _urlBarFocusNode = FocusNode();

  bool _isBookmarked = false;
  bool _isVideoBookmarked = false;
  bool _showBookmarksDropdown = false;
  bool _showDownloadsDrawer = false;
  List<BrowserBookmarkItem> _bookmarksList = [];

  // 当前下载状态映射 (url -> task)
  final Map<String, DownloadTask> _activeDownloads = {};

  @override
  void initState() {
    super.initState();
    _browserService.init();
    _browserService.addListener(_onBrowserServiceUpdated);
    _downloadManager.addListener(_onDownloadManagerUpdated);
    _privacyService.isUnlockedNotifier.addListener(_onPrivacyLockChanged);

    // 绑定视频浮动工具栏的回调触发
    _browserService.onDownloadRequested = _handleDownloadRequested;
    _browserService.onCachePlayRequested = _handleCachePlayRequested;
    _browserService.onFavoriteRequested = _handleFavoriteRequested;
    _browserService.onSubtitleRequested = _handleSubtitleRequested;

    _loadBookmarks();
  }

  @override
  void dispose() {
    _browserService.removeListener(_onBrowserServiceUpdated);
    _downloadManager.removeListener(_onDownloadManagerUpdated);
    _privacyService.isUnlockedNotifier.removeListener(_onPrivacyLockChanged);
    _urlBarController.dispose();
    _urlBarFocusNode.dispose();
    super.dispose();
  }

  void _onDownloadManagerUpdated() {
    if (!mounted) return;
    final task = _getCurrentPageTask();
    if (task != null) {
      if (task.status == DownloadStatus.downloading) {
        _browserService.updateNativeDownloadStatus(progress: task.progress, status: 'downloading');
      } else if (task.status == DownloadStatus.completed) {
        _browserService.updateNativeDownloadStatus(progress: 1.0, status: 'completed');
      } else if (task.status == DownloadStatus.failed) {
        _browserService.updateNativeDownloadStatus(progress: 0.0, status: 'failed');
      }
    }
    setState(() {});
  }

  void _onBrowserServiceUpdated() {
    if (mounted) {
      final currentUrl = _browserService.activeTab?.url ?? '';
      if (!_urlBarFocusNode.hasFocus && _urlBarController.text != currentUrl) {
        _urlBarController.text = currentUrl;
      }
      _checkIsBookmarked(currentUrl);
      setState(() {});
    }
  }

  void _onPrivacyLockChanged() {
    if (!_privacyService.isUnlocked) {
      _browserService.onPrivacyLocked();
    }
  }

  Future<void> _loadBookmarks() async {
    final list = await _browserService.repository.getBookmarks();
    if (mounted) {
      setState(() {
        _bookmarksList = list;
      });
    }
  }

  Future<void> _checkIsBookmarked(String url) async {
    if (url.isEmpty) {
      setState(() {
        _isBookmarked = false;
        _isVideoBookmarked = false;
      });
      _browserService.updateNativeFavoriteStatus(false);
      return;
    }
    final bookmarked = await _browserService.repository.isBookmarked(url);
    final videoBookmarked = await _browserService.repository.isVideoBookmarked(url);
    if (mounted) {
      setState(() {
        _isBookmarked = bookmarked;
        _isVideoBookmarked = videoBookmarked;
      });
    }
    _browserService.updateNativeFavoriteStatus(videoBookmarked);
  }

  DownloadTask? _getCurrentPageTask() {
    final activeUrl = _browserService.activeTab?.url ?? '';
    final detectedUrl = _browserService.detectedVideoUrl ?? '';
    for (final t in _downloadManager.tasks.reversed) {
      if ((activeUrl.isNotEmpty && t.url == activeUrl) ||
          (detectedUrl.isNotEmpty && t.url == detectedUrl)) {
        return t;
      }
    }
    if (activeUrl.isNotEmpty && _activeDownloads.containsKey(activeUrl)) {
      return _activeDownloads[activeUrl];
    }
    if (detectedUrl.isNotEmpty && _activeDownloads.containsKey(detectedUrl)) {
      return _activeDownloads[detectedUrl];
    }
    return null;
  }

  Future<void> _toggleBookmarkCurrentPage() async {
    final active = _browserService.activeTab;
    if (active == null || active.url.isEmpty) return;

    if (_isBookmarked) {
      // 移除书签
      final all = await _browserService.repository.getBookmarks();
      final match = all.firstWhere((b) => b.url == active.url, orElse: () => all.first);
      await _browserService.repository.removeBookmark(match.id);
      _checkIsBookmarked(active.url);
      _loadBookmarks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已从书签中移除'), duration: Duration(seconds: 1)),
        );
      }
    } else {
      // 添加书签
      final item = BrowserBookmarkItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        url: active.url,
        title: active.title.isNotEmpty ? active.title : active.url,
        createdAt: DateTime.now(),
      );
      await _browserService.repository.addBookmark(item);
      _checkIsBookmarked(active.url);
      _loadBookmarks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已成功加入书签 ★'), duration: Duration(seconds: 1)),
        );
      }
    }
  }

  void _navigateToUrl(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      // 正常完整 URL
    } else if (trimmed.contains('.') && !trimmed.contains(' ')) {
      trimmed = 'https://$trimmed';
    } else {
      trimmed = 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    }

    _urlBarController.text = trimmed;
    _browserService.openNativeBrowser(url: trimmed);
  }

  // ---------------------------------------------------------------------------
  // 视频增强层动作处理 (下载、缓存播放、收藏、字幕)
  // ---------------------------------------------------------------------------

  void _handleDownloadRequested(String url, String title, {String? videoSrc, String? thumbnail}) {
    if (url.isEmpty) return;
    final effectiveTitle = (title.trim().isNotEmpty && title != '网页视频' && title != '未命名视频')
        ? title.trim()
        : (_browserService.detectedVideoTitle?.trim().isNotEmpty == true
            ? _browserService.detectedVideoTitle!.trim()
            : (_browserService.activeTab?.title.trim().isNotEmpty == true
                ? _browserService.activeTab!.title.trim()
                : '网页视频'));
    final effectiveVideoSrc = videoSrc ?? _browserService.detectedVideoSrc;
    final effectiveThumbnail = thumbnail ?? _browserService.detectedVideoThumbnail;

    final task = _downloadManager.addTask(
      url,
      title: effectiveTitle,
      triggeredBy: 'browser',
      directStreamUrl: effectiveVideoSrc,
      thumbnailUrl: effectiveThumbnail,
    );
    setState(() {
      _activeDownloads[url] = task;
    });

    _browserService.updateNativeDownloadStatus(progress: 0.01, status: 'downloading');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入私密下载队列: ${task.title}'),
        action: SnackBarAction(
          label: '查看队列',
          onPressed: () {
            setState(() {
              _showDownloadsDrawer = true;
              _showBookmarksDropdown = false;
            });
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleCachePlayRequested(String url, String title, {String? videoSrc, String? thumbnail}) {
    if (url.isEmpty) return;
    final effectiveTitle = (title.trim().isNotEmpty && title != '网页视频' && title != '未命名视频')
        ? title.trim()
        : (_browserService.detectedVideoTitle?.trim().isNotEmpty == true
            ? _browserService.detectedVideoTitle!.trim()
            : (_browserService.activeTab?.title.trim().isNotEmpty == true
                ? _browserService.activeTab!.title.trim()
                : '网页视频'));
    final effectiveVideoSrc = videoSrc ?? _browserService.detectedVideoSrc;
    final effectiveThumbnail = thumbnail ?? _browserService.detectedVideoThumbnail;

    final task = _downloadManager.addTask(
      url,
      title: effectiveTitle,
      triggeredBy: 'browser',
      directStreamUrl: effectiveVideoSrc,
      thumbnailUrl: effectiveThumbnail,
    );
    setState(() {
      _activeDownloads[url] = task;
    });

    _browserService.updateNativeDownloadStatus(progress: 0.01, status: 'downloading');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在高速缓存，完成后将自动在私密播放器启动: ${task.title}'),
        action: SnackBarAction(
          label: '查看进度',
          onPressed: () {
            setState(() {
              _showDownloadsDrawer = true;
              _showBookmarksDropdown = false;
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    // 监听任务状态，完成后自动调用私密播放器打开
    void listener() {
      if (task.status == DownloadStatus.completed && task.outputPath != null) {
        task.removeListener(listener);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ 缓存完成，已切换至私密影音播放器: ${task.title}'),
              duration: const Duration(seconds: 2),
            ),
          );
          // 广播播放请求
          PrivateMediaPlayerPage.requestPlay(
            task.outputPath!,
            title: task.title,
            thumbnail: task.thumbnailUrl,
          );
          // 自动跳转至私密影音播放器页面
          AppShellState.current?.selectTool('private-media-player');
          // 回调可能注入的页面监听
          widget.onPlayMedia?.call(
            task.outputPath!,
            title: task.title,
            thumbnail: task.thumbnailUrl,
          );
        }
      }
    }

    task.addListener(listener);
  }

  Future<void> _handleFavoriteRequested(String url, String title, {String? videoSrc, String? thumbnail}) async {
    if (url.isEmpty) return;

    final existing = await _browserService.repository.getVideoBookmarkByUrl(url);
    if (existing != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('此视频已在私密视频库中: ${existing.title}'),
            action: SnackBarAction(
              label: '前往视频库',
              onPressed: () => AppShellState.current?.selectTool('video-library'),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final platform = _guessPlatformFromUrl(url);
    final effectiveTitle = (title.trim().isNotEmpty && title != '网页视频' && title != '未命名视频')
        ? title.trim()
        : (_browserService.detectedVideoTitle?.trim().isNotEmpty == true
            ? _browserService.detectedVideoTitle!.trim()
            : (_browserService.activeTab?.title.trim().isNotEmpty == true
                ? _browserService.activeTab!.title.trim()
                : '网页视频'));
    final effectiveThumbnail = thumbnail ?? _browserService.detectedVideoThumbnail;

    final bookmark = VideoBookmarkItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: effectiveTitle,
      url: url,
      platform: platform,
      addedAt: DateTime.now(),
    );

    await _browserService.repository.addVideoBookmark(bookmark);

    if (mounted) {
      setState(() {
        _isVideoBookmarked = true;
      });
      _browserService.updateNativeFavoriteStatus(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('★ 已收藏到私密视频库: ${bookmark.title}'),
          action: SnackBarAction(
            label: '前往视频库',
            onPressed: () => AppShellState.current?.selectTool('video-library'),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // 后台异步进行 AI 自动标签生成与缩略图本地缓存落盘
    _triggerBackgroundTaggingAndThumbnail(bookmark, remoteThumbnailUrl: effectiveThumbnail);
  }

  Future<void> _triggerBackgroundTaggingAndThumbnail(VideoBookmarkItem bookmark, {String? remoteThumbnailUrl}) async {
    try {
      final localThumb = await ThumbnailManager.instance.getOrCreateThumbnail(
        bookmark.url,
        remoteThumbnailUrl: remoteThumbnailUrl ?? _browserService.detectedVideoThumbnail,
      );
      final analysis = await AILibraryAssistantService.instance.analyzeVideoBookmark(
        title: bookmark.title,
        platform: bookmark.platform,
        url: bookmark.url,
      );

      final tagIds = <String>[];
      for (final tagName in analysis.tags) {
        final tag = await _browserService.repository.getOrCreateTag(tagName);
        tagIds.add(tag.id);
      }

      final updated = bookmark.copyWith(
        thumbnailPath: localThumb,
        aiSummary: analysis.summary.isNotEmpty ? analysis.summary : bookmark.aiSummary,
        aiTags: analysis.tags.isNotEmpty ? analysis.tags : bookmark.aiTags,
        tagIds: tagIds.isNotEmpty ? tagIds : bookmark.tagIds,
      );
      await _browserService.repository.updateVideoBookmark(updated);
    } catch (e) {
      debugPrint('后台提取标签及缩略图失败: $e');
    }
  }

  void _handleSubtitleRequested(String url) {
    _showBrowserSubtitleDialog(url);
  }

  String _guessPlatformFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube')) return 'YouTube';
    if (lower.contains('bilibili')) return 'Bilibili';
    if (lower.contains('missav')) return 'MissAV';
    if (lower.contains('jav.sb') || lower.contains('jav')) return 'jav.sb';
    if (lower.contains('91porn')) return '91porn';
    if (lower.contains('pornhub')) return 'PornHub';
    if (lower.contains('pornlulu')) return 'PornLulu';
    return 'Web';
  }

  // ---------------------------------------------------------------------------
  // 字幕面板弹窗
  // ---------------------------------------------------------------------------

  Future<void> _showBrowserSubtitleDialog(String videoUrl) async {
    bool isExtracting = false;
    String statusText = '选择字幕提取或生成模式';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: context.bgCard,
          title: Row(
            children: [
              Icon(Icons.subtitles_rounded, color: context.accentSolid, size: 20),
              const SizedBox(width: 8),
              Text('网页视频字幕增强', style: TextStyle(color: context.textPrimary, fontSize: 16)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前视频: ${_browserService.detectedVideoTitle ?? videoUrl}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.bgWindow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: context.accentText, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
                if (isExtracting)
                  const Center(child: CircularProgressIndicator())
                else
                  Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flash_on_rounded, color: Colors.amber),
                        title: const Text('快速提取原生字幕', style: TextStyle(fontSize: 14)),
                        subtitle: const Text('优先拉取 YouTube/Bilibili 等平台自带或自动生成的软字幕 (最快)', style: TextStyle(fontSize: 11)),
                        onTap: () async {
                          setDlgState(() {
                            isExtracting = true;
                            statusText = '正在通过 yt-dlp 快速拉取内置软字幕...';
                          });
                          try {
                            final subtitles = await AiSubtitleService.instance.fastGenerateSubtitles(
                              videoPathOrUrl: videoUrl,
                              title: _browserService.detectedVideoTitle ?? '网页视频',
                              onProgress: (status, _) {
                                if (ctx.mounted) setDlgState(() => statusText = status);
                              },
                            );
                            if (subtitles.isNotEmpty) {
                              final jsonList = subtitles.map((s) => s.toJson()).toList();
                              await _browserService.mountSubtitles(jsonList);
                              setDlgState(() {
                                isExtracting = false;
                                statusText = '✅ 提取成功！已在浏览器内同步加载 ${subtitles.length} 条字幕';
                              });
                            } else {
                              setDlgState(() {
                                isExtracting = false;
                                statusText = '未检测到原生字幕，建议尝试「AI 语音识别生成」';
                              });
                            }
                          } catch (e) {
                            setDlgState(() {
                              isExtracting = false;
                              statusText = '提取异常: $e';
                            });
                          }
                        },
                      ),
                      const Divider(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.auto_awesome_rounded, color: context.accentSolid),
                        title: const Text('AI 语音识别生成 (STT)', style: TextStyle(fontSize: 14)),
                        subtitle: const Text('提取音频切片并调用 Whisper / MiMo ASR 识别全片字幕与中文翻译', style: TextStyle(fontSize: 11)),
                        onTap: () async {
                          setDlgState(() {
                            isExtracting = true;
                            statusText = '正在使用 AI STT 分析全视频音频...';
                          });
                          try {
                            final subtitles = await AiSubtitleService.instance.generateFullSubtitles(
                              videoPathOrUrl: videoUrl,
                              totalDuration: const Duration(minutes: 10),
                              onProgress: (prog, msg) {
                                if (ctx.mounted) setDlgState(() => statusText = msg);
                              },
                            );
                            final jsonList = subtitles.map((s) => s.toJson()).toList();
                            await _browserService.mountSubtitles(jsonList);
                            setDlgState(() {
                              isExtracting = false;
                              statusText = '✅ AI 字幕生成完毕，已挂载至浏览器 Overlay！';
                            });
                          } catch (e) {
                            setDlgState(() {
                              isExtracting = false;
                              statusText = '生成失败: $e';
                            });
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('关闭', style: TextStyle(color: context.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (_) => _privacyService.recordActivity(),
      onPointerDown: (_) => _privacyService.recordActivity(),
      child: Scaffold(
        backgroundColor: context.bgWindow,
        body: Column(
          children: [
            // 1. 顶部浏览器标签栏 (Tab Bar)
            _buildTabBar(),

            // 2. 地址栏与主控制工具栏
            _buildAddressBar(),

            // 3. 核心视窗展示区 (空标签显示 N 宫格首页；有 URL 时显示主视窗与原生浏览器唤起卡)
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 38,
      color: context.bgSidebar,
      padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _browserService.tabs.length,
              itemBuilder: (ctx, idx) {
                final tab = _browserService.tabs[idx];
                final isActive = idx == _browserService.activeTabIndex;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _browserService.switchTab(idx),
                    child: Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isActive ? context.bgWindow : Colors.transparent,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        border: Border(
                          top: BorderSide(color: isActive ? context.accentSolid : Colors.transparent, width: 2),
                          left: BorderSide(color: context.borderSubtle),
                          right: BorderSide(color: context.borderSubtle),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            tab.url.isEmpty ? Icons.home_rounded : Icons.public_rounded,
                            size: 14,
                            color: isActive ? context.accentText : context.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tab.title.isNotEmpty ? tab.title : '新标签页',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isActive ? context.textPrimary : context.textSecondary,
                                fontSize: 12,
                                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _browserService.closeTab(idx),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded, size: 12, color: context.textTertiary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 新建标签页按钮
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 16),
            tooltip: '新建标签页',
            color: context.textSecondary,
            onPressed: () => _browserService.createTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBar() {
    final activeTab = _browserService.activeTab;
    final isPageLoaded = activeTab != null && activeTab.url.isNotEmpty;

    return Container(
      height: 44,
      color: context.bgWindow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // 后退 / 前进 / 刷新
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
            tooltip: '后退',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: context.textSecondary,
            onPressed: isPageLoaded ? () => _browserService.goBack() : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            tooltip: '前进',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: context.textSecondary,
            onPressed: isPageLoaded ? () => _browserService.goForward() : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            tooltip: '刷新',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: context.textSecondary,
            onPressed: isPageLoaded ? () => _browserService.reload() : null,
          ),
          const SizedBox(width: 8),

          // 主地址输入栏
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.borderSubtle),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    _urlBarController.text.startsWith('https://')
                        ? Icons.lock_outline_rounded
                        : Icons.language_rounded,
                    size: 14,
                    color: context.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlBarController,
                      focusNode: _urlBarFocusNode,
                      style: TextStyle(color: context.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: '输入网址或搜索...',
                        hintStyle: TextStyle(color: context.textTertiary, fontSize: 12),
                      ),
                      onSubmitted: _navigateToUrl,
                    ),
                  ),
                  // 书签 ★ 按钮
                  IconButton(
                    icon: Icon(
                      _isBookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 16,
                      color: _isBookmarked ? Colors.amber : context.textTertiary,
                    ),
                    tooltip: _isBookmarked ? '从书签移除' : '添加至书签',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: _toggleBookmarkCurrentPage,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 网络代理状态指示器
          Tooltip(
            message: _proxySettings.isConfigured
                ? '网络代理: 已启用 (${_proxySettings.host}:${_proxySettings.port})'
                : '网络代理: 未启用 (直连)',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _proxySettings.isConfigured
                    ? (context.isDarkMode ? const Color(0x2622C55E) : const Color(0xFFDCFCE7))
                    : context.bgCard,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _proxySettings.isConfigured
                      ? (context.isDarkMode ? const Color(0x6622C55E) : const Color(0xFF86EFAC))
                      : context.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 13,
                    color: _proxySettings.isConfigured
                        ? (context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                        : context.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _proxySettings.isConfigured ? '代理已激活' : '直连',
                    style: TextStyle(
                      color: _proxySettings.isConfigured
                          ? (context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                          : context.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 下载与缓存管理抽屉按钮
          Builder(
            builder: (ctx) {
              final activeCount = _downloadManager.tasks.where((t) =>
                  t.status == DownloadStatus.downloading ||
                  t.status == DownloadStatus.queued ||
                  t.status == DownloadStatus.merging).length;
              final totalCount = _downloadManager.tasks.length;
              return Tooltip(
                message: activeCount > 0 ? '正在下载 ($activeCount 个任务运行中)' : '下载与缓存管理 ($totalCount)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() {
                      _showDownloadsDrawer = !_showDownloadsDrawer;
                      if (_showDownloadsDrawer) _showBookmarksDropdown = false;
                    });
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _showDownloadsDrawer
                          ? context.accentSolid.withOpacity(0.15)
                          : (_downloadManager.tasks.isNotEmpty ? context.bgCard : Colors.transparent),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _showDownloadsDrawer
                            ? context.accentSolid
                            : (_downloadManager.tasks.isNotEmpty ? context.borderSubtle : Colors.transparent),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          activeCount > 0 ? Icons.downloading_rounded : Icons.download_rounded,
                          size: 15,
                          color: activeCount > 0 ? context.accentSolid : context.textSecondary,
                        ),
                        if (totalCount > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: activeCount > 0 ? context.accentSolid : context.borderSubtle,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              activeCount > 0 ? '$activeCount' : '$totalCount',
                              style: TextStyle(
                                color: activeCount > 0 ? Colors.white : context.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),

          // 私密视频库快捷入口
          IconButton(
            icon: const Icon(Icons.video_library_rounded, size: 16),
            tooltip: '前往私密视频库',
            color: context.textSecondary,
            onPressed: () {
              AppShellState.current?.selectTool('video-library');
            },
          ),
          const SizedBox(width: 6),

          // 书签库抽屉切换按钮
          IconButton(
            icon: Icon(
              Icons.bookmarks_outlined,
              size: 16,
              color: _showBookmarksDropdown ? context.accentText : context.textSecondary,
            ),
            tooltip: '已存书签',
            onPressed: () {
              setState(() {
                _showBookmarksDropdown = !_showBookmarksDropdown;
                if (_showBookmarksDropdown) _showDownloadsDrawer = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    final activeTab = _browserService.activeTab;

    if (activeTab == null || activeTab.url.isEmpty) {
      // 当前为空白页 -> 渲染优雅的 N 宫格首页
      return HomepageView(
        onOpenUrl: (url) {
          _navigateToUrl(url);
        },
      );
    }

    final currentTask = _getCurrentPageTask();
    final isCurDownloading = currentTask != null &&
        (currentTask.status == DownloadStatus.downloading ||
            currentTask.status == DownloadStatus.merging ||
            currentTask.status == DownloadStatus.queued);
    final isCurDone = currentTask != null && currentTask.status == DownloadStatus.completed;

    // 已经加载了网页：主视区展示网页控制工作台与视频探测状态
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: context.bgWindow,
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.open_in_new_rounded, color: context.accentText, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  activeTab.title.isNotEmpty ? activeTab.title : '已打开网页',
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.accentSolid,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.fullscreen_rounded, size: 16),
                                label: const Text('置顶浏览器视窗'),
                                onPressed: () => _browserService.openNativeBrowser(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            activeTab.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.textTertiary, fontSize: 12),
                          ),
                          const Divider(height: 24),

                          // 视频增强实时状态
                          if (_browserService.isVideoDetected) ...[
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '已精准探测到视频媒体流',
                                  style: TextStyle(
                                    color: context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isCurDownloading ? context.accentSolid.withOpacity(0.12) : context.bgCard,
                                    foregroundColor: isCurDownloading ? context.accentText : context.textPrimary,
                                    elevation: 0,
                                    side: BorderSide(
                                      color: isCurDownloading ? context.accentSolid : context.borderSubtle,
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: Icon(
                                    isCurDownloading ? Icons.downloading_rounded : Icons.download_rounded,
                                    size: 14,
                                    color: isCurDownloading ? context.accentSolid : context.accentText,
                                  ),
                                  label: Text(
                                    isCurDownloading
                                        ? '下载中 ${(currentTask!.progress * 100).toInt()}%'
                                        : (isCurDone ? '✓ 下载完成' : '一键私密下载'),
                                  ),
                                  onPressed: () => _handleDownloadRequested(
                                    activeTab.url,
                                    _browserService.detectedVideoTitle ?? activeTab.title,
                                    videoSrc: _browserService.detectedVideoSrc,
                                    thumbnail: _browserService.detectedVideoThumbnail,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: context.bgCard,
                                    foregroundColor: context.textPrimary,
                                    elevation: 0,
                                    side: BorderSide(color: context.borderSubtle),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: Icon(Icons.play_arrow_rounded, size: 14, color: context.accentText),
                                  label: Text(
                                    isCurDownloading
                                        ? '缓存中 ${(currentTask!.progress * 100).toInt()}%'
                                        : '缓存后直接播放',
                                  ),
                                  onPressed: () => _handleCachePlayRequested(
                                    activeTab.url,
                                    _browserService.detectedVideoTitle ?? activeTab.title,
                                    videoSrc: _browserService.detectedVideoSrc,
                                    thumbnail: _browserService.detectedVideoThumbnail,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isVideoBookmarked
                                        ? (context.isDarkMode ? const Color(0x33F59E0B) : const Color(0xFFFEF3C7))
                                        : context.bgCard,
                                    foregroundColor: _isVideoBookmarked
                                        ? (context.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
                                        : context.textPrimary,
                                    elevation: 0,
                                    side: BorderSide(
                                      color: _isVideoBookmarked
                                          ? (context.isDarkMode ? const Color(0x66F59E0B) : const Color(0xFFFCD34D))
                                          : context.borderSubtle,
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: Icon(
                                    _isVideoBookmarked ? Icons.star_rounded : Icons.star_border_rounded,
                                    size: 14,
                                    color: _isVideoBookmarked ? Colors.amber : context.textSecondary,
                                  ),
                                  label: Text(_isVideoBookmarked ? '✓ 已在私密视频库' : '加入私密视频库'),
                                  onPressed: () => _handleFavoriteRequested(
                                    activeTab.url,
                                    _browserService.detectedVideoTitle ?? activeTab.title,
                                    videoSrc: _browserService.detectedVideoSrc,
                                    thumbnail: _browserService.detectedVideoThumbnail,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: context.bgCard,
                                    foregroundColor: context.textPrimary,
                                    elevation: 0,
                                    side: BorderSide(color: context.borderSubtle),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: Icon(Icons.subtitles_rounded, size: 14, color: context.accentText),
                                  label: const Text('AI 字幕与翻译'),
                                  onPressed: () => _handleSubtitleRequested(activeTab.url),
                                ),
                              ],
                            ),

                            // 原地实时下载与缓存进度卡片
                            if (currentTask != null) ...[
                              const SizedBox(height: 16),
                              _buildTaskProgressCard(currentTask),
                            ],
                          ] else ...[
                            Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: context.textTertiary),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '正在监听网页视频加载...',
                                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                            // 如果页面正在下载此前探测到的任务，也展示进度卡片
                            if (currentTask != null) ...[
                              const SizedBox(height: 16),
                              _buildTaskProgressCard(currentTask),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 书签侧边抽屉
        if (_showBookmarksDropdown)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 280,
            child: Container(
              decoration: BoxDecoration(
                color: context.bgCard,
                border: Border(left: BorderSide(color: context.borderSubtle)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(-2, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: context.bgSidebar,
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(
                          '书签收藏夹 (${_bookmarksList.length})',
                          style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () => setState(() => _showBookmarksDropdown = false),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _bookmarksList.isEmpty
                        ? Center(child: Text('暂无书签', style: TextStyle(color: context.textTertiary)))
                        : ListView.separated(
                            itemCount: _bookmarksList.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: context.borderSubtle),
                            itemBuilder: (ctx, idx) {
                              final b = _bookmarksList[idx];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                                ),
                                subtitle: Text(
                                  b.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                                  onPressed: () async {
                                    await _browserService.repository.removeBookmark(b.id);
                                    _loadBookmarks();
                                    _checkIsBookmarked(_browserService.activeTab?.url ?? '');
                                  },
                                ),
                                onTap: () {
                                  setState(() => _showBookmarksDropdown = false);
                                  _navigateToUrl(b.url);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

        // 下载与缓存管理抽屉
        if (_showDownloadsDrawer)
          _buildDownloadsDrawer(),
      ],
    );
  }

  /// 原地实时下载与缓存进度展示卡片
  Widget _buildTaskProgressCard(DownloadTask task) {
    final isDone = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed;
    final isCancelled = task.status == DownloadStatus.cancelled;
    final isRunning = task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.merging ||
        task.status == DownloadStatus.queued;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isDone) {
      statusColor = context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
      statusIcon = Icons.check_circle_rounded;
      statusText = '已完成下载与合成';
    } else if (isFailed) {
      statusColor = Colors.redAccent;
      statusIcon = Icons.error_rounded;
      statusText = '下载失败: ${task.errorMessage ?? "未知错误"}';
    } else if (isCancelled) {
      statusColor = context.textTertiary;
      statusIcon = Icons.cancel_outlined;
      statusText = '任务已取消';
    } else if (task.status == DownloadStatus.merging) {
      statusColor = Colors.orangeAccent;
      statusIcon = Icons.auto_fix_high_rounded;
      statusText = '媒体流合成中...';
    } else if (task.status == DownloadStatus.downloading) {
      statusColor = context.accentSolid;
      statusIcon = Icons.downloading_rounded;
      statusText = '正在下载 ${(task.progress * 100).toStringAsFixed(1)}%';
    } else {
      statusColor = context.textSecondary;
      statusIcon = Icons.schedule_rounded;
      statusText = '排队等待中...';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDarkMode ? const Color(0x221E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRunning ? context.accentSolid.withOpacity(0.4) : context.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isDone ? 1.0 : (isRunning ? task.progress : 0.0),
              backgroundColor: context.borderSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (isRunning && task.speed.isNotEmpty) ...[
                Text(
                  '⚡ 速度: ${task.speed}',
                  style: TextStyle(color: context.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 12),
              ],
              if (isRunning && task.eta.isNotEmpty) ...[
                Text(
                  '⏱ 剩余: ${task.eta}',
                  style: TextStyle(color: context.textSecondary, fontSize: 11),
                ),
              ],
              const Spacer(),
              if (isRunning) ...[
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 13),
                  label: const Text('取消', style: TextStyle(fontSize: 11)),
                  onPressed: () => task.cancel(),
                ),
              ],
              if (isDone && task.outputPath != null) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentSolid,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 14),
                  label: const Text('立即在私密播放器播放', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: () {
                    PrivateMediaPlayerPage.requestPlay(
                      task.outputPath!,
                      title: task.title,
                      thumbnail: task.thumbnailUrl,
                    );
                    AppShellState.current?.selectTool('private-media-player');
                    widget.onPlayMedia?.call(task.outputPath!, title: task.title, thumbnail: task.thumbnailUrl);
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.borderSubtle),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 14),
                  label: const Text('访达定位', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Process.run('open', ['-R', task.outputPath!]);
                  },
                ),
              ],
              if (isFailed || isCancelled) ...[
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: context.accentText,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 13),
                  label: const Text('重试', style: TextStyle(fontSize: 11)),
                  onPressed: () => _downloadManager.retryTask(task.id),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 下载与缓存全局管理抽屉
  Widget _buildDownloadsDrawer() {
    final tasks = _downloadManager.tasks.reversed.toList();
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 380,
      child: Container(
        decoration: BoxDecoration(
          color: context.bgCard,
          border: Border(left: BorderSide(color: context.borderSubtle)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(-4, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: context.bgSidebar,
              child: Row(
                children: [
                  Icon(Icons.download_rounded, size: 16, color: context.accentSolid),
                  const SizedBox(width: 8),
                  Text(
                    '下载与缓存任务 (${tasks.length})',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (tasks.any((t) =>
                      t.status == DownloadStatus.completed ||
                      t.status == DownloadStatus.failed ||
                      t.status == DownloadStatus.cancelled))
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _downloadManager.clearFinished(),
                      child: Text('清除完成项', style: TextStyle(fontSize: 11, color: context.textTertiary)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => setState(() => _showDownloadsDrawer = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_done_rounded, size: 36, color: context.textTertiary),
                          const SizedBox(height: 8),
                          Text('暂无下载或缓存任务', style: TextStyle(color: context.textTertiary, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: context.borderSubtle),
                      itemBuilder: (ctx, idx) {
                        final t = tasks[idx];
                        final isDone = t.status == DownloadStatus.completed;
                        final isDownloading = t.status == DownloadStatus.downloading || t.status == DownloadStatus.merging;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (isDownloading)
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 14),
                                      tooltip: '取消',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                      onPressed: () => t.cancel(),
                                    ),
                                  if (isDone && t.outputPath != null)
                                    IconButton(
                                      icon: Icon(Icons.play_circle_fill_rounded, size: 18, color: context.accentSolid),
                                      tooltip: '立即在播放器播放',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                      onPressed: () {
                                        PrivateMediaPlayerPage.requestPlay(
                                          t.outputPath!,
                                          title: t.title,
                                          thumbnail: t.thumbnailUrl,
                                        );
                                        AppShellState.current?.selectTool('private-media-player');
                                        widget.onPlayMedia?.call(t.outputPath!, title: t.title, thumbnail: t.thumbnailUrl);
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: isDone ? 1.0 : (isDownloading ? t.progress : 0.0),
                                  minHeight: 4,
                                  backgroundColor: context.borderSubtle,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDone
                                        ? (context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                                        : (t.status == DownloadStatus.failed ? Colors.redAccent : context.accentSolid),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    isDone
                                        ? '已完成'
                                        : (isDownloading
                                            ? '${(t.progress * 100).toInt()}% · ${t.speed.isNotEmpty ? t.speed : "下载中"}'
                                            : t.status.label),
                                    style: TextStyle(
                                      color: isDone
                                          ? (context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                                          : context.textTertiary,
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (t.eta.isNotEmpty && isDownloading) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '剩余 ${t.eta}',
                                      style: TextStyle(color: context.textTertiary, fontSize: 10),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (isDone && t.outputPath != null)
                                    GestureDetector(
                                      onTap: () => Process.run('open', ['-R', t.outputPath!]),
                                      child: Text(
                                        '访达',
                                        style: TextStyle(color: context.accentText, fontSize: 10),
                                      ),
                                    ),
                                  if (t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled)
                                    GestureDetector(
                                      onTap: () => _downloadManager.retryTask(t.id),
                                      child: Text(
                                        '重试',
                                        style: TextStyle(color: context.accentText, fontSize: 10),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
