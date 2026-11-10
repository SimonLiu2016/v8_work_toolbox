import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../services/privacy_security_service.dart';
import '../../private_player/services/download_queue_manager.dart';
import '../models/drama_models.dart';
import 'casual_short_drama_store.dart';
import 'drama_cover_decryptor.dart';
import 'huangguo_api_client.dart';

/// 随心短剧核心控制器
/// 负责驱动媒体播放、选集连播、进度落盘、隐私锁硬联动及离线下载
class CasualShortDramaController extends ChangeNotifier {
  CasualShortDramaController({
    HuangguoApiClient? apiClient,
    CasualShortDramaStore? store,
    DramaCoverDecryptor? decryptor,
    PrivacySecurityService? privacyService,
  })  : _apiClient = apiClient ?? HuangguoApiClient.instance,
        _store = store ?? CasualShortDramaStore.instance,
        _privacyService = privacyService ?? PrivacySecurityService.instance {
    _initPlayer();
    _bindSecurityListener();
  }

  static CasualShortDramaController? _instance;
  static CasualShortDramaController get instance =>
      _instance ??= CasualShortDramaController();

  final HuangguoApiClient _apiClient;
  final CasualShortDramaStore _store;
  final PrivacySecurityService _privacyService;

  Player? _player;
  Player get player => _player!;

  VideoController? _videoController;
  VideoController get videoController => _videoController!;

  final List<StreamSubscription> _subscriptions = [];

  bool isPlaying = false;
  bool isBuffering = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 100.0;
  double rate = 1.0;
  bool isMuted = false;
  double _preMuteVolume = 100.0;

  // 播放状态
  DramaDetail? currentDrama;
  int currentEp = 1;
  DramaPlayInfo? currentPlayInfo;
  bool isFavorite = false;
  bool isLoadingPlay = false;
  String? playError;

  // 列表与探索状态
  List<DramaCard> catalogItems = [];
  List<DramaFavoriteItem> favorites = [];
  List<DramaHistoryItem> history = [];
  String currentTab = 'all'; // 'all' (全部短剧) | 'feed' (精选推荐) | 'hot' | 'recommend' | 'potential' | 'favorites' | 'history'
  bool isLoadingCatalog = false;
  String? catalogError;
  String currentSearchQuery = '';

  // 题材标签与排序状态
  String selectedTag = '';
  DramaSortType sortType = DramaSortType.defaultOrder;

  static const List<String> popularTags = [
    '都市',
    '现代',
    '逆袭',
    '重生',
    '古风',
    '仙侠',
    '系统',
    '后宫',
    '职场',
    '校园',
    '脑洞',
    '大男主',
    '大女主',
    '甜宠',
    '神豪',
    '战神',
  ];

  // 分页无限滚动状态
  int catalogPage = 1;
  static const int catalogPageSize = 30;
  bool hasMoreCatalog = true;
  bool isLoadingMoreCatalog = false;
  String? loadMoreError;

  // 线路状态
  LineState lineState = const LineState(
    currentBase: 'https://huangguoai.com',
    fixedLines: HuangguoApiClient.defaultFixedLines,
  );

  bool _isPlayerReady = false;
  bool get isPlayerReady => _isPlayerReady;

  DateTime _lastHistoryRecordTime = DateTime.now();

  void _initPlayer() {
    try {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
        ),
      );
      _videoController = VideoController(_player!);
      _isPlayerReady = true;

      _subscriptions.add(_player!.stream.playing.listen((val) {
        isPlaying = val;
        notifyListeners();
      }));

      _subscriptions.add(_player!.stream.buffering.listen((val) {
        isBuffering = val;
        notifyListeners();
      }));

      _subscriptions.add(_player!.stream.position.listen((val) {
        position = val;
        _maybeSaveHistoryThrottle();
        notifyListeners();
      }));

      _subscriptions.add(_player!.stream.duration.listen((val) {
        duration = val;
        notifyListeners();
      }));

