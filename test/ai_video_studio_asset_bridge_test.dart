import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_asset_bridge.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// 视频下载器 → 工坊素材搬运的测试（spec 16.1 / 16.2 + video-downloader delta）。
///
/// 三条硬约定：
/// 1. 没有活跃项目时不该显示快捷选项；
/// 2. 复制到当前集 `frames/`，**原文件留在原处**；
/// 3. 复制失败不该把「下载已完成」翻成「失败」。
void main() {
  late Directory root;
  late StudioProjectManager manager;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('studio_asset');
    AppPaths.overrideRootForTesting(root);
  });

  setUp(() {
    manager = StudioProjectManager.instance;
    manager.resetCachesForTesting();
    StudioActiveProjectStore.instance.clearActive();
  });

  group('快捷选项的显隐', () {
    test('没有活跃剧集时 label 为空串', () {
      expect(StudioActiveProjectStore.instance.hasActiveProject, isFalse);
      expect(StudioActiveProjectStore.instance.shortcutLabel, '');
    });

    test('有活跃剧集时 label 带上剧名', () async {
      final series = await manager.createSeries(name: '雨夜回声');
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
      );
      expect(
        StudioActiveProjectStore.instance.shortcutLabel,
        '保存至《雨夜回声》素材目录',
      );
    });

    test('clearActive 后选项消失', () async {
      final series = await manager.createSeries(name: '晴日');
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
      );
      StudioActiveProjectStore.instance.clearActive();
      expect(StudioActiveProjectStore.instance.shortcutLabel, '');
    });
  });

  group('复制到 frames/', () {
    test('复制到当前集的 frames/ 且原文件不动', () async {
      final series = await manager.createSeries(name: '雨夜');
      final created = await manager.createEpisode(seriesId: series.id);
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
        episodeId: created.episode.id,
      );

      final downloadDir = Directory.systemTemp.createTempSync('downloads');
      final source = File(p.join(downloadDir.path, 'clip.mp4'));
      source.writeAsStringSync('video-bytes');

      final result = await StudioAssetImporter.importDownloadedFile(
        downloadedFilePath: source.path,
      );

      expect(result.ok, isTrue);
      // 目标落在该集的 frames/
      final expectedDir = manager
          .episodeFramesDir(series.id, created.episode.id)
          .path;
      expect(result.targetPath!.startsWith(expectedDir), isTrue);
      expect(p.basename(result.targetPath!), startsWith('clip_'));
      expect(p.extension(result.targetPath!), '.mp4');
      expect(await File(result.targetPath!).exists(), isTrue);
      // 原文件仍在原处，内容不变
      expect(await source.exists(), isTrue);
      expect(await source.readAsString(), 'video-bytes');
      expect(await source.length(), await File(result.targetPath!).length());

      downloadDir.deleteSync(recursive: true);
    });

    test('同名素材不会互相覆盖', () async {
      final series = await manager.createSeries(name: '雨夜');
      final created = await manager.createEpisode(seriesId: series.id);
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
        episodeId: created.episode.id,
      );
      final downloadDir = Directory.systemTemp.createTempSync('downloads2');

      final targets = <String>[];
      for (var i = 0; i < 3; i++) {
        final source = File(p.join(downloadDir.path, 'same.mp4'));
        source.writeAsStringSync('bytes-$i');
        final result = await StudioAssetImporter.importDownloadedFile(
          downloadedFilePath: source.path,
        );
        targets.add(result.targetPath!);
      }
      expect(targets.toSet(), hasLength(3),
             reason: '同名的多次下载都该留下，时间戳让它们不冲突');

      downloadDir.deleteSync(recursive: true);
    });

    test('没选中集时落到该剧第一集', () async {
      final series = await manager.createSeries(name: '雨夜');
      final created = await manager.createEpisode(seriesId: series.id);
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
        // episodeId 缺省
      );
      final downloadDir = Directory.systemTemp.createTempSync('downloads3');
      final source = File(p.join(downloadDir.path, 'x.mp4'));
      source.writeAsStringSync('x');

      final result = await StudioAssetImporter.importDownloadedFile(
        downloadedFilePath: source.path,
      );
      expect(result.ok, isTrue);
      expect(
        result.targetPath!
            .startsWith(manager.episodeFramesDir(series.id, created.episode.id).path),
        isTrue,
      );
      downloadDir.deleteSync(recursive: true);
    });

    test('该剧一集都没有时给出可操作的错误', () async {
      final series = await manager.createSeries(name: '空剧');
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
      );
      final downloadDir = Directory.systemTemp.createTempSync('downloads4');
      final source = File(p.join(downloadDir.path, 'x.mp4'));
      source.writeAsStringSync('x');

      final result = await StudioAssetImporter.importDownloadedFile(
        downloadedFilePath: source.path,
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('还没有集'));
      // 原文件仍然在：失败的搬运不该带走用户的东西。
      expect(await source.exists(), isTrue);
      downloadDir.deleteSync(recursive: true);
    });
  });

  group('失败路径', () {
    test('没有活跃项目时拒绝并说明原因', () async {
      final result = await StudioAssetImporter.importDownloadedFile(
        downloadedFilePath: '/nonexistent.mp4',
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('没有活跃'));
    });

    test('源文件不存在时不造出空文件', () async {
      final series = await manager.createSeries(name: '雨夜');
      final created = await manager.createEpisode(seriesId: series.id);
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
        episodeId: created.episode.id,
      );

      final result = await StudioAssetImporter.importDownloadedFile(
        downloadedFilePath: '/tmp/definitely-not-here-${DateTime.now()}.mp4',
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('不存在'));

      final framesDir = manager.episodeFramesDir(series.id, created.episode.id);
      expect(framesDir.listSync(), isEmpty,
             reason: '复制失败不该在 frames/ 里留下半截文件');
    });

    test('剧集项目已删时给出明确错误', () async {
      final series = await manager.createSeries(name: '将删');
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
      );
      await manager.deleteSeries(series.id);

      final source = File('${Directory.systemTemp.createTempSync("d5").path}/a.mp4');
      source.writeAsStringSync('a');
      final result = await StudioAssetImporter.importDownloadedFile(
        downloadedFilePath: source.path,
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('不存在'));
    });
  });

  group('辅助显示', () {
    test('previewTargetDir 在没选中集时返回 null', () async {
      final series = await manager.createSeries(name: '雨夜');
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
      );
      expect(await StudioAssetImporter.previewTargetDir(), isNull);
    });

    test('previewTargetDir 返回该集 frames/ 的绝对路径', () async {
      final series = await manager.createSeries(name: '雨夜');
      final created = await manager.createEpisode(seriesId: series.id);
      StudioActiveProjectStore.instance.setActive(
        seriesId: series.id,
        seriesName: series.name,
        episodeId: created.episode.id,
      );
      final preview = await StudioAssetImporter.previewTargetDir();
      expect(preview, manager.episodeFramesDir(series.id, created.episode.id).path);
    });

    test('类型 id → 中文标签', () {
      expect(studioProductionTypeLabel('drama'), '真人剧情短剧');
      expect(studioProductionTypeLabel('anime'), '二次元 / 动态漫');
      expect(studioProductionTypeLabel('narration'), '图文解说 / 知识故事');
      // 未知 id 落到默认类型而不是抛
      expect(studioProductionTypeLabel('nope'), '真人剧情短剧');
    });
  });
}
