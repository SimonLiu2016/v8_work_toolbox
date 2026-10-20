import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/asset_library.dart';

/// 资产库的存储、复制语义与来源关联回归。
///
/// 这个文件守的核心性质是「资产独立于原剧存在」：复制而非移动、卡片持有
/// 副本而非引用。任一条被破坏，用户清理剧集或资产时就会以怪病形式丢文件。
void main() {
  group('AssetLibrary', () {
    late Directory tempDir;
    late Directory sourceDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('asset_lib_test');
      AppPaths.overrideRootForTesting(tempDir);
      AssetLibrary.instance.resetForTesting();
      sourceDir = Directory(p.join(tempDir.path, 'src'))..createSync(recursive: true);
    });

    tearDown(() {
      AssetLibrary.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<File> makeSource(String name, int bytes) async {
      final f = File(p.join(sourceDir.path, name));
      await f.writeAsBytes(List<int>.filled(bytes, 7));
      return f;
    }

    test('addAsset 是复制——原文件仍在原位', () async {
      final src = await makeSource('shot_3.png', 4096);
      await AssetLibrary.instance.addAsset(
        src,
        kind: AssetKind.image,
        providerId: 'agnes',
        model: 'agnes-image-2.5-flash',
        prompt: '雨夜天台，少女回眸',
        originPath: 'series_library/s1/episodes/e1/frames/shot_3.png',
      );

      expect(await src.exists(), isTrue,
          reason: '入库是复制，原剧集目录里的文件必须还在');
      final assets = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(assets, hasLength(1));
      expect(await assets.first.file.exists(), isTrue);
      expect(assets.first.sizeBytes, 4096);
      expect(assets.first.prompt, '雨夜天台，少女回眸');
      expect(assets.first.providerId, 'agnes');
      expect(assets.first.source, AssetSource.remote);
    });

    test('资产 ID 是 8 位十六进制，文件名即 ID', () async {
      final src = await makeSource('a.png', 100);
      final asset = await AssetLibrary.instance.addAsset(src, kind: AssetKind.image);
      expect(asset.id, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(asset.path, endsWith('${asset.id}.png'));
    });

    test('视频资产落 clips 目录且扩展名为 mp4', () async {
      final src = await makeSource('seg.mp4', 2048);
      final asset = await AssetLibrary.instance.addAsset(src, kind: AssetKind.clip);
      expect(asset.path, contains(p.join('assets', 'clips')));
      expect(asset.path, endsWith('.mp4'));
    });

    test('索引跨重启读回，资产文件仍在', () async {
      final src = await makeSource('b.png', 2048);
      final asset = await AssetLibrary.instance.addAsset(
        src,
        kind: AssetKind.image,
        sourceCallId: 'call_xyz',
      );

      // 模拟重启：清内存但不动磁盘。
      AssetLibrary.instance.resetForTesting();
      final found = await AssetLibrary.instance.findById(asset.id);
      expect(found, isNotNull);
      expect(found!.sourceCallId, 'call_xyz');
      expect(await found.file.exists(), isTrue);
    });

    test('损坏索引降级为空库，不抛异常，且仍可写入', () async {
      final dir = AppPaths.videoStudioAssetImagesDir.parent;
      await dir.create(recursive: true);
      await AppPaths.videoStudioAssetIndexFile.writeAsString('{ broken');
      AssetLibrary.instance.resetForTesting();

      final all = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(all, isEmpty);

      final src = await makeSource('c.png', 512);
      final asset = await AssetLibrary.instance.addAsset(src, kind: AssetKind.image);
      AssetLibrary.instance.resetForTesting();
      final after = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(after, hasLength(1));
      expect(after.first.id, asset.id);
    });

    test('removeAsset 删文件与索引条目', () async {
      final src = await makeSource('d.png', 1024);
      final asset = await AssetLibrary.instance.addAsset(src, kind: AssetKind.image);
      expect(await asset.file.exists(), isTrue);

      await AssetLibrary.instance.removeAsset(asset.id);
      expect(await asset.file.exists(), isFalse);
      expect(await AssetLibrary.instance.findById(asset.id), isNull);
    });

    test('assetsFromCall 按来源调用反查', () async {
      final a = await makeSource('e1.png', 100);
      final b = await makeSource('e2.png', 100);
      await AssetLibrary.instance.addAsset(a, kind: AssetKind.image, sourceCallId: 'call_1');
      await AssetLibrary.instance.addAsset(b, kind: AssetKind.image, sourceCallId: 'call_2');

      final fromOne = await AssetLibrary.instance.assetsFromCall('call_1');
      expect(fromOne, hasLength(1));
      expect(fromOne.first.sourceCallId, 'call_1');
    });

    test('要入库的文件不存在时明确报错', () async {
      final missing = File(p.join(sourceDir.path, 'nope.png'));
      await expectLater(
        AssetLibrary.instance.addAsset(missing, kind: AssetKind.image),
        throwsA(isA<StateError>()),
      );
    });

    test('视频资产记时长，跨重启后仍在', () async {
      final src = await makeSource('seg.mp4', 4096);
      final asset = await AssetLibrary.instance.addAsset(
        src,
        kind: AssetKind.clip,
        durationSec: 12,
      );
      expect(asset.durationSec, 12);

      AssetLibrary.instance.resetForTesting();
      final back = await AssetLibrary.instance.findById(asset.id);
      expect(back!.durationSec, 12,
          reason: '时长丢了两条展开路径的总时长会对不上');
    });

    test('图片资产的时长为 null', () async {
      final src = await makeSource('img.png', 2048);
      final asset = await AssetLibrary.instance.addAsset(src, kind: AssetKind.image);
      expect(asset.durationSec, isNull);
    });

    test('assetSync 只读内存，不触发加载', () async {
      final src = await makeSource('sync.png', 512);
      final asset = await AssetLibrary.instance.addAsset(src, kind: AssetKind.image);
      // 清内存但不动磁盘：此时同步查不到，异步查得到。
      AssetLibrary.instance.resetForTesting();
      expect(AssetLibrary.instance.assetSync(asset.id), isNull);
      final async = await AssetLibrary.instance.findById(asset.id);
      expect(async, isNotNull);
      expect(AssetLibrary.instance.assetSync(asset.id), isNotNull,
          reason: '异步加载后同步读应能命中');
    });

    test('资产目录已登记进 allDirs，索引文件已登记进 allFiles', () {
      expect(
        AppPaths.allDirs.any((d) => d.path == AppPaths.videoStudioAssetImagesDir.path),
        isTrue,
      );
      expect(
        AppPaths.allDirs.any((d) => d.path == AppPaths.videoStudioAssetClipsDir.path),
        isTrue,
      );
      expect(
        AppPaths.allFiles.any((f) => f.path == AppPaths.videoStudioAssetIndexFile.path),
        isTrue,
      );
    });

    test('并发入库不丢条目', () async {
      final futures = <Future<void>>[];
      for (var i = 0; i < 10; i++) {
        final f = await makeSource('cc_$i.png', 256);
        futures.add(
          AssetLibrary.instance
              .addAsset(f, kind: AssetKind.image)
              .then((_) {}),
        );
      }
      await Future.wait(futures);

      AssetLibrary.instance.resetForTesting();
      final all = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(all, hasLength(10), reason: '串行化写盘必须让每条都留下');
    });

    test('外部子窗口修改索引后，主进程自动按时间戳重载', () async {
      final f1 = await makeSource('first.png', 100);
      await AssetLibrary.instance.addAsset(f1, kind: AssetKind.image);
      final initial = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(initial, hasLength(1));

      // 模拟外部独立子窗口（如 Agnes 试炼场）：直接向磁盘 index.json 追加一条并更新时间戳
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final indexFile = AppPaths.videoStudioAssetIndexFile;
      final text = await indexFile.readAsString();
      final list = jsonDecode(text) as List;
      list.add({
        'id': 'ext12345',
        'kind': 'image',
        'source': 'remote',
        'sizeBytes': 2048,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'category': 'other',
        'tags': ['试炼场'],
      });
      await indexFile.writeAsString(jsonEncode(list), flush: true);

      // 主进程再次读取：无需 resetForTesting，ensureLoaded 应当感知时间戳变动自动重载
      final after = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(after, hasLength(2), reason: '时间戳更新后自动重载应能看到外部子窗口写入的新资产');
      expect(after.any((a) => a.id == 'ext12345'), isTrue);
    });

    test('reload() 强制重载磁盘资产', () async {
      final f1 = await makeSource('r1.png', 100);
      await AssetLibrary.instance.addAsset(f1, kind: AssetKind.image);
      expect(await AssetLibrary.instance.assetsOf(AssetKind.image), hasLength(1));

      // 外部修改
      final indexFile = AppPaths.videoStudioAssetIndexFile;
      final text = await indexFile.readAsString();
      final list = jsonDecode(text) as List;
      list.add({
        'id': 'rld99999',
        'kind': 'image',
        'source': 'remote',
        'sizeBytes': 1024,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'category': 'other',
        'tags': const [],
      });
      await indexFile.writeAsString(jsonEncode(list), flush: true);

      // 显式 reload
      await AssetLibrary.instance.reload();
      final assets = await AssetLibrary.instance.assetsOf(AssetKind.image);
      expect(assets, hasLength(2));
      expect(assets.any((a) => a.id == 'rld99999'), isTrue);
    });
  });
}

