import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'private_browser_repository.dart';
import 'private_browser_store.dart';

/// 隐私空间私密浏览器服务（封装底层 Repository、跨会话恢复、原生通道与视频增强联动）
class PrivateBrowserService extends ChangeNotifier {
  PrivateBrowserService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }
  static final PrivateBrowserService instance = PrivateBrowserService._();

  static const _channel = MethodChannel('v8_work_toolbox/private_browser');

  final PrivateBrowserRepository _repo = PrivateBrowserRepository();
  PrivateBrowserRepository get repository => _repo;

  final List<BrowserTabItem> _tabs = [];
  List<BrowserTabItem> get tabs => List.unmodifiable(_tabs);

  int _activeTabIndex = 0;
  int get activeTabIndex => _activeTabIndex;

  BrowserTabItem? get activeTab =>
      _tabs.isNotEmpty && _activeTabIndex >= 0 && _activeTabIndex < _tabs.length
          ? _tabs[_activeTabIndex]
          : null;

  bool _isNativeBrowserOpen = false;
  bool get isNativeBrowserOpen => _isNativeBrowserOpen;

  // 当前视频增强状态
  bool _isVideoDetected = false;
  bool get isVideoDetected => _isVideoDetected;

  String? _detectedVideoUrl;
  String? get detectedVideoUrl => _detectedVideoUrl;

  String? _detectedVideoTitle;
  String? get detectedVideoTitle => _detectedVideoTitle;

  String? _detectedVideoSrc;
  String? get detectedVideoSrc => _detectedVideoSrc;

  String? _detectedVideoThumbnail;
  String? get detectedVideoThumbnail => _detectedVideoThumbnail;

  // 外部动作监听回调 (下载、缓存播放、收藏、字幕等)
  void Function(String url, String title, {String? videoSrc, String? thumbnail})? onDownloadRequested;
  void Function(String url, String title, {String? videoSrc, String? thumbnail})? onCachePlayRequested;
  void Function(String url, String title, {String? videoSrc, String? thumbnail})? onFavoriteRequested;
  void Function(String url)? onSubtitleRequested;

  /// 初始化服务并从 SQLite 恢复跨会话持久化的标签页
  Future<void> init() async {
    final savedTabs = await _repo.getTabs();
    _tabs.clear();
    if (savedTabs.isEmpty) {
      // 默认提供一个空白首页标签
      _tabs.add(BrowserTabItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        url: '',
        title: '新标签页',
        createdAt: DateTime.now(),
      ));
    } else {
      _tabs.addAll(savedTabs);
    }
    _activeTabIndex = 0;
    notifyListeners();
  }

  /// 隐私空间锁定时调用：保存当前所有标签页状态并关闭原生视窗
  Future<void> onPrivacyLocked() async {
    await persistTabs();
    await closeNativeBrowser();
    _tabs.clear();
    _activeTabIndex = 0;
    _isVideoDetected = false;
    notifyListeners();
  }

  /// 持久化标签页到 SQLite
  Future<void> persistTabs() async {
    if (_tabs.isEmpty) return;
    await _repo.saveTabs(_tabs);
  }

  /// 新建标签页
  Future<void> createTab({String url = '', String title = '新标签页'}) async {
    final newTab = BrowserTabItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      title: title,
      orderIndex: _tabs.length,
      createdAt: DateTime.now(),
    );
    _tabs.add(newTab);
    _activeTabIndex = _tabs.length - 1;
    await _repo.addTab(newTab);
    notifyListeners();

    if (url.isNotEmpty && _isNativeBrowserOpen) {
      await loadUrl(url);
    }
  }

  /// 切换标签页
  Future<void> switchTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    _activeTabIndex = index;
    _isVideoDetected = false;
    notifyListeners();

    final tab = _tabs[index];
    if (tab.url.isNotEmpty && _isNativeBrowserOpen) {
      await loadUrl(tab.url);
    }
  }

  /// 关闭标签页
  Future<void> closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final closedTab = _tabs.removeAt(index);
    await _repo.removeTab(closedTab.id);

    if (_tabs.isEmpty) {
      await createTab();
    } else {
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      notifyListeners();
      final tab = _tabs[_activeTabIndex];
      if (tab.url.isNotEmpty && _isNativeBrowserOpen) {
        await loadUrl(tab.url);
      }
    }
  }

  /// 更新当前活动标签页的 URL 与标题
  Future<void> updateActiveTab({String? url, String? title}) async {
    if (activeTab == null) return;
    final updated = activeTab!.copyWith(
      url: url ?? activeTab!.url,
      title: title ?? activeTab!.title,
    );
    _tabs[_activeTabIndex] = updated;
    await _repo.updateTab(updated);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 原生视窗控制
  // ---------------------------------------------------------------------------

  /// 打开或置顶私密浏览器原生窗口
  Future<void> openNativeBrowser({String? url}) async {
    final targetUrl = url ?? activeTab?.url;
    final effectiveUrl = (targetUrl != null && targetUrl.isNotEmpty)
        ? targetUrl
        : 'https://www.youtube.com';

    await _channel.invokeMethod('openBrowser', {'url': effectiveUrl});
    _isNativeBrowserOpen = true;
    notifyListeners();
  }

  /// 加载指定 URL
  Future<void> loadUrl(String url) async {
    await _channel.invokeMethod('loadUrl', {'url': url});
    updateActiveTab(url: url);
  }

  /// 关闭原生窗口
  Future<void> closeNativeBrowser() async {
    try {
      await _channel.invokeMethod('closeBrowser');
    } catch (_) {}
    _isNativeBrowserOpen = false;
    notifyListeners();
  }

  /// 前进
  Future<void> goForward() async {
    await _channel.invokeMethod('goForward');
  }

  /// 后退
  Future<void> goBack() async {
    await _channel.invokeMethod('goBack');
  }

  /// 刷新
  Future<void> reload() async {
    await _channel.invokeMethod('reload');
  }

  /// 挂载字幕列表
  Future<void> mountSubtitles(List<Map<String, dynamic>> subtitles) async {
    await _channel.invokeMethod('mountSubtitles', {'subtitles': subtitles});
  }

  /// 切换字幕显隐
  Future<void> toggleSubtitles(bool visible) async {
    await _channel.invokeMethod('toggleSubtitles', {'visible': visible});
  }

  /// 向原生浮动工具栏同步下载进度
  Future<void> updateNativeDownloadStatus({required double progress, required String status}) async {
    try {
      await _channel.invokeMethod('updateDownloadStatus', {
        'progress': progress,
        'status': status,
      });
    } catch (_) {}
  }

  /// 向原生浮动工具栏同步收藏状态
  Future<void> updateNativeFavoriteStatus(bool isFavorite) async {
    try {
      await _channel.invokeMethod('updateFavoriteStatus', {
        'isFavorite': isFavorite,
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 原生端事件分发处理
  // ---------------------------------------------------------------------------

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onVideoDetected':
        final args = call.arguments as Map? ?? {};
        _isVideoDetected = true;
        _detectedVideoUrl = args['url'] as String?;
        _detectedVideoTitle = args['title'] as String?;
        _detectedVideoSrc = args['videoSrc'] as String?;
        _detectedVideoThumbnail = args['thumbnail'] as String?;
        notifyListeners();
        break;

      case 'onVideoReset':
        _isVideoDetected = false;
        _detectedVideoUrl = null;
        _detectedVideoTitle = null;
        _detectedVideoSrc = null;
        _detectedVideoThumbnail = null;
        notifyListeners();
        break;

      case 'onNavigationFinished':
        final args = call.arguments as Map? ?? {};
        final url = args['url'] as String? ?? '';
        final title = args['title'] as String? ?? '';
        updateActiveTab(url: url, title: title);
        break;

      case 'triggerDownload':
        final args = call.arguments as Map? ?? {};
        final url = args['url'] as String? ?? '';
        final title = args['title'] as String? ?? '';
        final videoSrc = args['videoSrc'] as String?;
        final thumbnail = args['thumbnail'] as String?;
        onDownloadRequested?.call(url, title, videoSrc: videoSrc, thumbnail: thumbnail);
        break;

      case 'triggerCachePlay':
        final args = call.arguments as Map? ?? {};
        final url = args['url'] as String? ?? '';
        final title = args['title'] as String? ?? '';
        final videoSrc = args['videoSrc'] as String?;
        final thumbnail = args['thumbnail'] as String?;
        onCachePlayRequested?.call(url, title, videoSrc: videoSrc, thumbnail: thumbnail);
        break;

      case 'triggerFavorite':
        final args = call.arguments as Map? ?? {};
        final url = args['url'] as String? ?? '';
        final title = args['title'] as String? ?? '';
        final videoSrc = args['videoSrc'] as String?;
        final thumbnail = args['thumbnail'] as String?;
        onFavoriteRequested?.call(url, title, videoSrc: videoSrc, thumbnail: thumbnail);
        break;

      case 'openSubtitlePanel':
        final args = call.arguments as Map? ?? {};
        final url = args['url'] as String? ?? '';
        onSubtitleRequested?.call(url);
        break;
    }
  }
}
