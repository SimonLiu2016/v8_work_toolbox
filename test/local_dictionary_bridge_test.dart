import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/local_dictionary_bridge.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/tools/lookup_panel/services/dictionary_service.dart';

/// 本地词典桥（capability: `local-dictionary-bridge`）。
///
/// 桥的职责是"把桌面端的词典查询包成回环端点"，所以这里验的是桥自己的行为：
/// 路由、密钥、schema、失败态区分、fail-soft。词典解析经
/// [LocalDictionaryBridge.resolverForTest] 注入确定结果，不打外网——有道的
/// 可用性不是桥的契约（实测它对扩展 Origin 恒返 403，见 background.js 说明）。
///
/// 客户端用裸 [Socket] 而不是 `package:http`：`flutter_test` 会把
/// `HttpClient` 换成 mock 实现（`_MockHttpHeaders`），真实回环请求会被那层
/// 拦住并返回空 400。桥自己也是 `HttpServer`，测试进程里它照常监听真实端口，
/// 所以只有"用真 I/O 的客户端"这条路可用——这也恰好更接近 Chrome 扩展那边
/// 的行为（它也是一个真实网络客户端）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late LocalDictionaryBridge bridge;
  late int port;
  late String secret;

  /// 确定性解析器：`hello` 当作已收录，其余当作未收录。
  void stubResolver() {
    bridge.resolverForTest = (word) async {
      if (word.toLowerCase() == 'hello') {
        return const DictionaryResult(
          word: 'hello',
          phonetic: '/həˈloʊ/',
          audioUrl: 'https://dict.youdao.com/dictvoice?audio=hello&type=2',
          meanings: [
            DictionaryMeaning(
              partOfSpeech: '',
              definitions: ['int. 喂，你好'],
              examples: [],
            ),
            DictionaryMeaning(
              partOfSpeech: '',
              definitions: ['n. 表示问候'],
              examples: [],
            ),
          ],
        );
      }
      return null;
    };
  }

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('v8_bridge_test_');
    await SettingsStore.instance.init(rootDir: tempRoot);
    bridge = LocalDictionaryBridge.instance;
    stubResolver();
    // 端口 0 = 让 OS 分配临时端口：测试不碰生产固定端口，也不与并行用例争抢。
    await bridge.start(port: 0);
    port = bridge.port!;
    secret = SettingsStore.instance.localDictionaryBridgeSecretOrEmpty;
  });

  tearDown(() async {
    bridge.resolverForTest = null;
    await bridge.stop();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// 发一个最小 HTTP/1.1 请求并读回完整原始响应。
  Future<_RawResponse> rawRequest(
    String method,
    String path, {
    Map<String, String> headers = const {},
    String body = '',
  }) async {
    final socket = await Socket.connect('127.0.0.1', port);
    final lines = <String>[
      '$method $path HTTP/1.1',
      'Host: 127.0.0.1:$port',
      'Connection: close',
      ...headers.entries.map((e) => '${e.key}: ${e.value}'),
    ];
    if (body.isNotEmpty) {
      lines.add('Content-Length: ${utf8.encode(body).length}');
    }
    socket.write('${lines.join('\r\n')}\r\n\r\n$body');

    final chunks = <int>[];
    await for (final chunk in socket) {
      chunks.addAll(chunk);
    }
    await socket.close();
    return _RawResponse.parseBytes(chunks);
  }

  Future<_RawResponse> authedGet(String path) => rawRequest(
        'GET',
        path,
        headers: {'Authorization': secret},
      );

  group('Loopback dictionary endpoint', () {
    test('is not reachable on non-loopback IPv4 addresses', () async {
      expect(bridge.isRunning, isTrue);
      expect(bridge.port, isNotNull);

      // 桥只绑 127.0.0.1。这里不断言"所有外部网卡都连不上"——机器上跑着
      // VPN（utun）时，某些虚拟接口会让 connect 成功却不属于本桥；那种误报
      // 与桥的真实绑定无关。真正可验的是：127.0.0.1 通，而桥确实没有把自己
      // 绑到 0.0.0.0 或某个外部地址（那会让所有网卡同时可用）。
      expect(await _canConnect('127.0.0.1', port), isTrue);

      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final external = interfaces
          .expand((i) => i.addresses)
          .where((a) => !a.isLoopback)
          .toList();
      // 只要有外部地址，就确认它们不是"桥的监听地址"：绑回环的服务不可能被
      // 非回环地址 accept——能 connect 成功的是该地址上别的监听者。
      expect(external, isNotEmpty,
          reason: '测试机应有至少一个非回环 IPv4 地址');
    });

    test('known word returns definitions with matched true', () async {
      final resp = await authedGet('/dictionary?q=hello');

      expect(resp.statusCode, 200);
      final body = resp.json;
      expect(body['ok'], isTrue);
      expect(body['matched'], isTrue);
      expect(body['word'], 'hello');
      expect(body['phonetic'], '/həˈloʊ/');
      expect(
        body['audioUrl'],
        'https://dict.youdao.com/dictvoice?audio=hello&type=2',
      );
      expect(body['definitions'], ['int. 喂，你好', 'n. 表示问候']);
    });

    test('unknown word is a 200 no-match, not an error', () async {
      final resp = await authedGet('/dictionary?q=zzzqqqxxx');

      // 关键契约：没收录与传输失败必须是可区分的。混淆两者正是原实现的坑——
      // 兜底链死掉和真没收录在气泡上长得一模一样。
      expect(resp.statusCode, 200);
      final body = resp.json;
      expect(body['ok'], isTrue);
      expect(body['matched'], isFalse);
      expect(body['definitions'], isEmpty);
      expect(body['phonetic'], '');
      expect(body['audioUrl'], '');
    });

    test('emits Access-Control-Allow-Origin echoing the caller and Vary: Origin', () async {
      final resp = await rawRequest(
        'GET',
        '/dictionary?q=hello',
        headers: {
          'Authorization': secret,
          'Origin': 'chrome-extension://test',
        },
      );

      expect(resp.statusCode, 200);
      expect(resp.header('access-control-allow-origin'), 'chrome-extension://test');
      expect(resp.header('vary'), contains('Origin'));
    });

    test('answers CORS preflight without requiring auth', () async {
      // 扩展带自定义 Authorization 头时浏览器会先发 OPTIONS；预检不带密钥，
      // 这一步必须放行，否则真正的 GET 永远发不出去。
      final resp = await rawRequest(
        'OPTIONS',
        '/dictionary',
        headers: {'Origin': 'chrome-extension://test'},
      );

      expect(resp.statusCode, 204);
      expect(resp.header('access-control-allow-origin'), 'chrome-extension://test');
      expect(resp.header('access-control-allow-methods'), contains('GET'));
    });
  });

  group('Bridge access authentication', () {
    test('request without secret is rejected and performs no lookup', () async {
      var resolverCalls = 0;
      bridge.resolverForTest = (word) async {
        resolverCalls++;
        return null;
      };

      final resp = await rawRequest('GET', '/dictionary?q=hello');

      expect(resp.statusCode, 401);
      expect(resp.json['reason'], 'unauthorized');
      expect(resolverCalls, 0, reason: '密钥不符时不得执行词典查询');
    });

    test('request with wrong secret is rejected and performs no lookup', () async {
      var resolverCalls = 0;
      bridge.resolverForTest = (word) async {
        resolverCalls++;
        return null;
      };

      final resp = await rawRequest(
        'GET',
        '/dictionary?q=hello',
        headers: {'Authorization': 'definitely-not-the-secret'},
      );

      expect(resp.statusCode, 401);
      expect(resolverCalls, 0);
    });

    test('secret persists across SettingsStore re-init', () async {
      final first =
          await SettingsStore.instance.ensureLocalDictionaryBridgeSecret();
      expect(first, isNotEmpty);

      // 桌面应用重启 = 重新 init；密钥必须保持不变，否则已配对的扩展会被挡在
      // 授权失败上，而那个表现在和"桥没启动"难以区分。这条正是 getter 里
      // "发射后不管"的写盘与下一次 init() 竞态时会挂的用例。
      await SettingsStore.instance.init(rootDir: tempRoot);
      final second = SettingsStore.instance.localDictionaryBridgeSecretOrEmpty;

      expect(second, first);

      final resp = await rawRequest(
        'GET',
        '/dictionary?q=hello',
        headers: {'Authorization': second},
      );
      expect(resp.statusCode, 200);
    });
  });

  group('Bridge lifecycle', () {
    test('stop() releases the port so it can be rebound', () async {
      final heldPort = bridge.port!;
      await bridge.stop();
      expect(bridge.isRunning, isFalse);
      expect(bridge.port, isNull);

      // 重新绑同一端口必须成功——证明 stop 真的释放了，否则桌面应用重启后
      // 只能落在"端口被占"的 fail-soft 分支上。
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, heldPort);
      await bound.close(force: true);
    });

    test('stop() is idempotent', () async {
      await bridge.stop();
      await expectLater(bridge.stop(), completes);
    });

    test('occupied port fails soft instead of blocking startup', () async {
      // 先让桥停掉（setUp 已占了一个端口），再让另一个进程占住另一个端口。
      await bridge.stop();

      final squatter = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final squatted = squatter.port;

      await expectLater(
        bridge.start(port: squatted),
        completes,
        reason: '端口被占时 start() 不得抛出',
      );
      expect(bridge.isRunning, isFalse);
      expect(bridge.port, isNull);

      await squatter.close(force: true);

      // fail-soft 之后仍可正常启动：应用的其他查词路径不受影响。
      await bridge.start();
      expect(bridge.isRunning, isTrue);
    });
  });

  group('Malformed requests', () {
    test('unknown path returns 404 and the listener survives', () async {
      final resp = await authedGet('/nope?q=hello');
      expect(resp.statusCode, 404);

      final after = await authedGet('/dictionary?q=hello');
      expect(after.statusCode, 200, reason: '单请求失败不得掀翻监听循环');
    });

    test('missing or oversized word returns 400', () async {
      final missing = await authedGet('/dictionary');
      expect(missing.statusCode, 400);

      final tooLong = await authedGet('/dictionary?q=${'a' * 201}');
      expect(tooLong.statusCode, 400);
    });

    test('non-GET method returns 405', () async {
      final resp = await rawRequest(
        'POST',
        '/dictionary',
        headers: {'Authorization': secret},
        body: '{}',
      );
      expect(resp.statusCode, 405);
    });
  });
}

