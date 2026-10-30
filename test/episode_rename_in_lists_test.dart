import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/studio_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StudioProjectManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_ep_rename_test_');
    AppPaths.overrideRootForTesting(tempDir);
    manager = StudioProjectManager.instance;
    await manager.ensureBaseStructure();
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('分集名称修改与记忆同步 (allow-episode-title-rename-in-lists)', () {
    test('修改分集名称持久化并同步更新 EpisodeMemory', () async {
      // 1. 创建剧集与初始分集
      final series = await manager.createSeries(name: '科幻编年史');
      final created = await manager.createEpisode(seriesId: series.id, title: '初启星途');
      final ep = created.episode;
      expect(ep.title, '初启星途');

      // 2. 修改分集名称
      const updatedTitle = '深空折跃：第一章';
      final updatedEp = ep.copyWith(title: updatedTitle);
      await manager.saveEpisode(updatedEp);

      // 同步记忆库
      await manager.upsertEpisodeMemory(
        seriesId: series.id,
        episodeId: ep.id,
        title: updatedTitle,
      );

      // 3. 验证从磁盘读取分集标题已更新
      final readEp = manager.readEpisode(series.id, ep.id);
      expect(readEp, isNotNull);
      expect(readEp!.title, updatedTitle);

      // 4. 验证剧集记忆中的分集标题已同步
      final readSeries = manager.readSeries(series.id);
      expect(readSeries, isNotNull);
      final mem = readSeries!.memories.firstWhere((m) => m.episodeId == ep.id);
      expect(mem.title, updatedTitle);
    });

    test('StudioSession.updateEpisode 就地更新分集并通知监听器', () async {
      final session = StudioSession();
      final series = await manager.createSeries(name: '悬疑追踪');
      final created = await manager.createEpisode(seriesId: series.id, title: '雨夜追踪');
      final ep = created.episode;

      session.select(series);
      session.selectEpisode(ep);
      expect(session.episode?.title, '雨夜追踪');

      var notified = false;
      session.addListener(() {
        notified = true;
      });

      const renamedTitle = '暴风雨前的宁静';
      final updatedEp = ep.copyWith(title: renamedTitle);
      session.updateEpisode(updatedEp);

      expect(notified, isTrue);
      expect(session.episode?.title, renamedTitle);
      expect(session.episode?.id, ep.id);
    });
  });
}
