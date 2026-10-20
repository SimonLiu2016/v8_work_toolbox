import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../../../services/settings_store.dart';
import 'infinite_canvas_asset_bridge.dart';
import 'infinite_canvas_canvas_plugin_source.dart';
import 'infinite_canvas_config_store.dart';

/// 单次请求的处理超时。
///
/// 导出要读剧集数据并渲染分镜表，比词典桥重；8 秒是给「桥自己卡住」兜底的，
/// 不是给正常请求放宽。
const Duration kHandlerTimeout = Duration(seconds: 20);

/// 视频请求体上限。
///
/// 超过这个大小的视频在请求头阶段就拒绝——传一半再失败会浪费带宽，也会在
/// 工坊里留下半个 `.part`。
const int kMaxVideoBytes = 512 * 1024 * 1024;

/// 无限画布配置文件的名字。
///
/// 它明文保存用户的 API Key 与 WebDAV 密码（上游文档原话「不应公开分享」）。
/// 本服务显式拒绝把它当作任何操作的输入（design D8）。
const String kForbiddenConfigFile = 'infinite-canvas-config.json';

/// 资产桥 loopback 服务（spec: 资产桥的传输通道）。
///
/// **只听 `127.0.0.1`**，与 `LocalDictionaryBridge` 同构：CORS 头自己写、
/// 端口冲突 fail-soft、密钥校验先于任何处理。
///
/// 职责分两半：
/// 1. 签发画布节点插件（`/v8-plugin.js`）——用户在无限画布里按 URL 装一次，
///    安装态由无限画布自己持久化；
/// 2. 给插件提供数据端点：选集列表、导出载荷、参考图原图、导回接收。
///
/// 生成请求**不经过这里**：画布上的生成由无限画布直连用户自己配置的渠道，
/// 密钥全程不离开浏览器（spec: 画布生成使用用户自己配置的渠道）。
class InfiniteCanvasBridgeServer extends ChangeNotifier {
  InfiniteCanvasBridgeServer._();
  static final InfiniteCanvasBridgeServer instance =
      InfiniteCanvasBridgeServer._();

  HttpServer? _server;

  /// 当前监听端口；未监听时为 null。
  int? get port => _server?.port;

  bool get isRunning => _server != null;

  /// 本机回环基地址，例如 `http://127.0.0.1:8798`。未启动时返回空串。
  String get baseUrl {
    final p = port;
    return p == null ? '' : 'http://127.0.0.1:$p';
  }

  /// 启动失败的可读原因（端口被占等）。
  String? lastError;

  /// 最近一次握手的时间。UI 用它显示「插件已连接」。
  DateTime? lastHandshakeAt;

  /// 已落盘但尚未归集进剧集的视频。
  ///
  /// 插件 POST 上来时只有 episodeId 与 fileName，不知道要进 segments/ 还是
  /// clips/、也不知道要覆盖哪些分镜——那些决策在 V8 侧做。所以这里先入队，
  /// 由工具页的「归集」动作统一消化。
  final List<StagedVideo> staged = <StagedVideo>[];