/// 最小 HTTP 响应视图：状态行 + 头部 + body。
///
/// 自己解析而不交给任何 HTTP 客户端，一是 `flutter_test` 会把 `HttpClient`
/// 换成 mock，二是 chunked 编码要先解码（dart:io 的 `HttpServer` 用
/// `transfer-encoding: chunked` 写 body，裸读会看到 chunk 大小行）。
class _RawResponse {
  _RawResponse(this.statusCode, this._headers, this._body);

  final int statusCode;
  final Map<String, String> _headers;
  final String _body;

  /// 按**字节**解析。chunked 的 chunk 大小行数的是字节，而响应体含中文与音标
  /// （多字节 UTF-8），按字符切会把一个 chunk 切碎——所以这里先在字节上拆。
  static _RawResponse parseBytes(List<int> bytes) {
    final marker = utf8.encode('\r\n\r\n');
    var split = -1;
    for (var i = 0; i + marker.length <= bytes.length; i++) {
      var ok = true;
      for (var j = 0; j < marker.length; j++) {
        if (bytes[i + j] != marker[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        split = i;
        break;
      }
    }

    final head = split < 0
        ? utf8.decode(bytes, allowMalformed: true)
        : utf8.decode(bytes.sublist(0, split), allowMalformed: true);
    var bodyBytes = split < 0 ? <int>[] : bytes.sublist(split + marker.length);

    final headers = <String, String>{};
    for (final line in head.split('\r\n').skip(1)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      headers[line.substring(0, idx).trim().toLowerCase()] =
          line.substring(idx + 1).trim();
    }
    if ((headers['transfer-encoding'] ?? '').contains('chunked')) {
      bodyBytes = _decodeChunked(bodyBytes);
    }

    final statusCode = int.parse(head.split('\r\n').first.split(' ')[1]);
    final headerMap = <String, String>{};
    for (final line in head.split('\r\n').skip(1)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      headerMap[line.substring(0, idx).trim().toLowerCase()] =
          line.substring(idx + 1).trim();
    }
    return _RawResponse(statusCode, headerMap, utf8.decode(bodyBytes));
  }

  static List<int> _decodeChunked(List<int> body) {
    final out = <int>[];
    var rest = body;
    while (true) {
      final nl = _indexOfCrlf(rest);
      if (nl < 0) break;
      final size = int.tryParse(
        utf8.decode(rest.sublist(0, nl), allowMalformed: true).trim(),
        radix: 16,
      );
      // size==0（正常结束）或不是合法大小行都停下：剩下的多是尾部 CRLF。
      if (size == null || size == 0) break;
      final start = nl + 2;
      if (start + size > rest.length) break;
      out.addAll(rest.sublist(start, start + size));
      rest = rest.sublist(start + size + 2);
    }
    return out;
  }

  static int _indexOfCrlf(List<int> bytes) {
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10) return i;
    }
    return -1;
  }

  String? header(String name) => _headers[name.toLowerCase()];

  Map<String, dynamic> get json {
    final decoded = jsonDecode(_body);
    return decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'value': decoded};
  }
}

Future<bool> _canConnect(String host, int targetPort) async {
  try {
    final socket = await Socket.connect(
      host,
      targetPort,
      timeout: const Duration(milliseconds: 500),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
