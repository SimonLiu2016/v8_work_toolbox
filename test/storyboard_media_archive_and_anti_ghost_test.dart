import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  group('分镜清空媒体归档与防幽灵自愈重连测试', () {
    late Directory tempDir;
    late StudioProjectManager manager;
    const seriesId = 'test_series_001';
    const episodeId = 'ep_001';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('v8_studio_test_');
      AppPaths.overrideRootForTesting(tempDir);
      manager = StudioProjectManager.instance;
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('1. archiveEpisodeMedia 能将当前集的 clips 与 frames 文件安全移动至 archive 目录', () async {
      // 1. 初始化剧集目录结构
      final clipsDir = manager.episodeClipsDir(seriesId, episodeId);
      final framesDir = manager.episodeFramesDir(seriesId, episodeId);
      await clipsDir.create(recursive: true);
      await framesDir.create(recursive: true);

      // 2. 模拟已生成的成片和关键帧文件
      final dummyClip = File(p.join(clipsDir.path, 'shot_1.mp4'));
      final dummyFrame = File(p.join(framesDir.path, 'shot_1.png'));
      await dummyClip.writeAsBytes(List.filled(2048, 1));
      await dummyFrame.writeAsBytes(List.filled(2048, 2));

      expect(dummyClip.existsSync(), isTrue);
      expect(dummyFrame.existsSync(), isTrue);

      // 3. 执行归档操作
      final count = await manager.archiveEpisodeMedia(seriesId, episodeId);
      expect(count, equals(2));

      // 4. 验证原 clips/ 和 frames/ 目录中的文件已被移除
      expect(dummyClip.existsSync(), isFalse);
      expect(dummyFrame.existsSync(), isFalse);

      // 5. 验证文件已安全移入 archive/ 归档子目录
      final archiveBase = manager.episodeArchiveDir(seriesId, episodeId);
      expect(archiveBase.existsSync(), isTrue);
      final archiveEntries = archiveBase.listSync();
      expect(archiveEntries.isNotEmpty, isTrue);

      final archivedSubDir = archiveEntries.first as Directory;
      final archivedClip = File(p.join(archivedSubDir.path, 'clips', 'shot_1.mp4'));
      final archivedFrame = File(p.join(archivedSubDir.path, 'frames', 'shot_1.png'));
      expect(archivedClip.existsSync(), isTrue);
      expect(archivedFrame.existsSync(), isTrue);
    });

    test('2. _healEpisodeMediaIfNeeded 防幽灵自愈：历史旧物理文件不会自动挂载给全新分镜', () async {
      // 1. 保存一个初始剧集（分镜尚未生成任何视频）
      final now = DateTime.now();
      final episode = StudioEpisode(
        id: episodeId,
        seriesId: seriesId,
        index: 1,
        title: '第一回',
        shots: const [
          StudioShot(
            number: 1,
            actionZh: '崭新分镜动作描写',
            dialogue: '崭新台词',
            status: ShotGenerationStatus.pending, // 初始未出片状态
            clipPath: null,
            framePath: null,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await manager.saveEpisode(episode);

      // 2. 模拟磁盘上遗留了一个物理文件 shot_1.mp4，但其修改时间早于本集更新时间（历史残留资产）
      final clipsDir = manager.episodeClipsDir(seriesId, episodeId);
      await clipsDir.create(recursive: true);
      final legacyClip = File(p.join(clipsDir.path, 'shot_1.mp4'));
      await legacyClip.writeAsBytes(List.filled(2048, 0));
      // 将文件修改时间调整为 10 秒前
      await legacyClip.setLastModified(now.subtract(const Duration(seconds: 10)));

      // 3. 读取剧集（内部会触发自愈检查）
      final loaded = manager.readEpisode(seriesId, episodeId);
      expect(loaded, isNotNull);

      // 4. 关键验证：分镜 #1 不得因为磁盘恰好有 shot_1.mp4 就被盲目挂载为已完成状态
      final shot1 = loaded!.shots.first;
      expect(shot1.clipPath, isNull);
      expect(shot1.status, equals(ShotGenerationStatus.pending));
    });
  });
}
