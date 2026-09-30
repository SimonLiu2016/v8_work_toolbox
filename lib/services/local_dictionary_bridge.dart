import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../tools/lookup_panel/services/dictionary_service.dart';
import '../tools/lookup_panel/services/youdao_service.dart';
import 'settings_store.dart';

/// 本地词典桥（capability: `local-dictionary-bridge`）。
///
/// 存在的原因是一次实测：浏览器扩展的 service worker 直连 `dict.youdao.com/jsonapi`
/// 恒返 `403 Invalid CORS request`。`host_permissions` 只让 Chrome 跳过浏览器这一侧的
/// CORS 检查，**不会把 `Origin: chrome-extension://…` 请求头抹掉**，服务端照旧按 CORS
/// 拒绝；备用源 `api.dictionaryapi.dev` 实测 ~20s 后回 Cloudflare 522。而 MV3 的规则是
/// fetch 响应超过 30s 即杀掉 service worker，那次 `sendResponse` 就永远发不出去。
///
/// 换源（datamuse 等有 CORS 头的公共 API）只能救英文释义，救不了 EN→ZH 主场景，还会让
/// 词典解析分叉出第二份实现。所以这里反过来做：桌面应用把既有的词典查询包成一个回环
/// 端点，`Access-Control-Allow-Origin` 由我们自己写，扩展退化成 UI 壳，词典实现仍然
/// 只有一处（[YoudaoService]）。
///
/// 边界（spec: `local-dictionary-bridge`）：
///   * 只听 `127.0.0.1`，其他网卡不可达；
///   * 每个请求都要校验共享密钥，不匹配直接拒且**不做词典查询**；
///   * 只读，生词本写路径不在此暴露；
///   * 端口被占时 fail-soft：不向启动流程抛异常，其余查词路径（热键、Services、深度链接）
///     全部照常。
class LocalDictionaryBridge {
  LocalDictionaryBridge._();
  static final LocalDictionaryBridge instance = LocalDictionaryBridge._();

  /// 桌面端词典查询自身有 4s 超时（`YoudaoService._timeout`），扩展侧另有 2.5s
  /// 客户端超时；这里的上限是给"桥自己卡住"兜底的，不是给正常查询放宽的。
  static const Duration _handlerTimeout = Duration(seconds: 8);

  HttpServer? _server;

  /// 词典解析注入点。生产恒为 null（走 [YoudaoService.lookupFull]）；测试用它
  /// 把"已知词/未知词"做成确定结果，不必真连外网。
  @visibleForTesting
  set resolverForTest(Future<DictionaryResult?> Function(String word)? resolver) =>
      _resolver = resolver;

  Future<DictionaryResult?> Function(String word)? _resolver;

  /// 当前监听端口；未监听时为 null。
  int? get port {
    final server = _server;
    return server?.port;
  }

  bool get isRunning => _server != null;

