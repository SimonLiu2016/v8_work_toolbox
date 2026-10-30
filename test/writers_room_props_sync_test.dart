import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('writers_room_props_sync_test');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('StudioProjectManager.saveProp & 道具沉淀测试', () {
    test('saveProp 在 props 为空时能够成功追加新道具并完成持久化 (Upsert 新增)', () async {
      final series = await manager.createSeries(
        name: '修仙传奇',
        productionType: StudioProductionType.drama,
      );

      expect(series.props, isEmpty);

      final newProp = PropCard(
        id: 'prop_test_01',
        name: '掌天瓶',
        descriptionZh: '【类型】法宝\n【戏剧作用】催熟灵药',
        promptEn: 'small green jade bottle with ancient patterns',
        isKeyProp: true,
        updatedAt: DateTime.now(),
      );

      await manager.saveProp(series.id, newProp);

      final propsAfter = await manager.listProps(series.id);
      expect(propsAfter.length, 1);
      expect(propsAfter.first.id, 'prop_test_01');
      expect(propsAfter.first.name, '掌天瓶');
      expect(propsAfter.first.isKeyProp, isTrue);

      final diskSeries = manager.readSeries(series.id);
      expect(diskSeries, isNotNull);
      expect(diskSeries!.props.length, 1);
      expect(diskSeries.props.first.name, '掌天瓶');
    });

    test('saveProp 对已存在的道具执行增量更新 (Upsert 更新)', () async {
      final series = await manager.createSeries(
        name: '武侠传奇',
        productionType: StudioProductionType.drama,
      );

      final propA = PropCard(
        id: 'prop_sword_1',
        name: '玄铁重剑',
        descriptionZh: '重剑无锋，大巧不工',
        promptEn: 'heavy black iron sword',
        updatedAt: DateTime.now(),
      );
      await manager.saveProp(series.id, propA);

      final updatedPropA = propA.copyWith(
        descriptionZh: '重剑无锋，大巧不工，四十岁前持之横行天下',
        isKeyProp: true,
        updatedAt: DateTime.now(),
      );
      await manager.saveProp(series.id, updatedPropA);

      final props = await manager.listProps(series.id);
      expect(props.length, 1);
      expect(props.first.descriptionZh, contains('四十岁前持之横行天下'));
      expect(props.first.isKeyProp, isTrue);
    });

    test('模拟编剧研讨室 7 件关键道具一键沉淀闭环', () async {
      final series = await manager.createSeries(
        name: '编剧研讨室道具测试',
        productionType: StudioProductionType.drama,
      );

      final mockKeyProps = [
        {'name': '掌天瓶', 'category': '核心法宝', 'significance': '催熟灵药逆天改命', 'appearance': '墨绿色小药瓶'},
        {'name': '青竹蜂云剑', 'category': '本命飞剑', 'significance': '大后期攻伐至宝', 'appearance': '金雷竹炼制，散发金色雷弧'},
        {'name': '定颜丹', 'category': '丹药', 'significance': '赠予红颜知己容颜永驻', 'appearance': '碧玉圆润丹丸'},
        {'name': '傀儡兽', 'category': '傀儡法宝', 'significance': '千竹教大衍决机关傀儡', 'appearance': '木制白虎机关兽'},
        {'name': '虚天鼎', 'category': '通天灵宝', 'significance': '全书中期乱星海争端引信', 'appearance': '青铜方鼎，刻日月星辰'},
        {'name': '降尘丹', 'category': '结丹辅助', 'significance': '突破假丹期瓶颈', 'appearance': '暗红灵丹'},
        {'name': '噬金虫', 'category': '灵虫', 'significance': '无物不噬护体神虫', 'appearance': '指甲盖大小的金色甲虫'},
      ];

      final existingProps = await manager.listProps(series.id);
      final existingByName = <String, PropCard>{
        for (final p in existingProps) p.name.trim().toLowerCase(): p,
      };

      int count = 0;
      for (final raw in mockKeyProps) {
        final name = (raw['name'] as String? ?? '').trim();
        final category = (raw['category'] as String? ?? '').trim();
        final significance = (raw['significance'] as String? ?? '').trim();
        final appearance = (raw['appearance'] as String? ?? '').trim();

        final descZh = StringBuffer();
        if (category.isNotEmpty) descZh.writeln('【类型】$category');
        if (significance.isNotEmpty) descZh.writeln('【戏剧作用】$significance');
        if (appearance.isNotEmpty) descZh.writeln('【外观特征】$appearance');

        final key = name.toLowerCase();
        final existing = existingByName[key];
        final now = DateTime.now();

        if (existing != null) {
          final updated = existing.copyWith(
            descriptionZh: existing.descriptionZh.isEmpty ? descZh.toString().trim() : existing.descriptionZh,
            promptEn: existing.promptEn.isEmpty ? appearance : existing.promptEn,
            isKeyProp: true,
            updatedAt: now,
          );
          await manager.saveProp(series.id, updated);
          existingByName[key] = updated;
        } else {
          final newCard = PropCard(
            id: 'prop_${now.millisecondsSinceEpoch}_${count + 1}',
            name: name,
            descriptionZh: descZh.toString().trim(),
            promptEn: appearance,
            isKeyProp: true,
            updatedAt: now,
          );
          await manager.saveProp(series.id, newCard);
          existingByName[key] = newCard;
        }
        count++;
      }

      expect(count, 7);

      final propsList = await manager.listProps(series.id);
      expect(propsList.length, 7);
      final names = propsList.map((p) => p.name).toSet();
      expect(names.contains('掌天瓶'), isTrue);
      expect(names.contains('青竹蜂云剑'), isTrue);
      expect(names.contains('虚天鼎'), isTrue);
      expect(names.contains('噬金虫'), isTrue);

      // 验证定稿合并时使用磁盘最新数据不会导致道具丢失
      final currentSeries = manager.readSeries(series.id)!;
      expect(currentSeries.props.length, 7);
      final updatedSeries = currentSeries.copyWith(
        name: '编剧研讨室道具测试 · 第 1 季',
        worldview: '全新宏观大纲世界观',
      );
      await manager.saveSeries(updatedSeries);

      final finalSeries = manager.readSeries(series.id)!;
      expect(finalSeries.props.length, 7);
    });
  });
}
