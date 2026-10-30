import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/drama_director_contract.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/screenplay_importer.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/storyboard_exporter.dart';

void main() {
  group('StoryboardExporter Tests', () {
    test('exportToMarkdown generates valid GFM table and metadata', () {
      final episode = StudioEpisode(
        id: 'ep_1',
        seriesId: 'series_1',
        index: 1,
        title: '第一集：初逢',
        synopsis: '主角初遇',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        shots: [
          const StudioShot(
            number: 1,
            durationSec: 4.0,
            shotSize: StudioShotSize.closeUp,
            mood: '紧张',
            function: ShotFunction.opening,
            actionZh: '林凡猛然转头，眼神如刀。',
            dialogue: '谁在那边？',
            voiceType: UtteranceVoiceType.dialogue,
            characterIds: ['char_1'],
            propIds: ['prop_1'],
            sceneId: 'scene_1',
            cameraMove: '快速推镜',
            assembledPrompt: 'Lin Fan turns head quickly',
          ),
          const StudioShot(
            number: 2,
            durationSec: 3.5,
            shotSize: StudioShotSize.full,
            mood: '压抑',
            function: ShotFunction.advance,
            actionZh: '阴影中走出一人，手持古剑。',
            dialogue: '好久不见。',
            voiceType: UtteranceVoiceType.dialogue,
            characterIds: ['char_2'],
            propIds: ['prop_2'],
            sceneId: 'scene_1',
            cameraMove: '固定平视',
            assembledPrompt: 'A figure walks out of shadow',
          ),
        ],
      );

      final md = StoryboardExporter.exportToMarkdown(
        seriesTitle: '斩夜',
        episode: episode,
        characterNames: {'char_1': '林凡', 'char_2': '神秘人'},
        propNames: {'prop_1': '罗盘', 'prop_2': '古剑'},
        sceneNames: {'scene_1': '荒庙'},
      );

      expect(md, contains('# 《斩夜》第 1 集：第一集：初逢 - 导演分镜表'));
      expect(md, contains('- **镜头总数**：2 镜'));
      expect(md, contains('| #1 | 荒庙 | 4.0s | 特写 | 快速推镜 | 林凡猛然转头，眼神如刀。 | 林凡: "谁在那边？" | 罗盘 | 待生成 |'));
      expect(md, contains('| #2 | 荒庙 | 3.5s | 全景 | 固定平视 | 阴影中走出一人，手持古剑。 | 神秘人: "好久不见。" | 古剑 | 待生成 |'));
    });

    test('exportToCsv produces RFC 4180 format with UTF-8 BOM', () {
      final episode = StudioEpisode(
        id: 'ep_1',
        seriesId: 'series_1',
        index: 1,
        title: '测试集',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        shots: [
          const StudioShot(
            number: 1,
            durationSec: 3.0,
            shotSize: StudioShotSize.medium,
            mood: '平静',
            function: ShotFunction.opening,
            actionZh: '主角喝了一口茶，淡淡一笑。\n眼神望向远方。',
            dialogue: '这一仗，"难打"了。',
            voiceType: UtteranceVoiceType.dialogue,
            characterIds: ['char_1'],
            propIds: ['prop_1'],
            sceneId: '',
            cameraMove: '慢移',
            assembledPrompt: 'Prompt with, comma and "quotes"',
          ),
        ],
      );

      final csv = StoryboardExporter.exportToCsv(
        seriesTitle: '斩夜',
        episode: episode,
        characterNames: {'char_1': '林凡'},
        propNames: {'prop_1': '茶杯'},
      );

      // 验证 UTF-8 BOM
      expect(csv.startsWith('\uFEFF'), isTrue);

      // 验证双引号转义与换行转义
      expect(csv, contains('""难打""'));
      expect(csv, contains('"主角喝了一口茶，淡淡一笑。\n眼神望向远方。"'));
      expect(csv, contains('"Prompt with, comma and ""quotes"""'));
    });
  });

  group('ScreenplayImporter Tests', () {
    test('parse standard markdown screenplay with scenes and beats', () {
      const markdown = '''
### 第1场 议事堂（内景 / 日景 / 青云门议事堂）
> 氛围光影：清冷晨光斜射

**【节拍 1：掌门训诫】**
画面动作：掌门端坐高堂，面色严肃。
对白（掌门）：魔教异动，尔等当谨言慎行。

**【节拍 2：林凡请战】**
画面动作：林凡一步踏出，抱拳行礼。
对白（林凡）：弟子愿亲往查探！
心声（林凡 · 内心 OS）：绝不能让他们抢占先机。

### 第2场 后山竹林（外景 / 夜景 / 幽深竹海）
画面动作：夜风呼啸，竹影摇曳。
旁白：黑夜往往掩盖了最致命的杀意。
''';

      final result = ScreenplayImporter.parse(markdown);
      expect(result.isStructured, isTrue);
      expect(result.scenes.length, equals(2));

      final scene1 = result.scenes[0];
      expect(scene1.sceneNumber, equals(1));
      expect(scene1.setting, equals('内景'));
      expect(scene1.timeOfDay, equals('日景'));
      expect(scene1.location, equals('青云门议事堂'));
      expect(scene1.atmosphere, equals('清冷晨光斜射'));
      expect(scene1.beats.length, greaterThanOrEqualTo(2));
      expect(scene1.beats[0].dialogueSpeaker, equals('掌门'));
      expect(scene1.beats[0].dialogue, equals('魔教异动，尔等当谨言慎行。'));

      final scene2 = result.scenes[1];
      expect(scene2.sceneNumber, equals(2));
      expect(scene2.setting, equals('外景'));
      expect(scene2.timeOfDay, equals('夜景'));
      expect(scene2.beats.any((b) => b.voiceType == UtteranceVoiceType.narration), isTrue);
    });

    test('parse plain unstructured text gracefully degrades to rawText', () {
      const unstructuredText = '''
今天是个特别的日子。
小王走在熟悉的大街上，阳光照在他略显疲惫的脸上。
他看着来来往往的人群，心中感慨万千。
"也许一切都该结束了。"他喃喃自语。
''';

      final result = ScreenplayImporter.parse(unstructuredText);
      expect(result.isStructured, isFalse);
      expect(result.scenes, isEmpty);
      expect(result.rawText, equals(unstructuredText.trim()));
      expect(result.parseSummary, contains('草稿载入'));
    });
  });
}
