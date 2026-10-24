import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/drama_director_contract.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

/// spec: ai-video-studio/shot-causality-ordering
///
/// 锁死两件事：
/// 1. 单镜与片段的提示词都带显式秒数区间，反应性台词不早于触发动作；
/// 2. 区间语法在分镜级与片段级之间保持一致（同一套编译器）。
StudioEpisode _episode({List<StudioShot> shots = const []}) => StudioEpisode(
  id: 'ep_1',
  seriesId: 's_01',
  index: 1,
  title: '第一集',
  shots: shots,
  createdAt: DateTime(2026, 10, 23),
  updatedAt: DateTime(2026, 10, 23),
);

CharacterCard _char(String id, String name) => CharacterCard(
  id: id,
  name: name,
  descriptionZh: '描述',
  updatedAt: DateTime(2026, 10, 23),
);

void main() {
  // ---------------------------------------------------------------------------
  // 1. 时间区间共享编译器
  // ---------------------------------------------------------------------------
  group('CausalityTimelineCompiler 累加区间', () {
    test('三个分镜时长累加，末镜结束时刻等于总时长', () {
      final ranges = CausalityTimelineCompiler.cumulativeRanges([4.0, 3.0, 5.0]);
      expect(ranges.length, 3);
      expect(ranges[0].$1, 0.0);
      expect(ranges[0].$2, 4.0);
      expect(ranges[1].$1, 4.0);
      expect(ranges[1].$2, 7.0);
      expect(ranges[2].$1, 7.0);
      expect(ranges[2].$2, 12.0);
    });

    test('格式化保留一位小数', () {
      expect(
        CausalityTimelineCompiler.formatRange(0, 4),
        '[0.0s - 4.0s]',
      );
      expect(
        CausalityTimelineCompiler.formatRanges(
          CausalityTimelineCompiler.cumulativeRanges([4.0, 3.0, 5.0]),
        ),
        '[0.0s - 4.0s] [4.0s - 7.0s] [7.0s - 12.0s]',
      );
    });

    test('区间数与输入一一对应（非正时长占位不错位）', () {
      final ranges = CausalityTimelineCompiler.cumulativeRanges([4.0, 0, 3.0]);
      expect(ranges.length, 3);
      expect(ranges[1].$1, ranges[1].$2);
      expect(ranges[2].$1, 4.0);
    });

    test('解析 temporalEvolution 的显式秒数分界', () {
      expect(
        CausalityTimelineCompiler.parsePhaseSplitSec('前1.5秒屏息试探，后1.5秒暴起接触'),
        1.5,
      );
      expect(
        CausalityTimelineCompiler.parsePhaseSplitSec('0.8秒破空突刺，0.5秒发丝断落'),
        0.8,
      );
    });

    test('解析不出秒数时返回 null（调用方回落默认次序）', () {
      expect(
        CausalityTimelineCompiler.parsePhaseSplitSec('动作处于屏息试探相位'),
        isNull,
      );
      expect(CausalityTimelineCompiler.parsePhaseSplitSec(''), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. 分镜级【因果时间轴】
  // ---------------------------------------------------------------------------
  group('buildVideoGenPrompt 因果时间轴', () {
    test('反应台词 + 离去动作：老王跳脚与台词晚于姜七夜动作区间', () {
      final jiang = _char('c_jiang', '姜七夜');
      final wang = _char('c_wang', '老王');
      final shot = StudioShot(
        number: 1,
        durationSec: 5.0,
        actionZh: '姜七夜拱手随意一拜，转身牵驴走出衙门，老王在背后跳脚',
        dialogue: '老王：你！你站住！反了你了！（预估2.0秒）',
        characterIds: ['c_jiang', 'c_wang'],
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
        characters: [jiang, wang],
      );

      expect(prompt.contains('【因果时间轴】'), isTrue);

      // 动作段落在对白段落之前（spec: 因果链先于台词）。
      final actionIdx = prompt.indexOf('【画面微动作】');
      final dialogueIdx = prompt.indexOf('正向对白约束');
      final timelineIdx = prompt.indexOf('【因果时间轴】');
      expect(actionIdx, greaterThanOrEqualTo(0));
      expect(dialogueIdx, greaterThan(actionIdx));
      expect(timelineIdx, greaterThan(dialogueIdx));
    });

    test('台词时段默认贴在本镜末尾', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 5.0,
        actionZh: '姜七夜拱手一拜转身牵驴离去',
        dialogue: '老王：你站住！（预估2.0秒）',
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      // 2.0s 台词贴末尾 → 动作占 0.0-3.0s，台词占 3.0-5.0s。
      expect(prompt.contains('0.0s-3.0s'), isTrue);
      expect(prompt.contains('3.0s-5.0s'), isTrue);
      final actionPart = prompt.indexOf('0.0s-3.0s');
      final dialoguePart = prompt.indexOf('3.0s-5.0s');
      expect(dialoguePart, greaterThan(actionPart));
    });

    test('无 temporalEvolution 且台词无预估标注时仍产出时间轴', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '姜七夜拱手一拜',
        dialogue: '老王：你站住！',
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      expect(prompt.contains('【因果时间轴】'), isTrue);
      // dialogueEstimatedSec 按 4 字/秒推算：剥掉括号后「老王：你站住！」7 字
      // → 1.75s。动作占 0.0-2.3s，台词占 2.3s-4.0s（一位小数）。
      expect(prompt.contains('0.0s-2.3s'), isTrue);
      expect(prompt.contains('2.3s-4.0s'), isTrue);
      // 无预估标注 → 标「约」。
      expect(prompt.contains('台词（约1.8s）'), isTrue);
    });

    test('有 temporalEvolution 显式秒数时按相位分界切分', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '韩立背抵药架猛然侧身',
        dialogue: '韩立：弟子确实不知。（预估1.5秒）',
        directorDecisions: DirectorDecisions(
          temporalEvolution: '前1.0秒屏息试探，后3.0秒暴起接触',
        ),
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      expect(prompt.contains('0.0s-1.0s'), isTrue);
      expect(prompt.contains('1.0s-4.0s'), isTrue);
      // 解析出秒数时，相位以秒数形式附加（不再原样吐 AI 自由文本）。
      expect(prompt.contains('相位：前 1.0 秒为动作相位'), isTrue);
    });

    test('temporalEvolution 解析不出秒数时不进提示词', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '韩立背抵药架',
        dialogue: '韩立：弟子不知。（预估1.5秒）',
        directorDecisions: DirectorDecisions(
          temporalEvolution: '动作处于屏息试探相位，为后续爆发蓄力',
        ),
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      // 不可解析的自由文本是噪声：模型不读、人看冗余（spec: 无法解析秒数的
      // 相位描述不进提示词）。时间轴本身仍按默认次序产出。
      expect(prompt.contains('【因果时间轴】'), isTrue);
      expect(prompt.contains('相位说明'), isFalse);
      expect(prompt.contains('动作处于屏息试探相位'), isFalse);
    });

    test('内心独白不参与动作因果排序', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '姜七夜面无表情垂手而立',
        dialogue: '姜七夜（内心 OS）：又来了，这老头每月俸禄被扣，就拿我撒气。（预估3.0秒）',
        voiceType: UtteranceVoiceType.innerVoice,
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      // 心声是画外音，与画面并行，不出现在时间轴里。
      expect(prompt.contains('【因果时间轴】'), isFalse);
      expect(prompt.contains('正向画音约束'), isTrue);
    });

    test('纯动作镜头不产出时间轴', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '暴雨猛烈拍打窗棂',
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      expect(prompt.contains('【因果时间轴】'), isFalse);
      expect(prompt.contains('正向动作约束'), isTrue);
    });

    test('时间轴是派生段，不污染 actionZh', () {
      final actionZh = '姜七夜拱手随意一拜，转身牵驴走出衙门';
      final shot = StudioShot(
        number: 1,
        durationSec: 5.0,
        actionZh: actionZh,
        dialogue: '老王：你站住！（预估2.0秒）',
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      // actionZh 本身不含秒数；时间戳只存在于时间轴段。
      expect(shot.actionZh, actionZh);
      expect(prompt.contains('【画面微动作】: $actionZh'), isTrue);
    });

    test('用户定制 videoPrompt 优先，不追加时间轴', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 5.0,
        actionZh: '姜七夜拱手一拜',
        dialogue: '老王：你站住！（预估2.0秒）',
        videoPrompt: '自定义提示词',
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
      );

      expect(prompt, '自定义提示词');
    });
  });

  // ---------------------------------------------------------------------------
  // 3. 片段级：保留对白 + 时序序列
  // ---------------------------------------------------------------------------
  group('buildSegmentPrompt 保留对白并输出时序序列', () {
    test('三分镜片段产出三个区间，对白未被剥离', () {
      final s1 = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '姜七夜拱手随意一拜',
      );
      final s2 = StudioShot(
        number: 2,
        durationSec: 3.0,
        actionZh: '姜七夜转身牵驴向衙门口走去',
        dialogue: '老王：你！你站住！反了你了！',
      );
      final s3 = StudioShot(
        number: 3,
        durationSec: 5.0,
        actionZh: '老王在背后跳脚',
      );

      final assembled = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 12,
          shots: [
            SegmentShotParts(
              number: 1,
              actionZh: s1.actionZh,
              dialogue: s1.dialogue,
              cameraMove: s1.cameraMove,
              durationSec: s1.durationSec,
            ),
            SegmentShotParts(
              number: 2,
              actionZh: s2.actionZh,
              dialogue: s2.dialogue,
              cameraMove: s2.cameraMove,
              durationSec: s2.durationSec,
            ),
            SegmentShotParts(
              number: 3,
              actionZh: s3.actionZh,
              dialogue: s3.dialogue,
              cameraMove: s3.cameraMove,
              durationSec: s3.durationSec,
            ),
          ],
        ),
      );

      expect(assembled.positive.contains('[0.0s - 4.0s]'), isTrue);
      expect(assembled.positive.contains('[4.0s - 7.0s]'), isTrue);
      expect(assembled.positive.contains('[7.0s - 12.0s]'), isTrue);
      // 对白必须保留（spec: 台词 SHALL NOT 从片段提示词中剥离）。
      expect(assembled.positive.contains('你！你站住！反了你了！'), isTrue);
    });

    test('片段内含闭口守卫措辞', () {
      final assembled = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 6,
          shots: [
            SegmentShotParts(
              number: 1,
              durationSec: 6.0,
              actionZh: '姜七夜拱手一拜',
              dialogue: '老王：你站住！',
            ),
          ],
        ),
      );

      expect(assembled.positive.contains('声音与画面约束'), isTrue);
      expect(assembled.positive.contains('嘴唇保持自然闭合'), isTrue);
      expect(assembled.positive.contains('不对口型'), isTrue);
    });

    test('乙台词所在区间起始秒数大于甲动作所在区间起始秒数', () {
      final assembled = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 7,
          shots: [
            SegmentShotParts(
              number: 1,
              durationSec: 4.0,
              actionZh: '姜七夜拱手随意一拜',
            ),
            SegmentShotParts(
              number: 2,
              durationSec: 3.0,
              actionZh: '姜七夜转身牵驴离去',
              dialogue: '老王：反了你了！',
            ),
          ],
        ),
      );

      final jiangIdx = assembled.positive.indexOf('[0.0s - 4.0s]');
      final wangIdx = assembled.positive.indexOf('[4.0s - 7.0s]');
      expect(jiangIdx, greaterThanOrEqualTo(0));
      expect(wangIdx, greaterThan(jiangIdx));
    });

    test('纯动作片段不注入闭口守卫', () {
      final assembled = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 4,
          shots: [
            SegmentShotParts(
              number: 1,
              durationSec: 4.0,
              actionZh: '暴雨猛烈拍打窗棂',
            ),
          ],
        ),
      );

      expect(assembled.positive.contains('声音与画面约束'), isFalse);
    });

    test('分镜级与片段级使用同一套区间语法', () {
      final ranges = CausalityTimelineCompiler.cumulativeRanges([4.0, 3.0, 5.0]);
      final assembled = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 12,
          shots: [
            SegmentShotParts(number: 1, durationSec: 4.0, actionZh: '甲动作'),
            SegmentShotParts(number: 2, durationSec: 3.0, actionZh: '乙动作'),
            SegmentShotParts(number: 3, durationSec: 5.0, actionZh: '丙动作'),
          ],
        ),
      );

      // 逐个区间核对：整串匹配会因为片段提示词的换行结构而失败。
      for (final (start, end) in ranges) {
        expect(
          assembled.positive.contains(CausalityTimelineCompiler.formatRange(start, end)),
          isTrue,
        );
      }
    });
  });
}