  /// 启动桥。任何失败都只记录诊断信号，不向外抛——调用方（`main()`）的契约是
  /// "桥起不来不影响应用启动"。
  ///
  /// [port] 仅供测试绑定到临时端口；生产走 [SettingsStore.localBridgePort]。
  Future<void> start({int? port}) async {
    if (_server != null) return;

    final bindPort = port ?? SettingsStore.instance.localBridgePort;
    try {
      // 先确保密钥已落盘再生产服务器：getter 里"发射后不管"的写盘会与下一次
      // init() 竞态，让已配对的扩展拿到一个过期密钥（表现是授权失败，与桥没
      // 启动难以区分）。
      await SettingsStore.instance.ensureLocalDictionaryBridgeSecret();
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        bindPort,
        shared: false,
      );
      // 不开 autoCompress：负载是 1-2KB 的 JSON，压缩省不下什么，却会把响应
      // 变成 gzip + chunked 的组合——Dart 的 HttpClient（测试客户端、以及任何
      // 将来复用这条桥的 Dart 代码）读这种响应会拿到 400。回环上不值得。
      server.idleTimeout = _handlerTimeout;
      _server = server;
      _serve(server);
      debugPrint('[LocalDictionaryBridge] 已监听 127.0.0.1:${server.port}');
    } catch (e, stack) {
      _server = null;
      // 端口被占是最常见的一种：另一个进程（或本应用的另一个窗口）持着它。
      // 这里必须留下可诊断的信号，否则"查词没反应"会被当成桥在工作。
      debugPrint(
        '[LocalDictionaryBridge] 启动失败（127.0.0.1:$bindPort），'
        '浏览器伴侣的划词查词将不可用，其余查词路径不受影响: $e\n$stack',
      );
    }
  }

  /// 停止监听。幂等；在 `runShutdownCleanup()` 中调用，避免孤儿进程持有端口
  /// （与 mihomo 子进程同一类问题）。
  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    try {
      await server.close(force: true);
    } catch (e) {
      debugPrint('[LocalDictionaryBridge] 关闭异常（端口已释放）: $e');
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request).timeout(_handlerTimeout);
      } on TimeoutException {
        await _safeRespond(
          request,
          statusCode: HttpStatus.gatewayTimeout,
          body: {'ok': false, 'reason': 'handler_timeout'},
        );
      } catch (e, stack) {
        // 单请求异常绝不能掀翻监听循环：socket 可能已被对端关闭，此时
        // respond 会再抛一次。记下来，继续服务下一个请求。
        debugPrint('[LocalDictionaryBridge] 请求处理异常: $e\n$stack');
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    // 预检：扩展的 fetch 在带自定义 Header（Authorization）时会先发 OPTIONS。
    if (request.method == 'OPTIONS') {
      _applyCorsHeaders(request);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method != 'GET') {
      await _safeRespond(
        request,
        statusCode: HttpStatus.methodNotAllowed,
        body: {'ok': false, 'reason': 'method_not_allowed'},
      );
      return;
    }

    // 密钥校验先于任何解析与查询：不匹配时不做词典查询（spec 的显式要求）。
    final expected = SettingsStore.instance.localDictionaryBridgeSecretOrEmpty;
    final supplied =
        request.headers.value('Authorization') ??
        request.uri.queryParameters['secret'];
    if (supplied == null || !_constantTimeEquals(supplied, expected)) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.unauthorized,
        body: {'ok': false, 'reason': 'unauthorized'},
      );
      return;
    }

    final path = request.uri.path;
    if (path != '/dictionary' && path != '/dictionary/') {
      await _safeRespond(
        request,
        statusCode: HttpStatus.notFound,
        body: {'ok': false, 'reason': 'not_found'},
      );
      return;
    }

    final word = (request.uri.queryParameters['q'] ?? '').trim();
    if (word.isEmpty || word.length > 200) {
      await _safeRespond(
        request,
        statusCode: HttpStatus.badRequest,
        body: {'ok': false, 'reason': 'bad_word'},
      );
      return;
    }

    // 已解析的词典引用（`DictionaryResult?`）。测试可在此替换，避免每次跑测试
    // 都真去打有道的网络——桥要验证的是"桥自己"的行为：路由、密钥、schema、
    // 失败态区分，而不是有道通不通。
    final result = await (_resolver ?? YoudaoService.lookupFull)(word);
    final matched = result != null && result.meanings.isNotEmpty;

    await _safeRespond(
      request,
      statusCode: HttpStatus.ok,
      body: {
        'ok': true,
        'word': word,
        'matched': matched,
        'phonetic': matched ? (result.phonetic ?? '') : '',
        'audioUrl': matched ? (result.audioUrl ?? '') : '',
        // 降平：气泡按 `adj. 短暂的` 这整串渲染，词性 chip 由 content.js 用
        // 正则从串首切出来，与桌面端 `allDefinitions` 的展示一致。
        'definitions': matched ? result.allDefinitions : <String>[],
      },
    );
  }

  /// 写入 CORS 响应头。只有带上 `Origin` 的跨域调用方（即扩展上下文）才需要
  /// 回显 ACAO；同源的命令行请求回显同一个值也无害。`Vary: Origin` 让任何
  /// 中间缓存按调用方分桶。
  void _applyCorsHeaders(HttpRequest request) {
    final origin = request.headers.value('Origin');
    if (origin == null || origin.isEmpty) return;
    final headers = request.response.headers;
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Vary', 'Origin');
    headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    headers.set('Access-Control-Max-Age', '600');
  }

  /// 发包失败不得冒泡到 [_serve] 之外——对端提前关闭时 respond 会抛
  /// `HttpException`，那属于正常网络噪声。
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
      debugPrint('[LocalDictionaryBridge] 写响应失败（对端可能已断开）: $e');
    }
  }

  /// 定长比较，避免用 `==` 早退暴露"猜对了几个字符"的时序。
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
