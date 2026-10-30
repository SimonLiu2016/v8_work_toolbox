import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('外部三视图导入与道具主图排序测试', () {
    late Directory tempRoot;
    final manager = StudioProjectManager.instance;
    late String seriesId;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('turnaround_prop_test_');
      AppPaths.overrideRootForTesting(tempRoot);
      manager.resetCachesForTesting();
      final created = await manager.createSeries(name: '测试剧集');
      seriesId = created.id;
    });

    tearDown(() {
      AppPaths.resetForTesting();
      manager.resetCachesForTesting();
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('角色三视图文件落盘至 turnaround.png 并可被正确识别', () async {
      final charDir = manager.characterDir(seriesId, 'char_001');
      await charDir.create(recursive: true);

      // 创建一个模拟的外部三视图文件
      final externalFile = File(p.join(tempRoot.path, 'my_external_turnaround.png'));
      await externalFile.writeAsString('fake png content for turnaround');

      // 模拟外部三视图导入操作：复制为 turnaround.png
      final target = File(p.join(charDir.path, 'turnaround.png'));
      await externalFile.copy(target.path);

      expect(target.existsSync(), isTrue);
      expect(await target.readAsString(), equals('fake png content for turnaround'));
    });

    test('角色形态三视图落盘至 turnaround_var_<id>.png 并更新 CharacterVariation', () async {
      final charDir = manager.characterDir(seriesId, 'char_001');
      await charDir.create(recursive: true);

      final externalFile = File(p.join(tempRoot.path, 'my_external_var_turnaround.png'));
      await externalFile.writeAsString('fake png content for variation turnaround');

      const varId = 'var_battle_01';
      final filename = 'turnaround_var_$varId.png';
      final target = File(p.join(charDir.path, filename));
      await externalFile.copy(target.path);

      var variation = const CharacterVariation(
        id: varId,
        name: '战损形态',
        positiveDelta: '破旧铠甲',
      );
      variation = variation.copyWith(turnaroundPath: filename);

      expect(target.existsSync(), isTrue);
      expect(variation.turnaroundPath, equals('turnaround_var_var_battle_01.png'));
    });

    test('道具从外部导入图片自动置于首位作为首选封面主图', () async {
      final prop = await manager.createProp(
        seriesId: seriesId,
        name: '诛仙剑',
        descriptionZh: '上古神器',
      );

      // 准备两张模拟外部图片
      final extImg1 = File(p.join(tempRoot.path, 'sword_old.png'))..writeAsStringSync('old');
      final extImg2 = File(p.join(tempRoot.path, 'sword_new_main.png'))..writeAsStringSync('new_main');

      // 导入第一张图片
      final rel1 = await manager.addPropReference(
        seriesId: seriesId,
        propId: prop.id,
        sourceFilePath: extImg1.path,
      );
      final propWith1 = prop.copyWith(
        referenceImages: [rel1],
        updatedAt: DateTime.now(),
      );
      await manager.saveProp(seriesId, propWith1);

      expect(propWith1.referenceImages.length, equals(1));
      expect(propWith1.referenceImages.first, equals(rel1));

      // 列表项快捷导入新图片：插入到首位
      final rel2 = await manager.addPropReference(
        seriesId: seriesId,
        propId: prop.id,
        sourceFilePath: extImg2.path,
      );
      final updatedRefs = [rel2, ...propWith1.referenceImages.where((r) => r != rel2)];
      final propWithNewMain = propWith1.copyWith(
        referenceImages: updatedRefs,
        updatedAt: DateTime.now(),
      );
      await manager.saveProp(seriesId, propWithNewMain);

      // 验证读取出来的道具中，最新导入的图片处于首位（即封面主图）
      final reloaded = manager.readProp(seriesId, prop.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.referenceImages.length, equals(2));
      expect(reloaded.referenceImages.first, equals(rel2));
      expect(reloaded.referenceImages[1], equals(rel1));
    });
  });
}
