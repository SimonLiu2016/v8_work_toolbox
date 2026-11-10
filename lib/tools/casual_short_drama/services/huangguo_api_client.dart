import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../services/settings_store.dart';
import '../models/drama_models.dart';

/// 黄果短剧网关客户端
/// 负责封装统一的 `/api/edge/request` 信封调用、线路测速探测与持久化
class HuangguoApiClient {
  HuangguoApiClient({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  static final HuangguoApiClient instance = HuangguoApiClient();

  final http.Client _client;

  static const String _defaultBase = 'https://huangguoai.com';

  static const List<LineItem> defaultFixedLines = [
    LineItem(name: '固定线路 1', url: 'https://huangguoai.com'),
    LineItem(name: '固定线路 2', url: 'https://huangguoai.ai'),
  ];

  static const String _publishPage = 'https://huangguoai.pages.dev/';
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  String _currentBase = _defaultBase;
  String get currentBase => _currentBase;

  List<LineItem> _mirrorLines = [];
  List<LineItem> get mirrorLines => List.unmodifiable(_mirrorLines);

  bool _initialized = false;

  /// 初始化并载入持久化线路配置
  Future<void> init() async {
    if (_initialized) return;
    try {
      final config = await SettingsStore.instance.readToolConfig('casual-short-drama');
      final savedBase = config['base_url']?.toString();
      if (savedBase != null && savedBase.startsWith('https://')) {
        _currentBase = savedBase.trim();
      }
    } catch (e) {
      debugPrint('[HuangguoApiClient] init preferences error: $e');
    }
    _initialized = true;
  }

  /// 切换当前服务基址并持久化
  Future<void> switchBase(String newBase) async {
    final clean = newBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (!clean.startsWith('https://')) {
      throw ArgumentError('线路必须为纯 HTTPS 协议');
    }
    _currentBase = clean;
    try {
      await SettingsStore.instance.writeToolConfig('casual-short-drama', {
        'base_url': _currentBase,
      });
    } catch (e) {
      debugPrint('[HuangguoApiClient] save base error: $e');
    }
  }

  /// 统一底层网关信封请求
  Future<dynamic> edgeRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? token,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final cur = _currentBase;
    final edgeUrl = Uri.parse('$cur/api/edge/request');
    final referer = '$cur/';

    String encodedBody = '';
    String contentType = '';
    if (body != null) {
      encodedBody = base64.encode(utf8.encode(jsonEncode(body)));
      contentType = 'application/json';
    }

    final envelope = {
      'method': method.toUpperCase(),
      'path': path,
      'body': encodedBody,
      'content_type': contentType,
    };

    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Referer': referer,
      'User-Agent': _defaultUserAgent,
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      response = await _client
          .post(
            edgeUrl,
            headers: headers,
            body: jsonEncode(envelope),
          )
          .timeout(timeout);
    } catch (e) {
      throw HttpException('网络请求连接失败: $e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const HttpException('未登录或凭证已失效');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: ${response.body.takePrefix(120)}');
    }

    final responseText = response.body.trim();
    if (responseText.isEmpty) {
      return null;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(responseText) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('解析上游网关响应失败: ${response.body.takePrefix(120)}');
    }

    final status = (json['status'] as num?)?.toInt();
    if (status == 1) {
      return json['data'];
    } else {
      final msg = json['msg']?.toString();
      throw HttpException(msg != null && msg.isNotEmpty ? msg : '接口返回业务失败');
    }
  }

  /// 获取推荐短剧 Feed 流
  Future<List<DramaCard>> getFeed({int page = 1, int size = 30}) async {
    final data = await edgeRequest(
      method: 'GET',
      path: '/api/videos?page=$page&size=$size',
    );
    return _parseDramaList(data);
  }

  /// 按分类获取短剧列表
  Future<List<DramaCard>> getCategory(String cate, {int page = 1, int size = 30}) async {
    final encodedCate = Uri.encodeComponent(cate);
    final data = await edgeRequest(
      method: 'GET',
      path: '/api/videos/category/$encodedCate?page=$page&size=$size',
    );
    return _parseDramaList(data);
  }

