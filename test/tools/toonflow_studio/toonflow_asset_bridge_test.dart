import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_asset_bridge.dart';

/// 资产桥契约测试（spec: 资产导出的内容范围 / 写画布内容的权限边界 / 密钥边界）。
///
/// 固定六件事：
/// 1. 画布 JSON 带 `toonflowCanvas: true` 且 `edges` 恒为空——桥不替用户连线；
/// 2. 节点 `data.textPath` 指向真实存在的 `content.md`；
/// 3. 节点 id 确定——重复导出覆盖同名，不建第二份素材目录；
/// 4. `settings.json`（Toonflow 自己的供应商密钥，明文）mtime 不变，且内容
///    不出现在任何返回给调用方的字符串里；
/// 5. 导回是**复制**：Toonflow 侧原文件仍在；
/// 6. 目标集不存在时报告失败，不猜。
void main() {
  late Directory tempDir;
  late StudioProjectManager manager;
  late ToonflowAssetBridge bridge;
  late String seriesId;
  late String episodeId;

  /// 造一个 Toonflow 侧会保存供应商密钥的文件（明文，mode 600）。
  ///
  /// 本测试的核心断言之一就是：桥碰过工作区之后，这个文件的 mtime 与内容
  /// 一个字节都不变。
  File seedSettingsFile() {
    final settings = File(
      p.join(AppPaths.toonflowDataDir.path, 'settings.json'),
    );
    settings.parent.createSync(recursive: true);
    const payload = '{"providers":{"agnes":{"apiKey":"sk-CANARY-DO-NOT-LEAK"}}}';
    settings.writeAsStringSync(payload, flush: true);
    Process.runSync('chmod', ['600', settings.path]);
    return settings;
  }

  /// 在角色目录里放一张参考图，并把相对路径登记进卡片。
  Future<void> attachReference({
    required String characterId,
    required String fileName,
    required String content,
  }) async {
    final dir = manager.characterDir(seriesId, characterId);
    dir.createSync(recursive: true);
    File(p.join(dir.path, fileName)).writeAsStringSync(content);
    final card = manager.readCharacter(seriesId, characterId)!;
    await manager.saveCharacter(
      seriesId,
      card.copyWith(referenceImages: <String>[fileName]),
    );
  }

  Future<void> attachSceneReference({
    required String sceneId,
    required String fileName,
    required String content,
  }) async {
    final dir = manager.sceneDir(seriesId, sceneId);
    dir.createSync(recursive: true);
    File(p.join(dir.path, fileName)).writeAsStringSync(content);
    final card = manager.readScene(seriesId, sceneId)!;
    await manager.saveScene(
      seriesId,
      card.copyWith(referenceImages: <String>[fileName]),
    );
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('tf_bridge');
    AppPaths.overrideRootForTesting(tempDir);
    manager = StudioProjectManager.instance;
    bridge = ToonflowAssetBridge.instance;

    final series = await manager.createSeries(
      name: '测试剧集',
      worldview: '民国小镇，连雨不停',
      styleTokens: 'film grain, muted teal',
    );
    seriesId = series.id;
    final created = await manager.createEpisode(
      seriesId: seriesId,
      title: '雨夜来客',
      synopsis: '主角在客栈遇到神秘女子',
    );
    episodeId = created.episode.id;

    // 三个镜头，让分镜表有内容可渲染。
    var episode = manager.readEpisode(seriesId, episodeId)!;
    episode = episode.copyWith(
      shots: <StudioShot>[
        const StudioShot(number: 1, durationSec: 3, actionZh: '推门'),
        const StudioShot(number: 2, durationSec: 3, dialogue: '你迟到了'),
        const StudioShot(number: 3, durationSec: 3, cameraMove: 'pan'),
      ],
    );
    await manager.saveEpisode(episode);

    await manager.createCharacter(seriesId: seriesId, name: '沈舟');
    await manager.createScene(seriesId: seriesId, name: '临水客栈');
  });

  tearDown(() {
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('导出', () {
    test('画布带 toonflowCanvas 标记且 edges 恒为空', () async {
      final result = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      expect(result.ok, isTrue, reason: result.error);

      final canvas = File(
        p.join(result.workspaceDir!, '画布1.json'),
      ).readAsStringSync();
      final decoded = jsonDecode(canvas) as Map<String, dynamic>;

      expect(decoded['toonflowCanvas'], isTrue);
      expect(decoded['edges'], isEmpty,
          reason: '桥不替用户决定连线（spec: 写画布内容的权限边界）');
      expect(decoded['nodes'], isA<List>());
      expect((decoded['nodes'] as List).length, greaterThanOrEqualTo(4),
          reason: '世界观/剧本/角色/场景至少各一个节点');
    });

    test('textPath 指向真实存在的 content.md', () async {
      final result = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      final canvas = jsonDecode(
        File(p.join(result.workspaceDir!, '画布1.json')).readAsStringSync(),
      ) as Map<String, dynamic>;

      for (final raw in canvas['nodes'] as List) {
        final node = raw as Map<String, dynamic>;
        final data = node['data'] as Map<String, dynamic>;
        final textPath = data['textPath'];
        if (textPath == null) continue;
        // 节点里的相对路径必须能在工作区里解析到文件，否则 Toonflow 打开后
        // 是个读不到内容的空节点。
        expect(
          File(p.join(result.workspaceDir!, textPath as String)).existsSync(),
          isTrue,
          reason: '节点 ${node['id']} 的 textPath=$textPath 不存在',
        );
        expect(
          File(p.join(result.workspaceDir!, textPath))
              .readAsStringSync()
              .trim(),
          isNotEmpty,
          reason: 'content.md 不能是空文件',
        );
      }
    });

    test('导出的文本含世界观、风格锁、大纲与分镜', () async {
      // 不接 result：这条断言只看落盘的文本内容，导出成败由同组其他用例覆盖。
      await bridge.export(seriesId: seriesId, episodeId: episodeId);
      final text = bridge.workspaceDirFor(seriesId).listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.basename(f.path) == 'content.md')
          .map((f) => f.readAsStringSync())
          .join('\n');

      expect(text, contains('民国小镇，连雨不停'));
      expect(text, contains('film grain, muted teal'));
      expect(text, contains('主角在客栈遇到神秘女子'));
      expect(text, contains('推门'));
      expect(text, contains('你迟到了'));
      expect(text, contains('pan'));
    });

    test('参考图被拷进 assets/<nodeId>/', () async {
      final characters = await manager.listCharacters(seriesId);
      final scenes = await manager.listScenes(seriesId);

      await attachReference(
        characterId: characters.first.id,
        fileName: 'ref.png',
        content: 'fake-png-bytes',
      );
      await attachSceneReference(
        sceneId: scenes.first.id,
        fileName: 'view.png',
        content: 'fake-scene-png',
      );

      final result = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.skippedNotes, isEmpty,
          reason: '两个卡片都有参考图，不该有跳过提示');
      expect(
        result.writtenFiles.any((f) => f.endsWith('ref.png')),
        isTrue,
        reason: '角色参考图必须进清单',
      );
      expect(
        result.writtenFiles.any((f) => f.endsWith('view.png')),
        isTrue,
        reason: '场景参考图必须进清单',
      );

      // 文件真实存在，且内容是拷贝而非引用。
      final copied = bridge.workspaceDirFor(seriesId)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.basename(f.path) == 'ref.png')
          .toList();
      expect(copied, hasLength(1));
      expect(copied.single.readAsStringSync(), 'fake-png-bytes');
    });

    test('没有参考图的卡片产生跳过提示而不是失败', () async {
      final result = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      expect(result.ok, isTrue);
      expect(
        result.skippedNotes.any((n) => n.contains('沈舟')),
        isTrue,
        reason: '用户该知道 Toonflow 侧要自行生成角色图',
      );
    });

    test('重复导出覆盖同名，不建第二份素材目录', () async {
      final first = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      final dirAfterFirst = bridge.workspaceDirFor(seriesId)
          .listSync(recursive: true)
          .whereType<Directory>()
          .length;

      // 在画布里塞一个不该存活的手改字段，验证第二次导出真的覆盖了文件。
      final canvasPath = p.join(first.workspaceDir!, '画布1.json');
      final decoded = jsonDecode(File(canvasPath).readAsStringSync())
          as Map<String, dynamic>;
      decoded['handEdited'] = true;
      File(canvasPath).writeAsStringSync(jsonEncode(decoded));

      final second = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      expect(second.ok, isTrue);

      expect(
        bridge.workspaceDirFor(seriesId)
            .listSync(recursive: true)
            .whereType<Directory>()
            .length,
        dirAfterFirst,
        reason: '确定性节点 id 必须让重复导出幂等',
      );
      expect(
        jsonDecode(File(canvasPath).readAsStringSync()) as Map<String, dynamic>,
        isNot(contains('handEdited')),
      );
    });

    test('workspaces/ 不存在时导出前自动创建', () async {
      final root = Directory(p.join(AppPaths.toonflowDataDir.path, 'workspaces'));
      expect(root.existsSync(), isFalse);

      final result = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      expect(result.ok, isTrue, reason: result.error);
      expect(root.existsSync(), isTrue);
    });

    test('剧集不存在时报告失败', () async {
      final result = await bridge.export(seriesId: 'no-such', episodeId: episodeId);
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('目标集不存在时报告失败', () async {
      final result = await bridge.export(seriesId: seriesId, episodeId: 'no-such');
      expect(result.ok, isFalse);
      expect(result.error, contains('目标集'));
    });

    test('不留下 .tmp 残留', () async {
      await bridge.export(seriesId: seriesId, episodeId: episodeId);
      final leftovers = bridge.workspaceDirFor(seriesId)
          .listSync(recursive: true)
          .where((e) => e.path.endsWith('.tmp'));
      expect(leftovers, isEmpty, reason: '原子写必须 rename 走临时文件');
    });
  });

  group('密钥边界', () {
    test('导出后 settings.json 的 mtime 与内容都不变', () async {
      final settings = seedSettingsFile();
      final before = settings.lastModifiedSync();
      final beforeContent = settings.readAsStringSync();

      await Future<void>.delayed(const Duration(milliseconds: 5));
      final result = await bridge.export(seriesId: seriesId, episodeId: episodeId);
      expect(result.ok, isTrue);

      expect(
        settings.lastModifiedSync(),
        before,
        reason: '桥绝不读写 settings.json（spec: 密钥边界）',
      );
      expect(settings.readAsStringSync(), beforeContent);
    });

    test('导回后 settings.json 也不被触碰', () async {
      final settings = seedSettingsFile();
      final before = settings.lastModifiedSync();
      final beforeContent = settings.readAsStringSync();

      // 造一个"Toonflow 新生成的视频"。
      final assets = Directory(p.join(bridge.workspaceDirFor(seriesId).path, 'assets'))
        ..createSync(recursive: true);
      final video = File(p.join(assets.path, 'clip.mp4'))
        ..writeAsStringSync('fake-mp4');

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await bridge.importVideos(
        seriesId: seriesId,
        episodeId: episodeId,
        sourcePaths: <String>[video.path],
      );

      expect(settings.lastModifiedSync(), before);
      expect(settings.readAsStringSync(), beforeContent);
    });

    test('桥写过的文件里不含 settings.json 的内容', () async {
      seedSettingsFile();
      await bridge.export(seriesId: seriesId, episodeId: episodeId);

      final blob = bridge.workspaceDirFor(seriesId)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(blob, isNot(contains('sk-CANARY-DO-NOT-LEAK')));
      expect(blob, isNot(contains('settings.json')));
    });

    test('settings.json 未登记进 AppPaths.allFiles', () {
      // 结构性防线：allFiles 的语义是「本软件生成并管理的文件」。登记它等于
      // 邀请后续代码去碰它（spec: 密钥边界）。
      expect(
        AppPaths.allFiles.any((f) => p.basename(f.path) == 'settings.json'),
        isFalse,
      );
      expect(
        AppPaths.allFiles.any((f) => f.path.contains('toonflow_data')),
        isFalse,
      );
    });
  });

  group('导回', () {
    test('复制而非移动：Toonflow 侧原文件仍在', () async {
      final assets = Directory(p.join(bridge.workspaceDirFor(seriesId).path, 'assets'))
        ..createSync(recursive: true);
      final video = File(p.join(assets.path, 'clip.mp4'))
        ..writeAsStringSync('fake-mp4');

      final result = await bridge.importVideos(
        seriesId: seriesId,
        episodeId: episodeId,
        sourcePaths: <String>[video.path],
      );

      expect(result.ok, isTrue, reason: result.error);
      expect(result.imported, hasLength(1));
      expect(video.existsSync(), isTrue,
          reason: '用户可能仍在 Toonflow 内继续使用该文件');

      final copied = File(
        p.join(manager.episodeSegmentsDir(seriesId, episodeId).path,
            result.imported.single),
      );
      expect(copied.existsSync(), isTrue);
      expect(copied.readAsStringSync(), 'fake-mp4');
    });

    test('目标集不存在时报告失败而不猜测', () async {
      final result = await bridge.importVideos(
        seriesId: seriesId,
        episodeId: 'no-such',
        sourcePaths: const <String>['/tmp/whatever.mp4'],
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('目标集'));
      expect(result.imported, isEmpty);
    });

    test('源文件不存在时跳过而不失败', () async {
      final result = await bridge.importVideos(
        seriesId: seriesId,
        episodeId: episodeId,
        sourcePaths: const <String>['/tmp/definitely-not-here.mp4'],
      );
      expect(result.ok, isTrue, reason: '勾选后文件被挪走不该让整批失败');
      expect(result.imported, isEmpty);
    });

    test('按分镜顺序写回片段，且片段状态推到 done', () async {
      // 造两个片段，让归集有地方可写。
      var episode = manager.readEpisode(seriesId, episodeId)!;
      episode = episode.copyWith(segments: const <StudioSegment>[
        StudioSegment(id: 'seg-1', shotNumbers: <int>[1, 2]),
        StudioSegment(id: 'seg-2', shotNumbers: <int>[3]),
      ]);
      await manager.saveEpisode(episode);

      final assets = Directory(p.join(bridge.workspaceDirFor(seriesId).path, 'assets'))
        ..createSync(recursive: true);
      // scanNewVideos 给的是「新的在前」，写回必须反转成分镜顺序。
      final older = File(p.join(assets.path, 'first.mp4'))
        ..writeAsStringSync('first')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 2)));
      final newer = File(p.join(assets.path, 'second.mp4'))
        ..writeAsStringSync('second')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 1)));

      final result = await bridge.importVideos(
        seriesId: seriesId,
        episodeId: episodeId,
        sourcePaths: <String>[newer.path, older.path],
      );

      expect(result.ok, isTrue, reason: result.error);
      expect(result.assignments, hasLength(2));
      // 顺序填充：先写的那个（mtime 更早）顶 seg-1。
      expect(result.assignments.first.segmentId, 'seg-1');
      expect(result.assignments.first.shotNumbers, <int>[1, 2]);
      expect(result.assignments.last.segmentId, 'seg-2');

      final reloaded = manager.readEpisode(seriesId, episodeId)!;
      expect(reloaded.segments[0].clipPath, result.assignments.first.fileName);
      expect(reloaded.segments[1].clipPath, result.assignments.last.fileName);
      expect(reloaded.segments.every((s) => s.status == SegmentStatus.done),
          isTrue, reason: '有 clipPath 却仍是 pending 会让看板显示矛盾');
      // 原文件仍在（复制而非移动）。
      expect(older.existsSync(), isTrue);
      expect(newer.existsSync(), isTrue);
    });

    test('视频比片段多时，多出的进 unassigned 而不丢弃', () async {
      var episode = manager.readEpisode(seriesId, episodeId)!;
      episode = episode.copyWith(segments: const <StudioSegment>[
        StudioSegment(id: 'seg-1', shotNumbers: <int>[1]),
      ]);
      await manager.saveEpisode(episode);

      final assets = Directory(p.join(bridge.workspaceDirFor(seriesId).path, 'assets'))
        ..createSync(recursive: true);
      final a = File(p.join(assets.path, 'a.mp4'))..writeAsStringSync('a');
      final b = File(p.join(assets.path, 'b.mp4'))..writeAsStringSync('b');

      final result = await bridge.importVideos(
        seriesId: seriesId,
        episodeId: episodeId,
        sourcePaths: <String>[a.path, b.path],
      );

      expect(result.imported, hasLength(2), reason: '文件都复制了');
      expect(result.assignments, hasLength(1));
      expect(result.unassigned, hasLength(1),
          reason: '没片段可写的视频必须报告，不能静默丢');
    });

    test('已有成片的片段不被覆盖', () async {
      var episode = manager.readEpisode(seriesId, episodeId)!;
      episode = episode.copyWith(segments: const <StudioSegment>[
        StudioSegment(
          id: 'seg-1',
          shotNumbers: <int>[1],
          clipPath: 'already.mp4',
          status: SegmentStatus.done,
        ),
        StudioSegment(id: 'seg-2', shotNumbers: <int>[2]),
      ]);
      await manager.saveEpisode(episode);

      final assets = Directory(p.join(bridge.workspaceDirFor(seriesId).path, 'assets'))
        ..createSync(recursive: true);
      final video = File(p.join(assets.path, 'a.mp4'))..writeAsStringSync('a');

      final result = await bridge.importVideos(
        seriesId: seriesId,
        episodeId: episodeId,
        sourcePaths: <String>[video.path],
      );

      expect(result.assignments.single.segmentId, 'seg-2',
          reason: '已确认的成果不能被归集覆盖');
      final reloaded = manager.readEpisode(seriesId, episodeId)!;
      expect(reloaded.segments[0].clipPath, 'already.mp4');
    });

    test('分镜级归集写 clips/ 并回填 shot.clipPath', () async {
      var episode = manager.readEpisode(seriesId, episodeId)!;
      episode = episode.copyWith(shots: const <StudioShot>[
        StudioShot(number: 1, durationSec: 3),
        StudioShot(number: 2, durationSec: 3),
      ]);
      await manager.saveEpisode(episode);

      final assets = Directory(p.join(bridge.workspaceDirFor(seriesId).path, 'assets'))
        ..createSync(recursive: true);
      final video = File(p.join(assets.path, 'a.mp4'))..writeAsStringSync('a');

      final result = await bridge.importVideos(
        seriesId: seriesId,
        episodeId: episodeId,
        sourcePaths: <String>[video.path],
        targetIsSegment: false,
      );

      expect(result.ok, isTrue, reason: result.error);
      expect(result.assignments.single.shotNumbers, <int>[1]);
      final reloaded = manager.readEpisode(seriesId, episodeId)!;
      expect(reloaded.shots[0].clipPath, result.assignments.single.fileName);
      expect(reloaded.shots[1].clipPath, isNull);
    });

    test('scanNewVideos 只列本次导出后新增的视频，按 mtime 倒序', () async {
      await bridge.export(seriesId: seriesId, episodeId: episodeId);
      final assets = Directory(p.join(bridge.workspaceDirFor(seriesId).path, 'assets'))
        ..createSync(recursive: true);

      // 旧文件：导出前的时间戳。
      final old = File(p.join(assets.path, 'old.mp4'))
        ..writeAsStringSync('old')
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 1)),
        );

      // 非视频文件：不该被列出。
      File(p.join(assets.path, 'notes.txt')).writeAsStringSync('nope');

      final newer = File(p.join(assets.path, 'newer.mp4'))
        ..writeAsStringSync('newer')
        ..setLastModifiedSync(
          DateTime.now().add(const Duration(seconds: 2)),
        );

      final scan = await bridge.scanNewVideos(
        seriesId: seriesId,
        since: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(scan, hasLength(1));
      expect(p.basename(scan.single), 'newer.mp4');
      expect(old.existsSync(), isTrue);
      expect(newer.existsSync(), isTrue);
    });

    test('workspaces 不存在时 scanNewVideos 返回空而不抛', () async {
      final scan = await bridge.scanNewVideos(seriesId: seriesId);
      expect(scan, isEmpty);
    });
  });
}
