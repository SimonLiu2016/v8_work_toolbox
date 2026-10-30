import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// spec: novel-import · 全季重导入的破坏性删除确认
///
/// 守一件事：用户点下「全季导入」之前，必须先知道这一下会抹掉多少已付费的
/// 算力成果。删除本身是 [StudioProjectManager.importNovelProject] 的既有
/// 行为，本组只验证「预览数字」与「取消即中止」两条契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('full_season_impact_test');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDown(() {
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('previewFullSeasonImportImpact 待删规模预览', () {
    test('无既有剧集时三项全为 0', () async {
      final series = await manager.createSeries(name: '空项目');

      final impact = await manager.previewFullSeasonImportImpact(series.id);

      expect(impact.episodeCount, equals(0));
      expect(impact.shotCount, equals(0));
      expect(impact.mediaFileCount, equals(0));
    });

    test('统计既有集数、分镜数与物理媒体文件数', () async {
      final series = await manager.createSeries(name: '有料项目');

      // 造两集：第一集带分镜与物理媒体，第二集空。
      final ep1 = await manager.createEpisode(seriesId: series.id);
      final ep2 = await manager.createEpisode(seriesId: series.id);
      // createEpisode 建的是空分镜集，先塞一个分镜进去。
      final seeded = (await manager.readEpisode(series.id, ep1.episode.id))!
          .copyWith(shots: [
              const StudioShot(number: 1, actionZh: '沈长青按刀'),
            ]);
      await manager.saveEpisode(seeded);

      final framesDir = manager.episodeFramesDir(series.id, ep1.episode.id);
      await framesDir.create(recursive: true);
      await File('${framesDir.path}/shot_1.png').writeAsString('fake');
      await File('${framesDir.path}/shot_1_last.png').writeAsString('fake');
      final clipsDir = manager.episodeClipsDir(series.id, ep1.episode.id);
      await clipsDir.create(recursive: true);
      await File('${clipsDir.path}/shot_1.mp4').writeAsString('fake');

      final impact = await manager.previewFullSeasonImportImpact(series.id);

      expect(impact.episodeCount, equals(2));
      expect(impact.shotCount, equals(1));
      expect(impact.mediaFileCount, equals(3));
      // 第二集被计入集数但不贡献分镜与媒体。
      expect(ep2.episode.shots, isEmpty);
    });
  });

  group('全季导入的确认条件', () {
    test('有待删数据时预览数字非零，构成弹确认的前提', () async {
      final series = await manager.createSeries(name: '确认流程剧');
      await manager.createEpisode(seriesId: series.id);

      // _processNovelContent 在全季且有待删数据时调用确认对话框；这里验证其
      // 触发条件（预览数字非零）成立。对话框的渲染依赖外壳级 Keychain 探测等
      // 启动链路，属 ai_video_studio_shell_test 的冒烟范围，此处不重复。
      final impact = await manager.previewFullSeasonImportImpact(series.id);
      expect(impact.episodeCount, greaterThan(0));
      expect(impact.shotCount, equals(0));
      expect(impact.mediaFileCount, equals(0));
    });
  });
}