  /// 启动服务。任何失败都只记录诊断信号，不向外抛。
  ///
  /// [port] 仅供测试绑定到临时端口；生产走配置的 `bridgePort`。
  Future<bool> start({int? port}) async {
    if (_server != null) return true;

    final bindPort =
        port ?? InfiniteCanvasConfigStore.instance.config.bridgePort;
    try {
      // 密钥先落盘再起服务：否则插件装好了却拿到过期密钥，表现是「授权失败」
      // 而与桥没启动难以区分。
      await SettingsStore.instance.ensureLocalDictionaryBridgeSecret();
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        bindPort,
        shared: false,
      );
      server.idleTimeout = kHandlerTimeout;
      _server = server;
      lastError = null;
      // 参考图 URL 需要服务地址，所以资产桥的宿主在这里注入。
      InfiniteCanvasAssetBridge.instance.referenceBaseUrl =
          'http://127.0.0.1:${server.port}';
      _serve(server);
      debugPrint('[InfiniteCanvasBridge] 已监听 127.0.0.1:${server.port}');
      return true;
    } catch (e) {
      _server = null;
      lastError = '资产桥启动失败（127.0.0.1:$bindPort）：$e';
      debugPrint('[InfiniteCanvasBridge] $lastError');
      return false;
    }
  }

  /// 停止监听。幂等。
  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    InfiniteCanvasAssetBridge.instance.referenceBaseUrl = null;
    try {
      await server.close(force: true);
    } catch (e) {
      debugPrint('[InfiniteCanvasBridge] 关闭异常（端口已释放）: $e');
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request).timeout(kHandlerTimeout);
      } on TimeoutException {
        await _safeRespond(
          request,
          statusCode: HttpStatus.gatewayTimeout,
          body: {'ok': false, 'reason': 'timeout'},
        );
      } catch (e, stack) {
        // 单请求异常绝不能掀翻监听循环。
        debugPrint('[InfiniteCanvasBridge] 请求处理异常: $e\n$stack');
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;

    // 预检：浏览器在带自定义 Header（Authorization）时会先发 OPTIONS。
    if (request.method == 'OPTIONS') {
      _applyCorsHeaders(request);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    // 插件源码不鉴权：它本身不含密钥，装了插件的浏览器本来就持有密钥。
    // 鉴权只保护数据端点。
    if (path == '/v8-plugin.js') {
      if (request.method != 'GET') {
        await _safeRespond(
          request,
          statusCode: HttpStatus.methodNotAllowed,
          body: {'ok': false, 'reason': 'method_not_allowed'},
        );
        return;
      }
      await _respondJs(
        request,
        renderPluginSource(baseUrl: baseUrl),
      );
      return;
    }

    // 密钥校验先于任何解析与查询。
    final expected = SettingsStore.instance.localDictionaryBridgeSecretOrEmpty;
    final supplied =
        request.headers.value('Authorization') ??
        request.uri.queryParameters['secret'];
    if (expected.isEmpty || supplied == null || !_constantTimeEquals(supplied, expected)) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.unauthorized,
        body: {'ok': false, 'reason': 'unauthorized'},
      );
      return;
    }

    if (path == '/api/handshake') {
      lastHandshakeAt = DateTime.now();
      await _safeRespond(
        request,
        statusCode: HttpStatus.ok,
        body: {'ok': true, 'pluginVersion': kPluginVersion},
      );
      return;
    }

    if (path == '/api/episodes') {
      if (request.method != 'GET') {
        await _safeRespond(
          request,
          statusCode: HttpStatus.methodNotAllowed,
          body: {'ok': false, 'reason': 'method_not_allowed'},
        );
        return;
      }
      final series =
          await InfiniteCanvasAssetBridge.instance.listSelectableEpisodes();
      await _safeRespond(
        request,
        statusCode: HttpStatus.ok,
        body: {'ok': true, 'series': series},
      );
      return;
    }

    if (path == '/api/export') {
      if (request.method != 'GET') {
        await _safeRespond(
          request,
          statusCode: HttpStatus.methodNotAllowed,
          body: {'ok': false, 'reason': 'method_not_allowed'},
        );
        return;
      }
      final seriesId = request.uri.queryParameters['seriesId'] ?? '';
      final episodeId = request.uri.queryParameters['episodeId'] ?? '';
      if (seriesId.isEmpty || episodeId.isEmpty) {
        await _safeRespond(
          request,
          statusCode: HttpStatus.badRequest,
          body: {'ok': false, 'reason': 'missing_params'},
        );
        return;
      }
      try {
        final payload = await InfiniteCanvasAssetBridge.instance.buildExport(
          seriesId: seriesId,
          episodeId: episodeId,
        );
        await _safeRespond(
          request,
          statusCode: HttpStatus.ok,
          body: {'ok': true, 'payload': payload.toJson()},
        );
      } on StateError catch (e) {
        await _safeRespond(
          request,
          statusCode: HttpStatus.notFound,
          body: {'ok': false, 'reason': 'not_found', 'detail': e.message},
        );
      }
      return;
    }

    if (path == '/api/staged') {
      if (request.method != 'GET') {
        await _safeRespond(
          request,
          statusCode: HttpStatus.methodNotAllowed,
          body: {'ok': false, 'reason': 'method_not_allowed'},
        );
        return;
      }
      await _safeRespond(
        request,
        statusCode: HttpStatus.ok,
        body: {
          'ok': true,
          'items': staged.map((e) => e.toJson()).toList(),
        },
      );
      return;
    }

    if (path == '/api/import') {
      await _handleImport(request);
      return;
    }

    if (path == '/assets' || path.startsWith('/assets/')) {
      await _handleAsset(request, path);
      return;
    }

    await _safeRespond(
      request,
      statusCode: HttpStatus.notFound,
      body: {'ok': false, 'reason': 'not_found'},
    );
  }

  /// 参考图原图。
  ///
  /// 范围限制在剧集目录内：`/assets/<seriesId>/<相对路径>`。`..` 一律拒绝。
  Future<void> _handleAsset(HttpRequest request, String path) async {
    if (request.method != 'GET') {
      await _safeRespond(
        request,
        statusCode: HttpStatus.methodNotAllowed,
        body: {'ok': false, 'reason': 'method_not_allowed'},
      );
      return;
    }
    final rest = path.substring('/assets/'.length);
    final segments = rest
        .split('/')
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    if (segments.isEmpty) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.badRequest,
        body: {'ok': false, 'reason': 'bad_path'},
      );
      return;
    }
    // 第一段是 seriesId，其余是它在剧集目录下的相对路径。
    final seriesId = segments.first;
    final file = File(
      p.join(AppPaths.videoStudioSeriesDir.path, seriesId, segments.skip(1).join('/')),
    );
    if (!await _isInside(file, AppPaths.videoStudioSeriesDir.path)) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.forbidden,
        body: {'ok': false, 'reason': 'forbidden'},
      );
      return;
    }
    if (!file.existsSync()) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.notFound,
        body: {'ok': false, 'reason': 'not_found'},
      );
      return;
    }
    try {
      _applyCorsHeaders(request);
      final ext = p.extension(file.path).toLowerCase();
      request.response.headers.contentType = switch (ext) {
        '.png' => ContentType('image', 'png'),
        '.jpg' || '.jpeg' => ContentType('image', 'jpeg'),
        '.webp' => ContentType('image', 'webp'),
        '.gif' => ContentType('image', 'gif'),
        _ => ContentType.binary,
      };
      await request.response.addStream(file.openRead());
      await request.response.close();
    } catch (e) {
      debugPrint('[InfiniteCanvasBridge] 读参考图失败: $e');
    }
  }

  /// 接收画布侧 POST 回来的视频。
  ///
  /// 请求体是视频字节本身（不 base64），元数据走 query：`seriesId`、
  /// `episodeId`、`fileName`、`targetIsSegment`。多个文件用多次请求——一次
  /// 一个文件失败不会连带别的文件。
  Future<void> _handleImport(HttpRequest request) async {
    if (request.method != 'POST') {
      await _safeRespond(
        request,
        statusCode: HttpStatus.methodNotAllowed,
        body: {'ok': false, 'reason': 'method_not_allowed'},
      );
      return;
    }
    final seriesId = request.uri.queryParameters['seriesId'] ?? '';
    final episodeId = request.uri.queryParameters['episodeId'] ?? '';
    final fileName = request.uri.queryParameters['fileName'] ?? '';
    if (seriesId.isEmpty || episodeId.isEmpty || fileName.isEmpty) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.badRequest,
        body: {'ok': false, 'reason': 'missing_params'},
      );
      return;
    }

    // 上游配置文件明文明文保存 API Key 与 WebDAV 密码。显式拒绝而不是忽略：
    // 用户很可能在整理目录时把它和画布导出文件摆在一起（design D8）。
    if (isForbiddenConfigName(fileName)) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.badRequest,
        body: {
          'ok': false,
          'reason': 'forbidden',
          'detail': '无限画布的配置文件含 API Key 与 WebDAV 凭据，'
              '本工具不接收它。',
        },
      );
      return;
    }

    final declared = request.contentLength;
    if (declared > kMaxVideoBytes) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.requestEntityTooLarge,
        body: {'ok': false, 'reason': 'too_large', 'limit': kMaxVideoBytes},
      );
      return;
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in request) {
      total += chunk.length;
      if (total > kMaxVideoBytes) {
        await request.drain();
        await _safeRespond(
          request,
          statusCode: HttpStatus.requestEntityTooLarge,
          body: {'ok': false, 'reason': 'too_large', 'limit': kMaxVideoBytes},
        );
        return;
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.badRequest,
        body: {'ok': false, 'reason': 'empty_body'},
      );
      return;
    }

    try {
      final stagedName = await InfiniteCanvasAssetBridge.instance
          .stageIncomingVideo(
            episodeId: episodeId,
            suggestedName: fileName,
            bytes: bytes,
          );
      staged.add(
        StagedVideo(
          fileName: stagedName,
          seriesId: seriesId,
          episodeId: episodeId,
          bytes: bytes.length,
          targetIsSegment:
              (request.uri.queryParameters['targetIsSegment'] ?? 'true') !=
              'false',
        ),
      );
      await _safeRespond(
        request,
        statusCode: HttpStatus.ok,
        body: {'ok': true, 'staged': stagedName},
      );
    } catch (e) {
      debugPrint('[InfiniteCanvasBridge] 落盘视频失败: $e');
      await _safeRespond(
        request,
        statusCode: HttpStatus.internalServerError,
        body: {'ok': false, 'reason': 'write_failed'},
      );
    }
  }

  Future<bool> _isInside(File file, String dir) async {
    final resolved = p.normalize(file.absolute.path);
    final root = p.normalize(Directory(dir).absolute.path);
    return p.isWithin(root, resolved) || p.equals(root, resolved);
  }

  void _applyCorsHeaders(HttpRequest request) {
    final origin = request.headers.value('Origin');
    if (origin == null || origin.isEmpty) return;
    final headers = request.response.headers;
    // 画布页面与本服务不同源（localhost:3000 vs 127.0.0.1:8798），必须回显
    // ACAO，否则浏览器拦截 `uploadImage` 的拉取（design D2）。
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Vary', 'Origin');
    headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    headers.set('Access-Control-Max-Age', '600');
  }

  Future<void> _safeRespond(
    HttpRequest request, {
    required int statusCode,
    required Map<String, dynamic> body,
  }) async {
    try {
      _applyCorsHeaders(request);
      final headers = request.response.headers;
      headers.contentType = ContentType.json;
      headers.set('Cache-Control', 'no-store');
      request.response.statusCode = statusCode;
      request.response.write(jsonEncode(body));
      await request.response.close();
    } catch (e) {
      debugPrint('[InfiniteCanvasBridge] 写响应失败（对端可能已断开）: $e');
    }
  }

  Future<void> _respondJs(HttpRequest request, String source) async {
    try {
      _applyCorsHeaders(request);
      final headers = request.response.headers;
      headers.contentType = ContentType('text', 'javascript', charset: 'utf-8');
      headers.set('Cache-Control', 'no-store');
      request.response.statusCode = HttpStatus.ok;
      request.response.write(source);
      await request.response.close();
    } catch (e) {
      debugPrint('[InfiniteCanvasBridge] 写插件源码失败: $e');
    }
  }

  /// 定长比较，避免用 `==` 早退暴露「猜对了几个字符」的时序。
  bool _constantTimeEquals(String a, String b) {
    final aa = utf8.encode(a);
    final bb = utf8.encode(b);
    if (aa.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < aa.length; i++) {
      diff |= aa[i] ^ bb[i];
    }
    return diff == 0;
  }
}

/// 一个已落盘、等待归集的视频。
@immutable
class StagedVideo {
  const StagedVideo({
    required this.fileName,
    required this.seriesId,
    required this.episodeId,
    required this.bytes,
    required this.targetIsSegment,
  });

  final String fileName;
  final String seriesId;
  final String episodeId;
  final int bytes;
  final bool targetIsSegment;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'seriesId': seriesId,
    'episodeId': episodeId,
    'bytes': bytes,
    'targetIsSegment': targetIsSegment,
  };
}

/// 显式拒绝上游配置文件（design D8）。
///
/// 单独成函数以便单测——它要在任何路径上都被拦，包括用户把文件名拼进
/// `fileName` query 参数。
bool isForbiddenConfigName(String name) =>
    p.basename(name) == kForbiddenConfigFile;
