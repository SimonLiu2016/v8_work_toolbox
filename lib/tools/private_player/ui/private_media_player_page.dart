import 'package:flutter/material.dart';
import '../../../services/privacy_security_service.dart';
import '../../../theme/app_theme.dart';
import '../services/media_history_store.dart';
import '../services/private_player_controller.dart';
import '../services/private_storage_manager.dart';
import 'ai_subtitles_dialog.dart';
import 'online_download_panel.dart';
import 'private_player_view.dart';

/// 私密影音播放器整体工作台页面
class PrivateMediaPlayerPage extends StatefulWidget {
  const PrivateMediaPlayerPage({super.key});

  @override
  State<PrivateMediaPlayerPage> createState() => _PrivateMediaPlayerPageState();
}

class _PrivateMediaPlayerPageState extends State<PrivateMediaPlayerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _mainTabController;
  late final PrivatePlayerController _playerController;

  final MediaHistoryStore _historyStore = MediaHistoryStore.instance;
  final PrivacySecurityService _privacyService = PrivacySecurityService.instance;
  late final PlaybackInhibitor _playbackInhibitor;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 4, vsync: this);
    _playerController = PrivatePlayerController();

    // 注册媒体播放状态锁屏抑制器：播放中绝不触发自动锁定
    _playbackInhibitor = () => _playerController.isPlaying;
    _privacyService.registerPlaybackInhibitor(_playbackInhibitor);

    // 监听隐私锁状态：锁定时自动暂停播放，防止声音泄露
    _privacyService.isUnlockedNotifier.addListener(_onPrivacyLockStateChanged);
  }

  void _onPrivacyLockStateChanged() {
    if (!_privacyService.isUnlocked && _playerController.isPlaying) {
      _playerController.pause();
    }
  }

  @override
  void dispose() {
    _privacyService.unregisterPlaybackInhibitor(_playbackInhibitor);
    _privacyService.isUnlockedNotifier.removeListener(_onPrivacyLockStateChanged);
    _mainTabController.dispose();
    _playerController.dispose();
    super.dispose();
  }

  void _playMedia(String urlOrPath, {String? title, String? thumbnail}) {
    _playerController.open(
      urlOrPath,
      title: title,
      thumbnail: thumbnail,
    );
    _mainTabController.animateTo(0); // 切换至播放器 Tab
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (_) => _privacyService.recordActivity(),
      onPointerDown: (_) => _privacyService.recordActivity(),
      onPointerSignal: (_) => _privacyService.recordActivity(),
      child: Scaffold(
        backgroundColor: AppTheme.bgWindow,
        body: Column(
        children: [
          // 顶部应用导航栏
          Container(
            height: 48,
            color: AppTheme.bgSidebar,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: AppTheme.accent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '私密影音播放器',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 24),
                // Tab 切换
                TabBar(
                  controller: _mainTabController,
                  isScrollable: true,
                  indicatorColor: AppTheme.accent,
                  labelColor: AppTheme.accent,
                  unselectedLabelColor: AppTheme.textSecondary,
                  tabs: const [
                    Tab(icon: Icon(Icons.play_circle_outline, size: 16), text: '正在播放'),
                    Tab(icon: Icon(Icons.download_rounded, size: 16), text: '在线解析与下载'),
                    Tab(icon: Icon(Icons.history_rounded, size: 16), text: '播放历史'),
                    Tab(icon: Icon(Icons.star_border_rounded, size: 16), text: '我的收藏'),
                  ],
                ),
                const Spacer(),
                // 打开私密文件夹
                TextButton.icon(
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('私密目录', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
                  onPressed: () => PrivateStorageManager.instance.revealInFinder(),
                ),
                const SizedBox(width: 8),
                // 立即锁定
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.bgCard,
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: AppTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.lock_rounded, size: 14, color: AppTheme.accent),
                  label: const Text('锁定', style: TextStyle(fontSize: 12)),
                  onPressed: () => PrivacySecurityService.instance.lock(),
                ),
              ],
            ),
          ),

          // 核心视窗
          Expanded(
            child: TabBarView(
              controller: _mainTabController,
              children: [
                // Tab 0: 播放器视口
                PrivatePlayerView(
                  controller: _playerController,
                  onOpenSubtitlesDialog: () {
                    AiSubtitlesDialog.show(context, _playerController);
                  },
                ),

                // Tab 1: 在线视频解析与批量下载面板
                OnlineDownloadPanel(
                  onPlayMedia: _playMedia,
                ),

                // Tab 2: 播放历史
                _buildHistoryView(),

                // Tab 3: 我的收藏
                _buildFavoritesView(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildHistoryView() {
    return ListenableBuilder(
      listenable: _historyStore,
      builder: (context, _) {
        final history = _historyStore.history;
        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_toggle_off_rounded, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('暂无播放历史记录', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.bgCard,
              child: Row(
                children: [
                  Text('共 ${history.length} 条播放记录', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                    label: const Text('清空历史', style: TextStyle(fontSize: 12)),
                    onPressed: () => _historyStore.clearHistory(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: history.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderSubtle),
                itemBuilder: (context, idx) {
                  final item = history[idx];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        item.isOnline ? Icons.public_rounded : Icons.video_file_rounded,
                        color: AppTheme.accent,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '上次播放至: ${_formatDuration(item.lastPosition)} / ${_formatDuration(item.duration)}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${item.lastPlayedAt.year}-${item.lastPlayedAt.month.toString().padLeft(2, '0')}-${item.lastPlayedAt.day.toString().padLeft(2, '0')} ${item.lastPlayedAt.hour.toString().padLeft(2, '0')}:${item.lastPlayedAt.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                        if (item.progress > 0) ...[
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 2.5,
                            backgroundColor: AppTheme.bgCard,
                            valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                            color: item.isFavorite ? Colors.amber : AppTheme.textSecondary,
                            size: 20,
                          ),
                          onPressed: () => _historyStore.toggleFavorite(
                            urlOrPath: item.urlOrPath,
                            title: item.title,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accent, size: 24),
                          tooltip: '继续播放',
                          onPressed: () => _playMedia(item.urlOrPath, title: item.title, thumbnail: item.thumbnailUrl),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                          onPressed: () => _historyStore.removeHistory(item.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFavoritesView() {
    return ListenableBuilder(
      listenable: _historyStore,
      builder: (context, _) {
        final favs = _historyStore.favorites;
        if (favs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_border_rounded, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('暂无收藏内容', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: favs.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderSubtle),
          itemBuilder: (context, idx) {
            final item = favs[idx];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.amber,
                  size: 24,
                ),
              ),
              title: Text(
                item.title,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.urlOrPath,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow_rounded, color: AppTheme.accent, size: 24),
                    tooltip: '播放',
                    onPressed: () => _playMedia(item.urlOrPath, title: item.title, thumbnail: item.thumbnailUrl),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                    tooltip: '移除收藏',
                    onPressed: () => _historyStore.removeFavorite(item.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}