  /// 获取榜单 (hot | recommend | potential)
  Future<List<DramaCard>> getRank({String kind = 'hot'}) async {
    final data = await edgeRequest(
      method: 'GET',
      path: '/api/ranks/$kind',
    );
    if (data is Map && data['items'] is List) {
      return (data['items'] as List).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        if (!map.containsKey('id') && map.containsKey('video_id')) {
          map['id'] = map['video_id'];
        }
        return DramaCard.fromJson(map);
      }).toList();
    }
    return [];
  }

  /// 关键词搜索短剧
  Future<List<DramaCard>> search(String query, {int page = 1, int size = 30}) async {
    final encoded = Uri.encodeQueryComponent(query.trim());
    final data = await edgeRequest(
      method: 'GET',
      path: '/api/search?q=$encoded&page=$page&size=$size',
    );
    return _parseDramaList(data);
  }

  /// 获取短剧详情 (包含剧集列表 episodes)
  Future<DramaDetail> getDetail(int dramaId) async {
    final data = await edgeRequest(
      method: 'GET',
      path: '/api/videos/$dramaId',
    );
    if (data is Map) {
      return DramaDetail.fromJson(Map<String, dynamic>.from(data));
    }
    throw const HttpException('获取剧集详情失败：数据格式不符');
  }

  /// 获取指定集数的播放直链 (HLS m3u8)
  Future<DramaPlayInfo> getPlayInfo(int dramaId, int epNum) async {
    Object? lastError;
    // 优先调用上游最新 POST playback 协议端点
    try {
      final data = await edgeRequest(
        method: 'POST',
        path: '/api/videos/$dramaId/episodes/$epNum/playback',
      );
      if (data is Map) {
        final playInfo = DramaPlayInfo.fromJson(Map<String, dynamic>.from(data));
        if (playInfo.videoUrl.isNotEmpty) {
          return playInfo;
        }
      }
    } catch (e) {
      lastError = e;
    }

    // 降级回退：旧版本 GET 接口
    try {
      final fallback = await edgeRequest(
        method: 'GET',
        path: '/api/videos/$dramaId/play?ep=$epNum&page_texts=0',
      );
      if (fallback is Map) {
        final playInfo = DramaPlayInfo.fromJson(Map<String, dynamic>.from(fallback));
        if (playInfo.videoUrl.isNotEmpty) {
          return playInfo;
        }
      }
    } catch (e) {
      lastError ??= e;
    }

    if (lastError != null) {
      throw HttpException('获取播放信息失败: $lastError');
    }
    throw const HttpException('获取播放信息失败：未能解析到可用的视频流');
  }

  /// 从地址发布页抓取镜像线路
  Future<List<LineItem>> fetchMirrors() async {
    try {
      final resp = await _client.get(
        Uri.parse(_publishPage),
        headers: {'User-Agent': _defaultUserAgent},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) {
        return [];
      }

      // 提取 <script src="publish.js?xxx">
      final html = resp.body;
      final scriptMatch = RegExp('src=["\']([^"\']*\\.js[^"\']*)["\']').firstMatch(html);
      final scriptRel = scriptMatch?.group(1) ?? 'publish.js';
      final scriptUri = Uri.parse(_publishPage).resolve(scriptRel);

      final jsResp = await _client.get(
        scriptUri,
        headers: {'User-Agent': _defaultUserAgent},
      ).timeout(const Duration(seconds: 8));

      if (jsResp.statusCode != 200) {
        return [];
      }

      final js = jsResp.body;
      final domains = _extractJsArray(js, 'var urls');
      final subs = _extractJsArray(js, 'var subdomains');

      final List<LineItem> items = [];
      final Set<String> seen = {};

      for (var domain in domains) {
        domain = domain.replaceAll(RegExp(r'/+$'), '');
        if (domain.isEmpty) continue;
        final hosts = subs.isEmpty ? [domain] : subs.map((s) => '$s.$domain').toList();
        for (final host in hosts) {
          if (seen.add(host)) {
            items.add(LineItem(name: '镜像: $host', url: 'https://$host'));
            if (items.length >= 30) break;
          }
        }
        if (items.length >= 30) break;
      }

      _mirrorLines = items;
      return items;
    } catch (e) {
      debugPrint('[HuangguoApiClient] fetchMirrors error: $e');
      return [];
    }
  }

  /// 批量对线路进行可达性与延迟测速探测
  Future<List<LineItem>> probeLines(List<LineItem> lines) async {
    final futures = lines.map((line) async {
      final sw = Stopwatch()..start();
      try {
        final resp = await _client.get(
          Uri.parse('${line.url}/'),
          headers: {'User-Agent': _defaultUserAgent},
        ).timeout(const Duration(seconds: 5));
        sw.stop();
        final ok = resp.statusCode < 400;
        return line.copyWith(
          isReachable: ok,
          latencyMs: ok ? sw.elapsedMilliseconds : null,
        );
      } catch (_) {
        return line.copyWith(isReachable: false, latencyMs: null);
      }
    });

    return Future.wait(futures);
  }

  List<DramaCard> _parseDramaList(dynamic data) {
    if (data is Map && data['items'] is List) {
      return (data['items'] as List)
          .map((e) => DramaCard.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    if (data is List) {
      return data
          .map((e) => DramaCard.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }

  List<String> _extractJsArray(String js, String decl) {
    final at = js.indexOf(decl);
    if (at < 0) return [];
    final rest = js.substring(at);
    final open = rest.indexOf('[');
    if (open < 0) return [];
    final close = rest.indexOf(']', open);
    if (close < 0) return [];
    final content = rest.substring(open + 1, close);
    return content
        .split(',')
        .map((s) => s.replaceAll(RegExp(r'//.*$'), '').trim().replaceAll(RegExp(r'''['"]'''), ''))
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

extension _StringPrefix on String {
  String takePrefix(int count) {
    return length > count ? '${substring(0, count)}...' : this;
  }
}
