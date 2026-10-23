import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// spec: shot-production · 清空本集分镜时归档物理媒体（第 9 组）
void main() {
  group('archiveEpisodeMedia', () {
    late Directory tempDir;
    late StudioProjectManager manager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('clear_archive_test');
      AppPaths.overrideRootForTesting(tempDir);
      manager = StudioProjectManager.instance;
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    /// 在某集的生产目录里造文件。
    File makeEpisodeFile(String sub, String name) {
      final dir = Directory(p.join(
        manager.episodeDir('s1', 'e1').path, sub));
      dir.createSync(recursive: true);
      final f = File(p.join(dir.path, name));
      f.writeAsStringSync('x');
      return f;
    }

    test('clips/frames/segments/audio 的文件都被移入归档目录', () async {
      makeEpisodeFile('clips', 'shot_1.mp4');
      makeEpisodeFile('frames', 'shot_1.png');
      makeEpisodeFile('segments', 'seg-1.mp4');
      makeEpisodeFile('audio', 'shot_1.m4a');
      makeEpisodeFile('audio', 'ep_e1.srt');

      final count = await manager.archiveEpisodeMedia('s1', 'e1');

      expect(count, 5, reason: '五个文件都应被归档');

      for (final sub in ['clips', 'frames', 'segments', 'audio']) {
        final dir = Directory(p.join(manager.episodeDir('s1', 'e1').path, sub));
        final leftovers = dir.existsSync()
            ? dir.listSync().whereType<File>().toList()
            : <File>[];
        expect(leftovers, isEmpty, reason: '$sub 不该有残留文件');
      }

      // 归档目录里应有这些文件。
      final archiveRoot = Directory(p.join(
        manager.episodeDir('s1', 'e1').path, 'archive'));
      expect(archiveRoot.existsSync(), isTrue);
      final archived = archiveRoot
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toSet();
      expect(archived, containsAll(['shot_1.mp4', 'shot_1.png', 'seg-1.mp4', 'shot_1.m4a', 'ep_e1.srt']));
    });

    test('exports 的文件保持原位', () async {
      final exportFile = makeEpisodeFile('exports', 'episode.mp4');

      await manager.archiveEpisodeMedia('s1', 'e1');

      expect(exportFile.existsSync(), isTrue,
          reason: '成片是交付物，不该被归档');
    });

    test('目录不存在时返回 0 而不抛异常', () async {
      final count = await manager.archiveEpisodeMedia('s1', 'no-such-ep');
      expect(count, 0);
    });

    test('没有媒体文件时返回 0', () async {
      Directory(manager.episodeDir('s1', 'e1').path).createSync(recursive: true);
      final count = await manager.archiveEpisodeMedia('s1', 'e1');
      expect(count, 0);
    });
  });
}
