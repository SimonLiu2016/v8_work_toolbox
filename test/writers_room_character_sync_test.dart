import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('writers_room_sync_test');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('编剧研讨室角色沉淀至 IP 资产库契约测试', () {
    test('增量同步：新角色规范落盘，已有角色保护原有视觉资产与声音', () async {
      // 1. 创建剧集
      final series = await manager.createSeries(
        name: '凡人短剧版',
        productionType: StudioProductionType.drama,
        worldview: '仙凡两隔，弱肉强食',
      );

      // 2. 事先手动录入韩立，并设置已有参考图与脸模
      final existingHanLi = CharacterCard(
        id: 'char_existing_hanli',
        name: '韩立',
        descriptionZh: '原有简要描述',
        facialFeaturesZh: '原有容貌特征',
        basePromptPositive: 'existing positive prompt',
        referenceImages: const ['ref1.png', 'ref2.png'],
        faceAnchorPath: 'face_anchor.png',
        ttsVoiceId: 'voice_hanli_01',
        variations: const [
          CharacterVariation(id: 'var_1', name: '默认', active: true),
        ],
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, existingHanLi);

      // 3. 研讨室提炼出的角色列表
      final extractedCharacters = [
        {
          'name': '韩立',
          'role': '主角',
          'personality': '隐忍低调、心狠手辣但有底线',
          'appearance_features': '肤色黝黑朴素，粗布麻衣 (dark skinned youth, plain robe)',
          'motivation': '求生求长生',
        },
        {
          'name': '墨大夫',
          'role': '核心反派',
          'personality': '阴鸷伪善、机关算尽',
          'appearance_features': '白发苍苍，形容枯槁，身着灰黑药师袍 (withered old man, grey robe)',
          'motivation': '夺舍续命，重回修仙界',
        },
      ];

      // 4. 执行模拟同步逻辑（与 WritersRoomDialog 内部同步契约保持一致）
      final existingChars = await manager.listCharacters(series.id);
      final existingByName = <String, CharacterCard>{
        for (final c in existingChars) c.name.trim().toLowerCase(): c,
      };

      for (final raw in extractedCharacters) {
        final name = (raw['name'] as String? ?? '').trim();
        final role = (raw['role'] as String? ?? '').trim();
        final personality = (raw['personality'] as String? ?? '').trim();
        final appearance = (raw['appearance_features'] as String? ?? '').trim();
        final motivation = (raw['motivation'] as String? ?? '').trim();

        final descZh = StringBuffer();
        if (role.isNotEmpty) descZh.writeln('【定位】$role');
        if (personality.isNotEmpty) descZh.writeln('【性格】$personality');
        if (appearance.isNotEmpty) descZh.writeln('【外貌体态】$appearance');
        if (motivation.isNotEmpty) descZh.writeln('【核心动机】$motivation');

        final key = name.toLowerCase();
        final existing = existingByName[key];
        if (existing != null) {
          // 保护已有参考图、脸模和音色
          final updated = existing.copyWith(
            descriptionZh: existing.descriptionZh.isEmpty ? descZh.toString().trim() : existing.descriptionZh,
            facialFeaturesZh: existing.facialFeaturesZh.isEmpty ? appearance : existing.facialFeaturesZh,
            basePromptPositive: existing.basePromptPositive.isEmpty ? appearance : existing.basePromptPositive,
            updatedAt: DateTime.now(),
          );
          await manager.saveCharacter(series.id, updated);
        } else {
          final now = DateTime.now();
          final newCard = CharacterCard(
            id: 'char_${now.millisecondsSinceEpoch}_new',
            name: name,
            descriptionZh: descZh.toString().trim(),
            facialFeaturesZh: appearance,
            basePromptPositive: appearance,
            variations: [
              CharacterVariation(
                id: 'var_${now.millisecondsSinceEpoch}',
                name: '默认',
                active: true,
              ),
            ],
            updatedAt: now,
          );
          await manager.saveCharacter(series.id, newCard);
        }
      }

      // 5. 验证持久化结果
      final finalChars = await manager.listCharacters(series.id);
      expect(finalChars.length, 2);

      final hanli = finalChars.firstWhere((c) => c.name == '韩立');
      expect(hanli.id, 'char_existing_hanli', reason: '复用已有角色 ID');
      expect(hanli.referenceImages, ['ref1.png', 'ref2.png'], reason: '严格保护已有参考图');
      expect(hanli.faceAnchorPath, 'face_anchor.png', reason: '严格保护已有脸模');
      expect(hanli.ttsVoiceId, 'voice_hanli_01', reason: '严格保护已有 TTS 音色');
      expect(hanli.descriptionZh, '原有简要描述');

      final mo = finalChars.firstWhere((c) => c.name == '墨大夫');
      expect(mo.name, '墨大夫');
      expect(mo.descriptionZh, contains('核心反派'));
      expect(mo.descriptionZh, contains('阴鸷伪善'));
      expect(mo.facialFeaturesZh, contains('白发苍苍'));
      expect(mo.variations.length, 1);
      expect(mo.variations.first.name, '默认');
    });
  });
}
