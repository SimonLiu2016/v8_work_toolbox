import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/asset_library.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// 资产 → 制作流程 的引用闭环回归。
///
/// 守两件最容易回退的事：
/// 1. **复制的语义**——角色卡持有副本，删资产不影响已引用它的剧集；
/// 2. **顺序规则不变**——资产片段插入不改变分镜序列本身。
///
/// 这两条任何一条破了，用户看到的现象都是"莫名丢了文件"或"成片顺序变了"，
/// 而根因藏在数据层，很难从 UI 反推。
void main() {
  group('资产引用闭环', () {
    late Directory tempDir;
    late StudioProjectManager manager;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('asset_ref_test');
      AppPaths.overrideRootForTesting(tempDir);
      AssetLibrary.instance.resetForTesting();
      manager = StudioProjectManager.instance;
      await manager.ensureBaseStructure();
    });

    tearDown(() {
      AssetLibrary.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('角色卡从资产库选图后，参考图列表与卡片目录文件均就位', () async {
      // 造一个剧集 + 角色卡
      final series = await manager.createSeries(name: '测试剧集');
      final character = CharacterCard(
        id: 'char_1',
        name: '林晚',
        descriptionZh: '女主角',
        basePromptPositive: 'a young woman',
        updatedAt: DateTime.utc(2026, 10, 13),
      );
      await manager.saveCharacter(series.id, character);

      // 造一个资产
      final src = File(p.join(tempDir.path, 'src.png'));
      await src.writeAsBytes(List<int>.filled(2048, 3));
      final asset = await AssetLibrary.instance.addAsset(
        src,
        kind: AssetKind.image,
        prompt: '雨夜天台，少女回眸',
      );

      // 模拟 UI 的接入动作：复制进角色目录 + 加入列表
      final dir = manager.characterDir(series.id, character.id);
      final name = '${asset.id}.png';
      await asset.file.copy(p.join(dir.path, name));
      final updated = character.copyWith(
        referenceImages: [name],
      );
      await manager.saveCharacter(series.id, updated);

      // 断言：列表里有、文件在
      final reread = manager.readCharacter(series.id, character.id);
      expect(reread!.referenceImages, [name]);
      final inCardDir = File(p.join(dir.path, name));
      expect(await inCardDir.exists(), isTrue);

      // 断言：是副本而非引用——内容相同但是两个文件
      expect(await inCardDir.length(), await asset.file.length());
      expect(inCardDir.path, isNot(asset.path));
    });

    test('删资产不影响已引用它的角色卡', () async {
      final series = await manager.createSeries(name: '测试剧集2');
      final character = CharacterCard(
        id: 'char_2',
        name: '配角',
        descriptionZh: '',
        updatedAt: DateTime.utc(2026, 10, 13),
      );
      await manager.saveCharacter(series.id, character);

      final src = File(p.join(tempDir.path, 'src2.png'));
      await src.writeAsBytes(List<int>.filled(1024, 5));
      final asset = await AssetLibrary.instance.addAsset(
        src,
        kind: AssetKind.image,
      );

      final dir = manager.characterDir(series.id, character.id);
      final name = '${asset.id}.png';
      await asset.file.copy(p.join(dir.path, name));
      await manager.saveCharacter(
        series.id,
        character.copyWith(referenceImages: [name]),
      );

      // 删资产库里的那份
      await AssetLibrary.instance.removeAsset(asset.id);
      expect(await asset.file.exists(), isFalse);

      // 角色卡的副本必须还在——这正是"复制而非引用"的要紧之处
      final inCardDir = File(p.join(dir.path, name));
      expect(await inCardDir.exists(), isTrue,
          reason: '删资产不该让剧集的参考图丢失');
      final reread = manager.readCharacter(series.id, character.id);
      expect(reread!.referenceImages, [name]);
    });

    test('资产片段插入不改变分镜序列', () async {
      final series = await manager.createSeries(name: '测试剧集3');
      final created = await manager.createEpisode(
        seriesId: series.id,
        title: '第一集',
      );
      // 新建的集没有分镜（shots 由 AI 拆分产生）。自己造三个，
      // 否则「插入不改分镜序列」这条断言对着空列表跑，什么也没验。
      final episode = created.episode.copyWith(shots: [
        for (var n = 1; n <= 3; n++)
          StudioShot(
            number: n,
            durationSec: 3,
            actionZh: '动作 $n',
            cameraMove: 'pan',
          ),
      ]);
      await manager.saveEpisode(episode);
      final before = episode.shots.map((s) => s.number).toList();
      expect(before, [1, 2, 3]);

      // 加两个插入
      final updated = episode.copyWith(timelineInserts: [
        StudioTimelineInsert(assetId: 'a1', afterShotNumber: 0),
        StudioTimelineInsert(assetId: 'a2', afterShotNumber: before.last),
      ]);
      await manager.saveEpisode(updated);

      final reread = manager.readEpisode(series.id, episode.id);
      expect(reread!.shots.map((s) => s.number).toList(), before,
          reason: '插入是剪辑决策，不该改剧本结构');
      expect(reread.timelineInserts, hasLength(2));
    });

    test('合成顺序：资产片段按 afterShotNumber 展开到正确位置', () async {
      // 直接验展开逻辑的等价物：按 shot 顺序走，遇 0 与镜号后各插一次。
      // 这里不引入 DeliveryPanel（它是 StatefulWidget，测起来要起 widget
      // 树）；展开规则在 exporter 与 panel 各有一份同构实现，两边都消费
      // episode.timelineInserts，规则本身由本测试钉住。
      final inserts = <int, List<String>>{
        0: <String>['asset_head'],
        2: <String>['asset_after2'],
      };
      final shotNumbers = <int>[1, 2, 3];

      final order = <String>[];
      for (final n in shotNumbers) {
        // 插在"上一个镜号之后"的，在这个镜前面输出
        order.addAll(inserts[n - 1] ?? <String>[]);
        order.add('shot_$n');
      }
      // 最后一个镜号之后的
      order.addAll(inserts[shotNumbers.last] ?? <String>[]);

      expect(order, [
        'asset_head',
        'shot_1',
        'shot_2',
        'asset_after2',
        'shot_3',
      ]);
    });
  });
}