      // 完播自动切下一集
      _subscriptions.add(_player!.stream.completed.listen((completed) {
        if (completed && currentDrama != null) {
          playNextEpisode();
        }
      }));
    } catch (e) {
      debugPrint('[CasualShortDramaController] init player error: $e');
    }
  }

  late final PlaybackInhibitor _playbackInhibitor;

  void _bindSecurityListener() {
    _playbackInhibitor = () => isPlaying;
    _privacyService.registerPlaybackInhibitor(_playbackInhibitor);
    _privacyService.isUnlockedNotifier.addListener(_onPrivacyLockChanged);
  }

  void _onPrivacyLockChanged() {
    if (!_privacyService.isUnlocked) {
      // 隐私空间被锁定：立即暂停播放并切断音频，防止背景泄露
      pause();
      if (_player != null) {
        _player!.setVolume(0.0);
        isMuted = true;
      }
    }
  }

  /// 初始化数据（载入线路与首页 Feed）
  Future<void> init() async {
    await _apiClient.init();
    lineState = LineState(
      currentBase: _apiClient.currentBase,
      fixedLines: HuangguoApiClient.defaultFixedLines,
      mirrorLines: _apiClient.mirrorLines,
    );
    await refreshCatalog();
    await loadFavorites();
    await loadHistory();
  }

  void _applySort(List<DramaCard> items) {
    if (sortType == DramaSortType.scoreDesc) {
      items.sort((a, b) => b.score.compareTo(a.score));
    } else if (sortType == DramaSortType.episodesDesc) {
      items.sort((a, b) => b.totalEpisodes.compareTo(a.totalEpisodes));
    }
  }

  /// 切换排序模式
  void setSortType(DramaSortType sort) {
    _privacyService.recordActivity();
    if (sortType == sort) return;
    sortType = sort;
    if (sortType == DramaSortType.defaultOrder) {
      refreshCatalog();
    } else {
      _applySort(catalogItems);
      notifyListeners();
    }
  }

  /// 选择/取消选择题材标签
  Future<void> selectTag(String tag) async {
    _privacyService.recordActivity();
    final nextTag = (selectedTag == tag) ? '' : tag;
    selectedTag = nextTag;
    currentSearchQuery = '';
    await refreshCatalog();
  }

  /// 刷新当前分类或 Feed 列表
  Future<void> refreshCatalog() async {
    isLoadingCatalog = true;
    catalogError = null;
    loadMoreError = null;
    catalogPage = 1;
    hasMoreCatalog = true;
    notifyListeners();

    try {
      if (selectedTag.isNotEmpty) {
        // 如果选中了标签，优先按标签检索
        catalogItems = await _apiClient.search(selectedTag, page: 1, size: catalogPageSize);
        hasMoreCatalog = catalogItems.length >= catalogPageSize;
      } else if (currentTab == 'all' || currentTab == 'feed') {
        catalogItems = await _apiClient.getFeed(page: 1, size: catalogPageSize);
        hasMoreCatalog = catalogItems.length >= catalogPageSize;
      } else if (currentTab == 'hot' || currentTab == 'recommend' || currentTab == 'potential') {
        catalogItems = await _apiClient.getRank(kind: currentTab);
        hasMoreCatalog = false; // 榜单为固定精选榜
      } else if (currentTab == 'favorites') {
        await loadFavorites();
        hasMoreCatalog = false;
      } else if (currentTab == 'history') {
        await loadHistory();
        hasMoreCatalog = false;
      }
      _applySort(catalogItems);
    } catch (e) {
      catalogError = e.toString();
    } finally {
      isLoadingCatalog = false;
      notifyListeners();
    }
  }

  /// 加载更多（触底分页追加）
  Future<void> loadMoreCatalog() async {
    if (isLoadingMoreCatalog || !hasMoreCatalog || isLoadingCatalog) return;
    if (currentTab != 'all' && currentTab != 'feed' && currentSearchQuery.isEmpty && selectedTag.isEmpty) return;

    isLoadingMoreCatalog = true;
    loadMoreError = null;
    notifyListeners();

    try {
      final nextPage = catalogPage + 1;
      final List<DramaCard> newItems;
      final query = currentSearchQuery.isNotEmpty ? currentSearchQuery : selectedTag;
      if (query.isNotEmpty) {
        newItems = await _apiClient.search(query, page: nextPage, size: catalogPageSize);
      } else {
        newItems = await _apiClient.getFeed(page: nextPage, size: catalogPageSize);
      }

      if (newItems.isEmpty) {
        hasMoreCatalog = false;
      } else {
        catalogPage = nextPage;
        // 去重合并
        final existingIds = catalogItems.map((e) => e.id).toSet();
        final added = newItems.where((e) => !existingIds.contains(e.id)).toList();
        catalogItems.addAll(added);
        _applySort(catalogItems);
        if (newItems.length < catalogPageSize) {
          hasMoreCatalog = false;
        }
      }
    } catch (e) {
      loadMoreError = e.toString();
    } finally {
      isLoadingMoreCatalog = false;
      notifyListeners();
    }
  }

  /// 切换主侧边栏分类标签
  Future<void> switchTab(String tab) async {
    _privacyService.recordActivity();
    if (currentTab == tab && currentSearchQuery.isEmpty && selectedTag.isEmpty) return;
    currentTab = tab;
    currentSearchQuery = '';
    selectedTag = '';
    await refreshCatalog();
  }

  /// 执行搜索
  Future<void> search(String query) async {
    _privacyService.recordActivity();
    currentSearchQuery = query.trim();
    selectedTag = '';
    if (currentSearchQuery.isEmpty) {
      await refreshCatalog();
      return;
    }
    isLoadingCatalog = true;
    catalogError = null;
    loadMoreError = null;
    catalogPage = 1;
    hasMoreCatalog = true;
    notifyListeners();

    try {
      catalogItems = await _apiClient.search(currentSearchQuery, page: 1, size: catalogPageSize);
      hasMoreCatalog = catalogItems.length >= catalogPageSize;
      _applySort(catalogItems);
    } catch (e) {
      catalogError = e.toString();
    } finally {
      isLoadingCatalog = false;
      notifyListeners();
    }
  }

  /// 打开短剧并开始播放（默认定位到历史集数或第 1 集）
  Future<void> openDrama(dynamic dramaCardOrId, {int? startEp}) async {
    _privacyService.recordActivity();
    final int dramaId = dramaCardOrId is DramaCard
        ? dramaCardOrId.id
        : (dramaCardOrId is int ? dramaCardOrId : int.tryParse(dramaCardOrId.toString()) ?? 0);
    if (dramaId <= 0) return;

    isLoadingPlay = true;
    playError = null;
    notifyListeners();

    try {
      final detail = await _apiClient.getDetail(dramaId);
      currentDrama = detail;

      // 检查收藏状态
      isFavorite = await _store.isFavorite(dramaId);

      // 决定起始集数：如果有显式指定，按显式指定；否则检查历史记录；没有则从第 1 集起播
      int targetEp = startEp ?? 1;
      if (startEp == null) {
        final historyItem = await _store.getHistory(dramaId);
        if (historyItem != null && historyItem.lastWatchedEp > 0) {
          targetEp = historyItem.lastWatchedEp;
        }
      }

      await playEpisode(targetEp, autoPlay: true);
    } catch (e) {
      playError = '加载短剧详情失败: $e';
    } finally {
      isLoadingPlay = false;
      notifyListeners();
    }
  }

  /// 播放指定集数
  Future<void> playEpisode(int epNum, {bool autoPlay = true}) async {
    _privacyService.recordActivity();
    if (currentDrama == null) return;
    currentEp = epNum;
    isLoadingPlay = true;
    playError = null;
    notifyListeners();

    try {
      final playInfo = await _apiClient.getPlayInfo(currentDrama!.id, epNum);
      currentPlayInfo = playInfo;

      if (playInfo.videoUrl.isEmpty) {
        playError = '第 $epNum 集暂无可用视频流';
      } else if (_player != null) {
        // 使用 media_kit 原生播放 HLS 流媒体
        final media = Media(
          playInfo.videoUrl,
          httpHeaders: {
            'Referer': '${_apiClient.currentBase}/',
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          },
        );

        await _player!.open(media, play: autoPlay);
        if (autoPlay) {
          await _player!.play();
        }

        // 记录历史
        _saveHistory();
      }
    } catch (e) {
      playError = '播放第 $epNum 集失败: $e';
    } finally {
      isLoadingPlay = false;
      notifyListeners();
    }
  }

  /// 退出观影剧场，返回片库浏览
  Future<void> exitTheater() async {
    if (_player != null) {
      await _player!.pause();
    }
    currentDrama = null;
    currentPlayInfo = null;
    playError = null;
    notifyListeners();
  }

  /// 播放下一集
  Future<void> playNextEpisode() async {
    if (currentDrama == null) return;
    final total = currentDrama!.totalEpisodes > 0
        ? currentDrama!.totalEpisodes
        : currentDrama!.episodes.length;
    if (currentEp < total) {
      await playEpisode(currentEp + 1);
    }
  }

  /// 播放上一集
  Future<void> playPrevEpisode() async {
    if (currentDrama == null) return;
    if (currentEp > 1) {
      await playEpisode(currentEp - 1);
    }
  }

  /// 播放 / 暂停切换
  Future<void> togglePlayPause() async {
    _privacyService.recordActivity();
    if (_player == null) return;
    if (isPlaying) {
      await _player!.pause();
    } else {
      await _player!.play();
    }
  }

  Future<void> pause() async {
    if (_player != null && isPlaying) {
      await _player!.pause();
    }
  }

  Future<void> play() async {
    _privacyService.recordActivity();
    if (_player != null && !isPlaying) {
      await _player!.play();
    }
  }

  /// 跳转指定进度
  Future<void> seek(Duration pos) async {
    _privacyService.recordActivity();
    if (_player != null) {
      await _player!.seek(pos);
    }
  }

  /// 快进 / 快退相对毫秒
  Future<void> seekRelative(Duration delta) async {
    _privacyService.recordActivity();
    final target = position + delta;
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    await seek(clamped);
  }

  /// 静音切换
  Future<void> toggleMute() async {
    if (_player == null) return;
    if (isMuted) {
      await _player!.setVolume(_preMuteVolume > 0 ? _preMuteVolume : 100.0);
      isMuted = false;
    } else {
      _preMuteVolume = volume;
      await _player!.setVolume(0.0);
      isMuted = true;
    }
    notifyListeners();
  }

  /// 设置音量 (0.0 ~ 100.0)
  Future<void> setVolume(double val) async {
    if (_player == null) return;
    volume = val.clamp(0.0, 100.0);
    isMuted = volume <= 0.0;
    await _player!.setVolume(volume);
    notifyListeners();
  }

  /// 设置播放倍速
  Future<void> setPlaybackRate(double r) async {
    if (_player == null) return;
    rate = r.clamp(0.5, 3.0);
    await _player!.setRate(rate);
    notifyListeners();
  }

  /// 切换当前短剧收藏
  Future<void> toggleFavorite() async {
    _privacyService.recordActivity();
    if (currentDrama == null) return;
    final newFav = await _store.toggleFavorite(
      dramaId: currentDrama!.id,
      title: currentDrama!.title,
      cover: currentDrama!.cover,
      episodeCount: currentDrama!.episodeCount,
    );
    isFavorite = newFav;
    await loadFavorites();
    notifyListeners();
  }

  /// 显式移除收藏
  Future<void> removeFavorite(int dramaId) async {
    _privacyService.recordActivity();
    await _store.removeFavorite(dramaId);
    if (currentDrama?.id == dramaId) {
      isFavorite = false;
    }
    await loadFavorites();
    notifyListeners();
  }

  /// 载入收藏列表
  Future<void> loadFavorites() async {
    favorites = await _store.getFavorites();
    notifyListeners();
  }

  /// 载入历史记录
  Future<void> loadHistory() async {
    history = await _store.getAllHistory();
    notifyListeners();
  }

  /// 删除某部短剧的历史记录
  Future<void> removeHistory(int dramaId) async {
    await _store.removeHistory(dramaId);
    await loadHistory();
  }

  /// 清空历史记录
  Future<void> clearHistory() async {
    await _store.clearHistory();
    history = [];
    notifyListeners();
  }

  /// 切换线路
  Future<void> switchBaseUrl(String newBase) async {
    _privacyService.recordActivity();
    await _apiClient.switchBase(newBase);
    lineState = LineState(
      currentBase: _apiClient.currentBase,
      fixedLines: HuangguoApiClient.defaultFixedLines,
      mirrorLines: _apiClient.mirrorLines,
    );
    await refreshCatalog();
  }

  /// 刷新并探测所有镜像线路
  Future<void> refreshAndProbeLines() async {
    final mirrors = await _apiClient.fetchMirrors();
    final allLines = [...HuangguoApiClient.defaultFixedLines, ...mirrors];
    final probed = await _apiClient.probeLines(allLines);
    final fixedProbed = probed.take(HuangguoApiClient.defaultFixedLines.length).toList();
    final mirrorsProbed = probed.skip(HuangguoApiClient.defaultFixedLines.length).toList();

    lineState = LineState(
      currentBase: _apiClient.currentBase,
      fixedLines: fixedProbed,
      mirrorLines: mirrorsProbed,
    );
    notifyListeners();
  }

  /// 将当前短剧当前集加入私密下载队列
  Future<DownloadTask?> downloadCurrentEpisode() async {
    if (currentDrama == null || currentPlayInfo == null) return null;
    final url = currentPlayInfo!.videoUrl;
    if (url.isEmpty) return null;

    final title = '${currentDrama!.title} - 第$currentEp集';
    return DownloadQueueManager.instance.addTask(
      url,
      title: title,
      thumbnailUrl: currentDrama!.cover,
      directStreamUrl: url,
    );
  }

  /// 批量将多集加入私密下载队列
  Future<List<DownloadTask>> downloadEpisodes(List<int> epNums) async {
    if (currentDrama == null) return [];
    final List<DownloadTask> tasks = [];
    for (final ep in epNums) {
      try {
        final playInfo = await _apiClient.getPlayInfo(currentDrama!.id, ep);
        if (playInfo.videoUrl.isNotEmpty) {
          final title = '${currentDrama!.title} - 第$ep集';
          final task = DownloadQueueManager.instance.addTask(
            playInfo.videoUrl,
            title: title,
            thumbnailUrl: currentDrama!.cover,
            directStreamUrl: playInfo.videoUrl,
          );
          tasks.add(task);
        }
      } catch (e) {
        debugPrint('[CasualShortDramaController] batch download error for ep $ep: $e');
      }
    }
    return tasks;
  }

  void _maybeSaveHistoryThrottle() {
    final now = DateTime.now();
    if (now.difference(_lastHistoryRecordTime).inSeconds >= 5) {
      _lastHistoryRecordTime = now;
      _saveHistory();
    }
  }

  void _saveHistory() {
    if (currentDrama == null) return;
    _store.recordHistory(
      dramaId: currentDrama!.id,
      title: currentDrama!.title,
      cover: currentDrama!.cover,
      lastWatchedEp: currentEp,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
    );
  }

  @override
  void dispose() {
    _privacyService.unregisterPlaybackInhibitor(_playbackInhibitor);
    _privacyService.isUnlockedNotifier.removeListener(_onPrivacyLockChanged);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    super.dispose();
  }
}
