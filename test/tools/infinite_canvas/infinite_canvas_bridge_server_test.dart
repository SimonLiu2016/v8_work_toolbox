import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/settings_store.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_asset_bridge.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_bridge_models.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_bridge_server.dart';
import 'package:V8WorkToolbox/tools/infinite_canvas/services/infinite_canvas_canvas_plugin_source.dart';

/// 资产桥服务的契约测试（spec: 资产桥的传输通道 / 密钥边界 / 导出内容范围）。
///
/// 关键注入点：服务可绑定到临时端口，测试用真实 HttpClient 打过去——不 mock
/// HTTP，因为要验的正是路由、CORS、密钥与拒绝路径这些「桥自己」的行为。
void main() {
  late Directory tempDir;
  late InfiniteCanvasBridgeServer server;
  late int port;
  late String secret;

  Future<Map<String, dynamic>> getJson(String path, {String? auth}) async {
    final res = await http.get(
      Uri.parse('http://127.0.0.1:$port$path'),
      headers: {if (auth != null) 'Authorization': auth},
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<http.Response> postRaw(
    String path, {
    required List<int> body,
    String? auth,
  }) async {
    return http.post(
      Uri.parse('http://127.0.0.1:$port$path'),
      headers: {
        if (auth != null) 'Authorization': auth,
        'Content-Type': 'application/octet-stream',
      },
      body: body,
    );
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ic_bridge');
    AppPaths.overrideRootForTesting(tempDir);
    await SettingsStore.instance.init();
    secret = await SettingsStore.instance.ensureLocalDictionaryBridgeSecret();

    server = InfiniteCanvasBridgeServer.instance;
    await server.stop();
    final started = await server.start(port: 0);
    expect(started, isTrue, reason: '测试里必须能起到服务');
    port = server.port!;
  });

  tearDown(() async {
    await server.stop();
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('插件源码', () {
    test('不需要密钥即可获取，且 baseUrl 被烤进去', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/v8-plugin.js'),
      );
      expect(res.statusCode, 200);
      final source = res.body;
      expect(source, contains('http://127.0.0.1:$port'));
      expect(source, isNot(contains('__V8_BASE_URL__')));
      // 必须走宿主的 React，不打包自己的副本。
      expect(source, contains('runtime.React'));
      // 必须声明最低宿主版本，SDK 漂移时可诊断。
      expect(source, contains('minAppVersion'));
    });

    test('renderPluginSource 是可独立调用的纯函数', () {
      final src = renderPluginSource(baseUrl: 'http://127.0.0.1:1234');
      expect(src, contains('http://127.0.0.1:1234'));
      expect(src, contains(kPluginId));
    });
  });

  group('密钥边界', () {
    test('无密钥时数据端点一律 401，且不做任何查询', () async {
      for (final path in const [
        '/api/episodes',
        '/api/export?seriesId=x&episodeId=y',
        '/api/handshake',
      ]) {
        final res = await http.get(Uri.parse('http://127.0.0.1:$port$path'));
        expect(res.statusCode, 401, reason: path);
      }
    });

    test('错密钥同样 401', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/episodes'),
        headers: {'Authorization': 'wrong-secret'},
      );
      expect(res.statusCode, 401);
    });

    test('正确密钥通过', () async {
      final data = await getJson('/api/episodes', auth: secret);
      expect(data['ok'], isTrue);
    });

    test('密钥可从 query 传（插件在某些环境下不方便带头）', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/episodes?secret=$secret'),
      );
      expect(res.statusCode, 200);
    });
  });

  group('CORS', () {
    test('OPTIONS 预检回显 ACAO', () async {
      final req = http.Request(
        'OPTIONS',
        Uri.parse('http://127.0.0.1:$port/api/episodes'),
      )..headers['Origin'] = 'http://localhost:3000';
      final res = await http.Client().send(req).then((r) => http.Response.fromStream(r));
      expect(res.statusCode, 204);
      expect(
        res.headers['access-control-allow-origin'],
        'http://localhost:3000',
        reason: '画布页面与服务不同源，不回显 ACAO 浏览器会拦下拉取',
      );
    });

    test('数据响应也带 ACAO', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/episodes'),
        headers: {'Authorization': secret, 'Origin': 'http://localhost:3000'},
      );
      expect(res.headers['access-control-allow-origin'], 'http://localhost:3000');
    });
  });

  group('选集列表', () {
    test('空工坊返回空数组而不是报错', () async {
      final data = await getJson('/api/episodes', auth: secret);
      expect(data['series'], isA<List>());
      expect((data['series'] as List), isEmpty);
    });

    test('列出剧集与其集', () async {
      final manager = StudioProjectManager.instance;
      final series = await manager.createSeries(name: '测试剧集');
      await manager.createEpisode(seriesId: series.id, title: '第一集');

      final data = await getJson('/api/episodes', auth: secret);
      final list = data['series'] as List;
      expect(list, hasLength(1));
      expect((list.first as Map)['seriesName'], '测试剧集');
      expect(((list.first as Map)['episodes'] as List), hasLength(1));
    });
  });

  group('导出载荷', () {
    late String seriesId;
    late String episodeId;

    setUp(() async {
      final manager = StudioProjectManager.instance;
      final series = await manager.createSeries(name: '导出剧集');
      seriesId = series.id;
      await manager.saveSeries(
        series.copyWith(worldview: '末世后的废土', styleTokens: 'cinematic'),
      );
      final created = await manager.createEpisode(seriesId: seriesId);
      episodeId = created.episode.id;
      var ep = manager.readEpisode(seriesId, episodeId)!;
      ep = ep.copyWith(
        synopsis: '主角踏上旅途',
        shots: const [
          StudioShot(number: 1, durationSec: 3, actionZh: '推开大门'),
          StudioShot(number: 2, durationSec: 4, actionZh: '走进荒野'),
        ],
      );
      await manager.saveEpisode(ep);
    });

    test('载荷含文本与图片节点，且图片节点带 loopback URL', () async {
      final data = await getJson(
        '/api/export?seriesId=$seriesId&episodeId=$episodeId',
        auth: secret,
      );
      expect(data['ok'], isTrue);
      final payload = CanvasExportPayload.fromJson(
        data['payload'] as Map<String, dynamic>,
      );
      final kinds = payload.nodes.map((n) => n.kind).toSet();
      expect(kinds, contains('text'));
      // 世界观 + 剧本两个文本节点必然在。
      expect(payload.nodes.where((n) => n.kind == 'text'), hasLength(2));
      // 每个节点都带 v8 元数据（design D4）。
      for (final n in payload.nodes) {
        expect(n.metadata.containsKey('v8'), isTrue, reason: n.title);
        final v8 = n.metadata['v8'] as Map;
        expect(v8['seriesId'], seriesId);
        expect(v8['episodeId'], episodeId);
      }
    });

    test('节点 id 确定性——重复导出两次得到同一批 id', () async {
      Future<List<String>> ids() async {
        final data = await getJson(
          '/api/export?seriesId=$seriesId&episodeId=$episodeId',
          auth: secret,
        );
        final payload = CanvasExportPayload.fromJson(
          data['payload'] as Map<String, dynamic>,
        );
        return payload.nodes.map((n) => n.id).toList();
      }

      expect(await ids(), await ids());
    });

    test('分镜表渲染进文本节点', () async {
      final data = await getJson(
        '/api/export?seriesId=$seriesId&episodeId=$episodeId',
        auth: secret,
      );
      final payload = CanvasExportPayload.fromJson(
        data['payload'] as Map<String, dynamic>,
      );
      final script = payload.nodes.firstWhere((n) => n.kind == 'text'
          && n.title.contains('分镜'));
      expect(script.markdown, contains('镜头 1'));
      expect(script.markdown, contains('推开大门'));
      expect(script.markdown, contains('镜头 2'));
    });

    test('载荷里没有任何 base64 图片数据', () async {
      final data = await getJson(
        '/api/export?seriesId=$seriesId&episodeId=$episodeId',
        auth: secret,
      );
      final raw = jsonEncode(data);
      expect(raw, isNot(contains('base64,')));
      expect(raw, isNot(contains('data:image/')));
    });

    test('目标不存在时报 not_found 而不是 500', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/export?seriesId=x&episodeId=y'),
        headers: {'Authorization': secret},
      );
      expect(res.statusCode, 404);
    });

    test('缺参数时报 bad_request', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/export'),
        headers: {'Authorization': secret},
      );
      expect(res.statusCode, 400);
    });
  });

  group('参考图路由', () {
    test('剧集目录下的文件可读，且带 ACAO', () async {
      final manager = StudioProjectManager.instance;
      final series = await manager.createSeries(name: '带图剧集');
      final character = await manager.createCharacter(
        seriesId: series.id,
        name: '林拓',
      );
      final dir = manager.characterDir(series.id, character.id);
      dir.createSync(recursive: true);
      final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      File(p.join(dir.path, 'ref.png')).writeAsBytesSync(png);

      final res = await http.get(
        Uri.parse(
          'http://127.0.0.1:$port/assets/${series.id}/characters/${character.id}/ref.png',
        ),
        headers: {'Authorization': secret, 'Origin': 'http://localhost:3000'},
      );
      expect(res.statusCode, 200);
      expect(res.bodyBytes, png);
      expect(
        res.headers['access-control-allow-origin'],
        'http://localhost:3000',
      );
    });

    test('路径穿越被拒', () async {
      for (final evil in const [
        '/assets/..%2f..%2fetc/passwd',
        '/assets/a/../../../../etc/passwd',
        '/assets/./../app.json',
      ]) {
        final res = await http.get(
          Uri.parse('http://127.0.0.1:$port$evil'),
          headers: {'Authorization': secret},
        );
        expect(res.statusCode, isNot(200), reason: evil);
      }
    });

    test('剧集目录外的文件不可读', () async {
      // app.json 在 root 下而不是剧集目录下。
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/assets/../app.json'),
        headers: {'Authorization': secret},
      );
      expect(res.statusCode, isNot(200));
    });

    test('不存在的文件报 404', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/assets/nope/missing.png'),
        headers: {'Authorization': secret},
      );
      expect(res.statusCode, 404);
    });
  });

  group('导回接收', () {
    test('视频字节原样落盘并可被归集', () async {
      final manager = StudioProjectManager.instance;
      final series = await manager.createSeries(name: '归集剧集');
      final created = await manager.createEpisode(seriesId: series.id);
      var ep = manager.readEpisode(series.id, created.episode.id)!;
      ep = ep.copyWith(
        shots: const [
          StudioShot(number: 1, durationSec: 3, actionZh: 'a'),
          StudioShot(number: 2, durationSec: 3, actionZh: 'b'),
        ],
      );
      await manager.saveEpisode(ep);

      final bytes = List<int>.generate(1024, (i) => i % 256);
      final res = await postRaw(
        '/api/import?seriesId=${series.id}&episodeId=${created.episode.id}'
        '&fileName=shot1.mp4&targetIsSegment=true',
        body: bytes,
        auth: secret,
      );
      expect(res.statusCode, 200);
      final staged =
          (jsonDecode(res.body) as Map<String, dynamic>)['staged'] as String;
      expect(staged, isNotEmpty);

      final entry = CanvasVideoEntry(
        fileName: staged,
        bytes: bytes.length,
        v8: <String, dynamic>{
          'seriesId': series.id,
          'episodeId': created.episode.id,
          'entityKind': 'shot',
          'entityId': '1',
        },
      );
      final result = await InfiniteCanvasAssetBridge.instance.importVideos(
        seriesId: series.id,
        episodeId: created.episode.id,
        entries: <CanvasVideoEntry>[entry],
        targetIsSegment: false,
      );
      expect(result.ok, isTrue);
      expect(result.imported, hasLength(1));

      final after = manager.readEpisode(series.id, created.episode.id)!;
      final withClip = after.shots.where((s) => s.clipPath != null).toList();
      expect(withClip, hasLength(1), reason: '按分镜顺序填入第一个空片段');
      expect(File(p.join(manager.episodeClipsDir(series.id, created.episode.id).path, withClip.first.clipPath!)).existsSync(), isTrue);
    });

    test('空 body 被拒', () async {
      final res = await postRaw(
        '/api/import?seriesId=a&episodeId=b&fileName=x.mp4',
        body: const <int>[],
        auth: secret,
      );
      expect(res.statusCode, 400);
    });

    test('缺参数被拒', () async {
      final res = await postRaw(
        '/api/import?seriesId=a',
        body: <int>[1, 2, 3],
        auth: secret,
      );
      expect(res.statusCode, 400);
    });

    test('无密钥时不被接收', () async {
      final res = await postRaw(
        '/api/import?seriesId=a&episodeId=b&fileName=x.mp4',
        body: <int>[1, 2, 3],
      );
      expect(res.statusCode, 401);
    });
  });

  group('显式拒绝上游配置文件（design D8）', () {
    test('把配置文件名拼进 fileName 也被拒', () async {
      final res = await postRaw(
        '/api/import?seriesId=a&episodeId=b'
        '&fileName=$kForbiddenConfigFile',
        body: <int>[1, 2, 3],
        auth: secret,
      );
      expect(res.statusCode, 400);
      expect(res.body, contains('forbidden'));
    });

    test('isForbiddenConfigName 识别各种写法', () {
      expect(isForbiddenConfigName('infinite-canvas-config.json'), isTrue);
      expect(isForbiddenConfigName('./infinite-canvas-config.json'), isTrue);
      expect(
        isForbiddenConfigName('/tmp/x/infinite-canvas-config.json'),
        isTrue,
      );
      expect(isForbiddenConfigName('shot1.mp4'), isFalse);
    });
  });

  group('握手与状态', () {
    test('握手成功并记录时间', () async {
      final before = server.lastHandshakeAt;
      final data = await getJson('/api/handshake', auth: secret);
      expect(data['ok'], isTrue);
      expect(data['pluginVersion'], kPluginVersion);
      expect(server.lastHandshakeAt != null, isTrue);
      expect(before == null || !server.lastHandshakeAt!.isBefore(before), isTrue);
    });

    test('未知路径 404', () async {
      final res = await http.get(
        Uri.parse('http://127.0.0.1:$port/nope'),
        headers: {'Authorization': secret},
      );
      expect(res.statusCode, 404);
    });
  });
}
