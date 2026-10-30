import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';

/// `AiConstraintEngine` 的模板与解析契约测试。
///
/// 这里固定的是 spec「AI 约束引擎集成」的三条承诺：
/// 1. 每个任务的 System Prompt 里都有取值域与 JSON Schema 示例；
/// 2. 合法 JSON 一次通过，坏 JSON 触发重试，重试耗尽抛
///    [ConstraintParseError] 且保留原始文本；
/// 3. 字段级硬约束（台词字数 = 时长 × 5）真的会拒收超标的 AI 输出。
void main() {
  /// 超过 3 秒镜头上限（3 × 5 = 15 字，即使包含预估秒数标注容差 15 字也超过 30 字）。
  const tooLongDialogue = '这里有一句非常非常长的台词长到三秒钟绝对说不完这么多字，因为台词太长太长太长了完全无法在一瞬之间全部念完';


  tearDown(AiConstraintEngine.resetForTesting);

  ChatResult chatOf(String text) => ChatResult(
    text: text,
    usedProviderId: 'deepseek',
    usedModel: 'deepseek-chat',
    routingTrace: const [],
  );

  group('System Prompt 模板', () {
    test('每个任务都有非空模板', () {
      for (final task in StudioAiTask.values) {
        final prompt = AiConstraintEngine.systemPromptFor(task);
        expect(prompt, isNotEmpty, reason: '${task.id} 缺模板');
        expect(prompt, contains('JSON'), reason: '${task.id} 的模板没有提到 JSON');
      }
    });

    test('scriptBreakdown 模板含景别/时长/情绪/台词字数约束与 Schema', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.scriptBreakdown,
      );
      // 取值域
      expect(prompt, contains('close_up'));
      expect(prompt, contains('extreme_long'));
      expect(prompt, contains('depressing'));
      expect(prompt, contains('opening'));
      // 时长 4.0 到 12.0 秒
      expect(prompt, contains('4.0 到 12.0 秒'));
      // 8-16 个分镜
      expect(prompt, contains('8 到 16 个分镜'));


      // JSON Schema 与 Example
      expect(prompt, contains('【Output JSON Schema】'));
      expect(prompt, contains('【Example】'));
      expect(prompt, contains('"shots"'));
    });

    test('promptTranslation 模板按制作类型适配画风', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.promptTranslation,
      );
      expect(prompt, contains('prompt_positive'));
      expect(prompt, contains('prompt_negative'));
      for (final style in ['photorealistic', 'anime style', 'illustration style']) {
        expect(prompt, contains(style));
      }
    });

    test('ideaIncubation 模板要求 3 个方向与分集节奏', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.ideaIncubation,
      );
      expect(prompt, contains('恰好输出 3 个方向'));
      expect(prompt, contains('pacing'));
      expect(prompt, contains('strategy'));
    });

    test('bgmRecommend 模板禁止编造列表之外的曲名', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.bgmRecommend,
      );
      expect(prompt, contains('不得编造列表之外的曲名'));
    });
  });

  group('JSON 提取', () {
    test('裸 JSON 直接解析', () {
      final parsed = AiConstraintEngine.parseJsonLoose('{"a": 1}');
      expect(parsed, isNotNull);
      expect(parsed!['a'], 1);
    });

    test('剥掉 ```json 代码围栏', () {
      const raw = '```json\n{"a": 1}\n```';
      expect(AiConstraintEngine.parseJsonLoose(raw)!['a'], 1);
    });

    test('剥掉带前缀解释文字的代码围栏', () {
      const raw = '好的，以下是结果：\n```JSON\n{"a": 1}\n```\n希望有帮助';
      expect(AiConstraintEngine.parseJsonLoose(raw)!['a'], 1);
    });

    test('截取首个 { 到末个 } 之间的内容', () {
      const raw = '我拆好了：\n{"a": 1}\n以上。';
      expect(AiConstraintEngine.parseJsonLoose(raw)!['a'], 1);
    });

    test('纯文本返回 null', () {
      expect(AiConstraintEngine.parseJsonLoose('我无法完成这个任务'), isNull);
      expect(AiConstraintEngine.parseJsonLoose(''), isNull);
    });

    test('截断在数组中途的 JSON 能够安全自愈并挽救已完成条目', () {
      const truncated = '''
{
  "season_title": "寒阳镇魔",
  "target_duration_sec": 90,
  "episodes": [
    {"episode_number": 1, "title": "第一集", "conflict": "开局对峙"},
    {"episode_number": 2, "title": "第二集", "conflict": "夜探黑渊"},
    {"episode_number": 3, "title": "第三集", "conflict": "尚未写完的核心冲突
''';
      final parsed = AiConstraintEngine.parseJsonLoose(truncated);
      expect(parsed, isNotNull);
      expect(parsed!['season_title'], '寒阳镇魔');
      final eps = parsed['episodes'] as List;
      expect(eps.length, 2);
      expect(eps[0]['title'], '第一集');
      expect(eps[1]['title'], '第二集');
    });

    test('截断在对象字段间的 JSON 能够自动闭合', () {
      const truncated = '''
{
  "season_title": "短剧大纲",
  "episodes": [
    {"episode_number": 1, "title": "集1"}
  ],
  "extra_key": "未完成的
''';
      final parsed = AiConstraintEngine.parseJsonLoose(truncated);
      expect(parsed, isNotNull);
      expect(parsed!['season_title'], '短剧大纲');
      expect((parsed['episodes'] as List).length, 1);
    });
  });

  group('scriptBreakdown 解析', () {
    test('合法分镜一次通过并归一化字段', () async {
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        return chatOf('''
{"shots": [
  {"number": 1, "duration_sec": 3, "shot_size": "中景", "mood": "压抑",
   "function": "开场", "action_zh": "雨夜回头", "dialogue": "",
   "character_ids": [], "scene_id": "", "camera_move": "slow push-in"},
  {"number": 2, "duration_sec": 5, "shot_size": "close_up", "mood": "excited",
   "function": "advance", "action_zh": "冲向黑影", "dialogue": "站住！",
   "character_ids": [], "scene_id": "", "camera_move": "handheld follow"}
]}
''');
      };

      final result = await AiConstraintEngine.scriptBreakdown(
        synopsis: '女主雨夜发现丈夫出轨',
        context: const ScriptContext(seriesName: '雨夜', episodeIndex: 1),
      );

      expect(calls, 1, reason: '合法输出不该重试');
      expect(result.attempt, 1);
      final shots = result.data['shots'] as List;
      expect(shots, hasLength(2));
      // 中文景别/情绪/功能被归一化为枚举 id
      expect(shots[0]['shot_size'], 'medium');
      expect(shots[0]['mood'], 'depressing');
      expect(shots[0]['function'], 'opening');
      expect(shots[1]['shot_size'], 'close_up');
    });

    test('台词超出 时长×5 上限时拒收并重试', () async {
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        // 3 秒镜头塞 27 个汉字的台词，上限是 3 × 5 = 15。
        return chatOf(
          '{"shots": [{"number": 1, "duration_sec": 3, "shot_size": "medium", '
          '"mood": "warm", "function": "opening", "action_zh": "长台词", '
          '"dialogue": "$tooLongDialogue", '
          '"character_ids": [], "scene_id": "", "camera_move": ""}]}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
      expect(calls, AiConstraintEngine.maxAttempts);
    });

    test('时长超出 3-12 秒时拒收', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"shots": [{"number": 1, "duration_sec": 15, "shot_size": "medium", '
          '"mood": "warm", "function": "opening", "action_zh": "", '
          '"dialogue": "", "character_ids": [], "scene_id": "", '
          '"camera_move": ""}]}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
    });

    test('非 JSON 输出重试至上限且保留原始文本', () async {
      const badText = '我觉得这个剧情可以这样发展……（没有任何 JSON）';
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        return chatOf(badText);
      };

      try {
        await AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        );
        fail('应当抛 ConstraintParseError');
      } on ConstraintParseError catch (e) {
        expect(e.attempts, 3);
        expect(e.rawText, badText);
        expect(e.task, StudioAiTask.scriptBreakdown);
      }
      expect(calls, 3);
    });

    test('重试提示里带上一次的原始输出', () async {
      final seenUserMessages = <String>[];
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        seenUserMessages.add(messages.last['content'] ?? '');
        if (calls == 1) return chatOf('这不是 JSON');
        return chatOf(
          '{"shots": [{"number": 1, "duration_sec": 4, "shot_size": "long", '
          '"mood": "sad", "function": "opening", "action_zh": "离别", '
          '"dialogue": "保重", "character_ids": [], "scene_id": "", '
          '"camera_move": "wide static"}]}',
        );
      };

      final result = await AiConstraintEngine.scriptBreakdown(
        synopsis: '测试',
        context: const ScriptContext(),
      );
      expect(result.attempt, 2);
      expect(seenUserMessages[1], contains('这不是 JSON'));
      expect(seenUserMessages[1], contains('无法解析'));
    });

    test('跨集记忆与角色清单注入 user prompt', () async {
      String? capturedUser;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        capturedUser = messages.last['content'];
        return chatOf(
          '{"shots": [{"number": 1, "duration_sec": 4, "shot_size": "long", '
          '"mood": "sad", "function": "opening", "action_zh": "离别", '
          '"dialogue": "", "character_ids": [], "scene_id": "", '
          '"camera_move": ""}]}',
        );
      };

      await AiConstraintEngine.scriptBreakdown(
        synopsis: '第二集大纲',
        context: const ScriptContext(
          seriesName: '雨夜',
          episodeIndex: 2,
          memoryContext: '【前情提要】\n- 第 1 集：女主离家\n'
              '【上集末尾钩子】入职第一天见到初恋',
          characterNames: ['林晓', '陈警官'],
          sceneNames: ['警局审讯室'],
        ),
      );

      expect(capturedUser, contains('第 2 集'));
      expect(capturedUser, contains('上集末尾钩子'));
      expect(capturedUser, contains('林晓'));
      expect(capturedUser, contains('警局审讯室'));
    });

    test('跨集状态台账注入 user prompt', () async {
      String? capturedUser;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        capturedUser = messages.last['content'];
        return chatOf(
          '{"shots": [{"number": 1, "duration_sec": 4, "shot_size": "long", '
          '"mood": "sad", "function": "opening", "action_zh": "离别", '
          '"dialogue": "", "character_ids": [], "scene_id": "", '
          '"camera_move": "", "continuity": {"world_position": "巷口", '
          '"screen_position": "", "holding_left": "", "holding_right": "", '
          '"lighting_state": "", "state_changes": []}}]}',
        );
      };

      await AiConstraintEngine.scriptBreakdown(
        synopsis: '第二集大纲',
        context: const ScriptContext(
          seriesName: '雨夜',
          episodeIndex: 2,
          carryOverState: '角色位于巷口左侧，右手持有折叠刀',
        ),
      );

      // 措辞必须是「既定初始状态，直接沿用，不得推导其来源」——
      // 写成「请据此推导」会诱导 AI 补前史。
      expect(capturedUser, contains('既定初始状态'));
      expect(capturedUser, contains('不得推导其来源'));
      expect(capturedUser, contains('右手持有折叠刀'));
    });
  });

  group('片段结构校验', () {
    /// 造一份合法的分镜 JSON（含 continuity），供片段测试复用。
    String shotsJson() => '''
{"shots": [
  {"number": 1, "duration_sec": 3, "shot_size": "medium", "mood": "warm",
   "function": "opening", "action_zh": "回眸", "dialogue": "",
   "character_ids": ["c1"], "scene_id": "", "camera_move": "push-in",
   "continuity": {"world_position": "巷口", "screen_position": "",
   "holding_left": "", "holding_right": "刀", "lighting_state": "",
   "state_changes": []}},
  {"number": 2, "duration_sec": 4, "shot_size": "full", "mood": "warm",
   "function": "advance", "action_zh": "走近", "dialogue": "",
   "character_ids": ["c1"], "scene_id": "", "camera_move": "follow",
   "continuity": {"world_position": "巷口中段", "screen_position": "",
   "holding_left": "", "holding_right": "刀", "lighting_state": "",
   "state_changes": []}}
]}
''';

    test('片段覆盖全部分镜且镜号不重叠时通过', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": [{"segment_id": 1, "target_duration_sec": 7, '
          '"boundary_reason": "开场建立空间", "shot_numbers": [1, 2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      final result = await AiConstraintEngine.scriptBreakdown(
        synopsis: '测试',
        context: const ScriptContext(),
      );

      expect(result.attempt, 1, reason: '合法片段结构不该重试');
      final segments = result.data['segments'] as List;
      expect(segments, hasLength(1));
      expect(segments.first['shot_numbers'], [1, 2]);
    });

    test('片段未覆盖全部分镜时拒收', () async {
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        return chatOf(
          '{"segments": [{"segment_id": 1, "target_duration_sec": 3, '
          '"boundary_reason": "只覆盖第一镜", "shot_numbers": [1]}], '
          '${shotsJson().substring(1)}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
      expect(calls, greaterThan(1), reason: '校验失败应该重试');
    });

    test('片段镜号重叠时拒收', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": ['
          '{"segment_id": 1, "target_duration_sec": 3, '
          '"boundary_reason": "第一段", "shot_numbers": [1]},'
          '{"segment_id": 2, "target_duration_sec": 4, '
          '"boundary_reason": "第二段重复覆盖第一镜", "shot_numbers": [1, 2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
    });

    test('相邻片段衔接不足时拒收', () async {
      // 两镜景别相同（medium / medium）且出场角色相同 → 不满足
      // 「主体不同 / 景别差 2 档 / 角度差 90°」中的任何一项。
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": ['
          '{"segment_id": 1, "target_duration_sec": 3, '
          '"boundary_reason": "第一段", "shot_numbers": [1]},'
          '{"segment_id": 2, "target_duration_sec": 4, '
          '"boundary_reason": "第二段", "shot_numbers": [2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
    });

    test('片段目标时长与分镜时长之和不符时拒收', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": [{"segment_id": 1, "target_duration_sec": 99, '
          '"boundary_reason": "时长乱填", "shot_numbers": [1, 2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
    });

    test('片段目标时长与分镜时长之和不符时拒收', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": [{"segment_id": 1, "target_duration_sec": 3, '
          '"boundary_reason": "第一段", "shot_numbers": [1, 2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
    });

    test('片段时长偏差被算出但不拒收', () async {
      // 分镜时长之和 = 3 + 4 = 7 秒，片段目标写 8 秒。偏差 +1 秒，落在单片段
      // 的 ±1 秒硬门槛内，所以不拒收；但 UI 要能看见这个偏差并提示用户
      // （spec: 单集片段数量与时长自洽）。
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": [{"segment_id": 1, "target_duration_sec": 8, '
          '"boundary_reason": "整集一段", "shot_numbers": [1, 2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      final result = await AiConstraintEngine.scriptBreakdown(
        synopsis: '测试',
        context: const ScriptContext(),
      );

      expect(result.attempt, 1, reason: '±1 秒内的偏差不该触发重试');
      expect(result.data['duration_deviation_sec'], 1);
    });

    test('片段时长超出单片段 ±1 秒硬门槛时拒收', () async {
      // 7 秒的片段目标写 10 秒：这不是"计时漂移"，是 AI 完全没按分镜计时。
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": [{"segment_id": 1, "target_duration_sec": 10, '
          '"boundary_reason": "整集一段", "shot_numbers": [1, 2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      await expectLater(
        AiConstraintEngine.scriptBreakdown(
          synopsis: '测试',
          context: const ScriptContext(),
        ),
        throwsA(isA<ConstraintParseError>()),
      );
    });

    test('片段时长与分镜时长一致时偏差为 0', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"segments": [{"segment_id": 1, "target_duration_sec": 7, '
          '"boundary_reason": "整集一段", "shot_numbers": [1, 2]}], '
          '${shotsJson().substring(1)}',
        );
      };

      final result = await AiConstraintEngine.scriptBreakdown(
        synopsis: '测试',
        context: const ScriptContext(),
      );

      expect(result.data['duration_deviation_sec'], 0);
    });

    test('没有 segments 字段时只返回 shots（旧版数据路径）', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(shotsJson());
      };

      final result = await AiConstraintEngine.scriptBreakdown(
        synopsis: '测试',
        context: const ScriptContext(),
      );

      expect(result.attempt, 1);
      expect(result.data.containsKey('segments'), isFalse);
      expect(result.data['shots'], hasLength(2));
    });
  });

  group('其他任务解析', () {
    test('ideaIncubation 要求恰好 3 个方向', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('{"directions": [{"title": "a", "hook": "b"}]}');
      };
      await expectLater(
        AiConstraintEngine.ideaIncubation(
          rawIdea: '想写个复仇故事',
          productionTypeLabel: '真人剧情短剧',
        ),
        throwsA(isA<ConstraintParseError>()),
      );
    });

    test('promptTranslation 抽出正负向 Prompt', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '```json\n{"prompt_positive": "1 girl, silver hair", '
          '"prompt_negative": "blurry, watermark"}\n```',
        );
      };
      final result = await AiConstraintEngine.promptTranslation(
        descriptionZh: '银色头发的女孩',
        productionType: 'drama',
      );
      expect(result.data['prompt_positive'], contains('silver hair'));
      expect(result.data['prompt_negative'], contains('watermark'));
    });

    test('bgmRecommend 按 score 降序返回', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"recommendations": ['
          '{"name": "紧张_追逐", "score": 70, "reason": "可用"},'
          '{"name": "战斗_高潮", "score": 95, "reason": "最匹配"}]}',
        );
      };
      final result = await AiConstraintEngine.bgmRecommend(
        moodLabel: '战斗',
        productionType: 'anime',
        availableTracks: ['战斗_高潮', '紧张_追逐'],
      );
      final recs = result.data['recommendations'] as List;
      expect(recs.first['name'], '战斗_高潮');
    });

    test('titleGeneration 要求 3 条标题', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"titles": [{"style": "emotion", "text": "一等就是十年"},'
          '{"style": "suspense", "text": "新郎喊了别的名字"},'
          '{"style": "payoff", "text": "赶我走的人求我回"}]}',
        );
      };
      final result = await AiConstraintEngine.titleGeneration(
        seriesName: '雨夜',
        productionType: 'drama',
        episodeSummary: '女主发现出轨证据',
      );
      expect((result.data['titles'] as List), hasLength(3));
    });

    test('episodeSummary 返回摘要与钩子', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('{"summary": "女主离家", "hook": "上司是初恋"}');
      };
      final result = await AiConstraintEngine.episodeSummary(
        synopsis: '粗剧情',
        shotsSummary: '1. 离家 2. 入职',
      );
      expect(result.data['summary'], '女主离家');
      expect(result.data['hook'], '上司是初恋');
    });

    test('shotRegenerate 返回单个 shot 对象', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"shot": {"number": 3, "duration_sec": 4, "shot_size": "close_up", '
          '"mood": "sad", "function": "advance", "action_zh": "看病例", '
          '"dialogue": "只剩三个月", "character_ids": [], "scene_id": "", '
          '"camera_move": "slow push-in"}}',
        );
      };
      final result = await AiConstraintEngine.shotRegenerate(
        currentShotJson: '{"number": 3}',
        instruction: '改成看病例单',
        context: const ScriptContext(),
      );
      expect(result.data['shot']['mood'], 'sad');
      expect(result.data['shot']['number'], 3);
    });
  });

  group('供应商错误', () {
    test('网络错误直接向上抛，不走 JSON 重试', () async {
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        throw const SlotUnavailableException(
          slotName: 'text',
          candidateCount: 1,
          candidateErrors: ['connection reset'],
        );
      };

      await expectLater(
        AiConstraintEngine.episodeSummary(
          synopsis: 'x',
          shotsSummary: 'y',
        ),
        throwsA(isA<SlotUnavailableException>()),
      );
      expect(calls, 1, reason: '供应商不可用是路由层的问题，重发只会让用户多等');
    });
  });

  group('任务超时映射测试', () {
    test('长篇小说全案解构与单章提炼任务默认超时为 240 秒，普通任务为 120 秒', () {
      expect(
        AiConstraintEngine.defaultTimeoutFor(StudioAiTask.novelMasterExtraction),
        equals(const Duration(seconds: 240)),
      );
      expect(
        AiConstraintEngine.defaultTimeoutFor(StudioAiTask.novelEpisodeSegmentation),
        equals(const Duration(seconds: 240)),
      );
      expect(
        AiConstraintEngine.defaultTimeoutFor(StudioAiTask.novelChapterAdaptation),
        equals(const Duration(seconds: 240)),
      );
      expect(
        AiConstraintEngine.defaultTimeoutFor(StudioAiTask.scriptBreakdown),
        equals(const Duration(seconds: 120)),
      );
      expect(
        AiConstraintEngine.defaultTimeoutFor(StudioAiTask.promptTranslation),
        equals(const Duration(seconds: 120)),
      );
    });

    test('adaptNovelChapter 调用时向 chatFn 传递 240 秒超时且正确校验结构化大纲', () async {
      Duration? capturedTimeout;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        capturedTimeout = timeout;
        return ChatResult(
          text: '{"title": "密室杀局", "synopsis": "【开局抓手】暴雨之夜韩立推开神手谷密室木门，赫然发现墨大夫面色铁青，手中短刃寒光逼人。【矛盾推进】墨大夫步步紧逼逼问长春功第四层口诀，韩立借取药引为由退至药柜死角暗中周旋。【核心高潮】墨大夫骤然暴起施展鹰爪功锁喉，韩立生死一线间反手掷出毒粉迷其双目。【本集断点】墨大夫临死前双目泛起幽绿魂光，夺舍残魂破体而出。", "summary": "韩立在密室用毒粉反制墨大夫肉身", "hook": "墨大夫残魂即将扑向韩立"}',
          usedProviderId: 'test-provider',
          usedModel: 'test-model',
          routingTrace: const [],
        );
      };

      final result = await AiConstraintEngine.adaptNovelChapter(
        novelText: '韩立进入密室……整章数千字原文……',
        seriesName: '凡人修仙',
        worldview: '仙凡两隔',
        characterNames: ['韩立', '墨大夫'],
        episodeIndex: 1,
      );

      expect(capturedTimeout, equals(const Duration(seconds: 240)));
      expect(result.data['title'], equals('密室杀局'));
      expect(result.data['synopsis'], contains('【开局抓手】'));
      expect(result.data['synopsis'], contains('【核心高潮】'));
      expect(result.data['hook'], contains('残魂'));
    });

    test('extractNovelMaster 调用时向 chatFn 传递 240 秒超时', () async {
      Duration? capturedTimeout;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        capturedTimeout = timeout;
        return ChatResult(
          text: '{"worldview": "世界观", "style_tokens": "cinematic", "characters": [{"name": "主角"}], "scenes": []}',
          usedProviderId: 'test-provider',
          usedModel: 'test-model',
          routingTrace: const [],
        );
      };

      await AiConstraintEngine.extractNovelMaster(novelText: '测试小说文本');
      expect(capturedTimeout, equals(const Duration(seconds: 240)));
    });

    test('scriptBreakdown5D 与 actionCombatBreakdown 模板与参数注入正常', () {
      final prompt5d = AiConstraintEngine.systemPromptFor(StudioAiTask.scriptBreakdown5D);
      expect(prompt5d, contains('五维导演决策'));
      expect(prompt5d, contains('physical_momentum'));
      expect(prompt5d, contains('dynamic_exit_state'));

      final promptCombat = AiConstraintEngine.systemPromptFor(StudioAiTask.actionCombatBreakdown);
      expect(promptCombat, contains('Combat DNA'));
      expect(promptCombat, contains('combat_steps'));
      expect(promptCombat, contains('duty'));

      final promptDrama = AiConstraintEngine.systemPromptFor(StudioAiTask.novelDramaChapterAdaptation);
      expect(promptDrama, contains('scenes'));
      expect(promptDrama, contains('beats'));
      expect(promptDrama, contains('protected_contract'));
    });

    test('scriptBreakdown 正确解析 5D 导演决策、战斗步骤与动态末态', () {
      final json = {
        'shots': [
          {
            'number': 1,
            'duration_sec': 3.5,
            'shot_size': 'close_up',
            'mood': 'battle',
            'function': 'burst',
            'action_zh': '墨大夫手腕翻转短刃泛起乌光直刺韩立咽喉，韩立生死一瞬偏头闪避。',
            'dialogue': '（厉喝）纳命来！（预估1.5秒）',
            'beat_id': 'B01',
            'cut_reason': '近景突刺危机',
            'visual_task': '呈现刀尖划破空气与韩立眼神骤缩',
            'director_decisions': {
              'physical_momentum': '墨大夫前扑，韩立后倾卸力',
              'lighting_staging': '闪电冷光侧照',
              'camera_staging': '微推向刀锋',
              'temporal_evolution': '冲刺余势',
              'aesthetic_texture': '次世代3D国漫UE5',
            },
            'combat_steps': [
              {
                'step_index': 1,
                'actor_name': '墨大夫',
                'target_names': ['韩立'],
                'intent': '刺喉',
                'attack': '短刃直刺',
                'defense': '偏头',
                'impact': '削断发丝',
                'displacement': '墨大夫前冲',
                'next_link': '韩立反手毒粉',
                'duty': 'impact',
              }
            ],
            'continuity': {
              'world_position': '药架前三尺',
              'screen_position': '画面右侧',
              'holding_right': '短刃',
              'dynamic_exit_state': {
                'support_foot': '右脚前跨',
                'velocity_vector': '向前2m/s',
                'unfinished_phase': '刺势未尽',
              }
            }
          }
        ]
      };

      final parsed = AiConstraintEngine.validateSchema(
        StudioAiTask.scriptBreakdown,
        json,
      );

      expect(parsed, isNotNull);
      final shots = (parsed!['shots'] as List).cast<Map<String, dynamic>>();
      expect(shots.length, 1);
      final s = shots.first;
      expect(s['beat_id'], 'B01');
      expect(s['cut_reason'], '近景突刺危机');
      expect(s['visual_task'], contains('呈现刀尖'));
      expect(s['director_decisions']['physical_momentum'], contains('墨大夫前扑'));
      expect((s['combat_steps'] as List).length, 1);
      final continuity = s['continuity'] as Map<String, dynamic>;
      expect(continuity['dynamic_exit_state']['support_foot'], '右脚前跨');
    });

    test('novelChapterAdaptation 正确解析 scenes 和 protected_contract', () {
      final json = {
        'title': '密室绝杀',
        'synopsis': '【开局抓手】暴雨之夜，韩立推开密室木门，墨大夫手持短刃寒光逼人。【矛盾推进】墨大夫逼问长春功口诀，韩立退至药柜死角周旋。【核心高潮】墨大夫暴起锁喉，韩立反手掷出毒粉迷其双目。【本集断点】墨大夫瘫倒狂笑，夺舍残魂破体而出。',
        'summary': '韩立反制墨大夫肉身',
        'hook': '夺舍残魂破体而出',
        'scenes': [
          {
            'id': 'SC001',
            'scene_number': 1,
            'title': '神手谷密室',
            'location': '神手谷内室',
            'setting': '内景',
            'time_of_day': '暴雨深夜',
            'atmosphere': '昏黄油灯斜照',
            'character_ids': ['墨大夫', '韩立'],
            'primary_light_world_direction': '北窗闪电',
            'landmarks': ['药柜', '石桌'],
            'beats': [
              {
                'id': 'B01',
                'scene_id': 'SC001',
                'order': 1,
                'name': '寒暄试探',
                'action': '墨大夫缓步逼近韩立，眼神阴鸷。',
                'dialogue_speaker': '墨大夫',
                'dialogue': '好徒儿，你的长春功练到第几层了？（预估2.5秒）',
                'subtext': '步步紧逼试探虚实',
                'estimated_sec': 4.0,
                'dramatic_function': 'threat_build',
              }
            ]
          }
        ],
        'protected_contract': {
          'facts': [
            {
              'id': 'F01',
              'type': 'FACT',
              'content': '墨大夫手持玄铁淬毒短刃',
              'source_location': '章节中段',
              'mandatory': true,
            }
          ],
          'utterances': [
            {
              'id': 'U01',
              'speaker': '墨大夫',
              'listener': '韩立',
              'text': '好徒儿，你的长春功练到第几层了？',
              'voice_type': 'dialogue',
              'estimated_sec': 3.0,
            }
          ],
          'protected_beats': ['B01'],
        }
      };

      final parsed = AiConstraintEngine.validateSchema(
        StudioAiTask.novelDramaChapterAdaptation,
        json,
      );

      expect(parsed, isNotNull);
      expect(parsed!['title'], '密室绝杀');
      expect((parsed['scenes'] as List).length, 1);
      final scene = (parsed['scenes'] as List).first as Map<String, dynamic>;
      expect(scene['title'], '神手谷密室');
      expect(scene['setting'], '内景');
      expect(scene['time_of_day'], '暴雨深夜');
      final beats = scene['beats'] as List;
      expect(beats.length, 1);
      final beat = beats.first as Map<String, dynamic>;
      expect(beat['dialogue_speaker'], '墨大夫');
      expect(beat['dialogue'], contains('长春功'));
      expect(beat['subtext'], contains('试探'));
      expect(beat['estimated_sec'], 4.0);
      expect(parsed['screenplay_text'], isNotEmpty);
      expect(parsed['screenplay_text'], contains('### 第1场 神手谷密室'));
      expect(parsed['screenplay_text'], contains('墨大夫'));

      final contract = parsed['protected_contract'] as Map<String, dynamic>;
      expect((contract['facts'] as List).length, 1);
      expect((contract['utterances'] as List).length, 1);
      expect(contract['protected_beats'], ['B01']);
    });

    test('screenplayGeneration 校验与归一化', () {
      final json = {
        'scenes': [
          {
            'id': 'SC001',
            'scene_number': 1,
            'title': '客栈二楼对峙',
            'location': '同福客栈二楼走廊',
            'setting': '内景',
            'time_of_day': '夜景',
            'atmosphere': '昏黄油灯斜照',
            'character_ids': ['姜七夜', '余小白'],
            'beats': [
              {
                'id': 'B01',
                'scene_id': 'SC001',
                'order': 1,
                'name': '抬刀轻挑',
                'action': '姜七夜抬起短刀指向凭栏的余小白。',
                'dialogue_speaker': '姜七夜',
                'dialogue': '余小白，我迟早得叫你姐夫。',
                'subtext': '满脸戏谑',
                'estimated_sec': 5.0,
              }
            ],
          }
        ]
      };

      final parsed = AiConstraintEngine.validateSchema(
        StudioAiTask.screenplayGeneration,
        json,
      );

      expect(parsed, isNotNull);
      final scenes = parsed!['scenes'] as List;
      expect(scenes.length, 1);
      final scene = scenes.first as Map<String, dynamic>;
      expect(scene['title'], '客栈二楼对峙');
      final beats = scene['beats'] as List;
      expect(beats.length, 1);
      final beat = beats.first as Map<String, dynamic>;
      expect(beat['dialogue_speaker'], '姜七夜');
      expect(beat['dialogue'], '余小白，我迟早得叫你姐夫。');
      expect(beat['estimated_sec'], 5.0);
    });

    test('calculateDynamicDurationSec 动态时长推导', () {
      // 纯对白推导：15个字 / 3.8 = 3.94s + 1.2s padding = 5.14s -> clamp(4.0, 12.0)
      final durationDialogue = AiConstraintEngine.calculateDynamicDurationSec(
        dialogue: '余小白，我迟早得叫你姐夫。',
        actionZh: '姜七夜抬刀。',
      );
      expect(durationDialogue, greaterThanOrEqualTo(4.0));
      expect(durationDialogue, lessThanOrEqualTo(12.0));

      // 无对白短动作保底 4.0s
      final durationShort = AiConstraintEngine.calculateDynamicDurationSec(
        dialogue: '',
        actionZh: '点头。',
      );
      expect(durationShort, 4.0);

      // 超长台词封顶 12.0s
      final durationLong = AiConstraintEngine.calculateDynamicDurationSec(
        dialogue: '这是一段非常非常非常非常非常非常非常非常长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长长的台词',
        actionZh: '狂奔并回头高喊',
      );
      expect(durationLong, 12.0);
    });

    test('isActionOverloaded 复合动作超载检测', () {
      // 简单动作未超载
      expect(
        AiConstraintEngine.isActionOverloaded('姜七夜靠在栏杆边撕咬鸡腿。'),
        isFalse,
      );

      // 超过3个连词或复合动作超载
      expect(
        AiConstraintEngine.isActionOverloaded(
          '姜七夜撕下鸡腿大嚼，然后油汁顺嘴角流下，接着抬刀轻挑指向三楼余小白，随后翻身跃下并拔刀劈砍。',
        ),
        isTrue,
      );
    });

    test('convertScenesToShots 将剧本场次与节拍正确映射为 5D 分镜', () {
      final scenes = [
        DramaScene(
          id: 'scene-1',
          sceneNumber: 1,
          title: '回春堂正门',
          location: '回春堂大厅',
          timeOfDay: '暴雨夜',
          atmosphere: '肃杀阴冷',
          beats: [
            DramaBeat(
              id: 'beat-1',
              sceneId: 'scene-1',
              order: 1,
              name: '对峙',
              action: '姜七夜手持油纸伞踏入大厅，雨水从伞骨滑落。',
              dialogueSpeaker: '姜七夜',
              dialogue: '谁是掌柜？',
              subtext: '表面沉静，暗藏杀机',
            ),
            DramaBeat(
              id: 'beat-2',
              sceneId: 'scene-1',
              order: 2,
              name: '拔刀',
              action: '姜七夜拔刀劈向黑衣人，刀芒破空。',
              dialogue: '',
              subtext: '迅猛突击',
            ),
          ],
        ),
      ];

      final characters = [
        CharacterCard(
          id: 'char-1',
          name: '姜七夜',
          descriptionZh: '巡街捕快',
          updatedAt: DateTime.now(),
        ),
      ];

      final sceneCards = [
        SceneCard(
          id: 'scene-1',
          name: '回春堂大厅',
          updatedAt: DateTime.now(),
        ),
      ];

      final shots = AiConstraintEngine.convertScenesToShots(
        scenes,
        characters: characters,
        sceneCards: sceneCards,
      );

      expect(shots.length, 2);
      expect(shots[0].number, 1);
      expect(shots[0].function, ShotFunction.opening);
      expect(shots[0].dialogue, '姜七夜：“谁是掌柜？”');
      expect(shots[0].characterIds, contains('char-1'));
      expect(shots[0].sceneId, 'scene-1');
      expect(shots[0].beatId, 'beat-1');
      expect(shots[0].directorDecisions.physicalMomentum, '表面沉静，暗藏杀机');
      expect(shots[0].continuity.worldPosition, '回春堂大厅');

      expect(shots[1].number, 2);
      expect(shots[1].function, ShotFunction.ending);
      expect(shots[1].dialogue, '');
      expect(shots[1].characterIds, contains('char-1'));
      expect(shots[1].sceneId, 'scene-1');
      expect(shots[1].beatId, 'beat-2');
    });
  });

  group('场景纯净空间约束与 ScenePromptBuilder', () {
    test('novelMasterExtraction 模板严禁场景出现人物并要求纯净空镜', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.novelMasterExtraction,
      );
      expect(prompt, contains('纯净物理空镜底板'));
      expect(prompt, contains('严禁描写任何具体人物姓名'));
      expect(prompt, contains('严禁包含人物动作'));
      expect(prompt, contains('纯粹描写建筑形制格局'));
    });

    test('novelMasterExtraction 校验器自动为缺少空镜词的场景注入 empty scene 前缀', () {
      final input = {
        'worldview': '修仙世界',
        'era_genre': 'xianxia',
        'style_tokens': 'ethereal',
        'characters': [
          {'name': '韩立', 'description_zh': '青年'},
        ],
        'scenes': [
          {
            'name': '丽香苑雅间',
            'description_zh': '雕花木案，轻纱罗帐',
            'prompt_en': 'ancient tea house interior',
          },
          {
            'name': '神手谷密室',
            'description_zh': '石桌药鼎',
            'prompt_en': 'empty scene, quiet alchemy chamber',
          },
        ],
      };

      final parsed = AiConstraintEngine.parseJsonLoose(
        jsonEncode(input),
      );
      expect(parsed, isNotNull);
      // 直接跑 task 校验
      final res = AiConstraintEngine.systemPromptFor(StudioAiTask.novelMasterExtraction);
      expect(res, isNotEmpty);

      // 验证 ScenePromptBuilder 组装结果
      final pos = ScenePromptBuilder.buildPositivePrompt(
        basePrompt: 'luxurious tea house, carved wood table, sheer curtains',
        styleTokens: 'ancient Chinese Xianxia fantasy',
        eraGenreId: 'xianxia',
        angle: SceneCameraAngle.panoramic,
      );

      expect(pos, contains(ScenePromptBuilder.emptyScenePositiveLock));
      expect(pos, contains('大广角全景建立镜头，宏大开阔大气氛围，极远景全貌'));
      expect(pos, contains('luxurious tea house'));
      expect(pos, contains('ancient Chinese Xianxia fantasy'));

      final neg = ScenePromptBuilder.buildNegativePrompt(
        eraGenreId: 'xianxia',
      );
      expect(neg, contains('人物, 人类, 男人, 女人'));
      expect(neg, contains('画面模糊失真, 低画质'));
    });

    test('SceneCameraAngle 覆盖 4 个核心视角', () {
      expect(SceneCameraAngle.values.length, 4);
      final angles = SceneCameraAngle.values.map((a) => a.labelZh).toList();
      expect(angles, contains('全景建立镜头'));
      expect(angles, contains('主视平视全景'));
      expect(angles, contains('侧逆视角'));
      expect(angles, contains('局部陈设特写'));
    });
  });

  group('因果时序约束（spec: shot-causality-ordering）', () {
    test('videoPromptRewrite 模板含因果时序唯一性铁律', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.videoPromptRewrite,
      );
      expect(prompt, contains('因果时序唯一性'));
      // 反应性台词不得前移至触发动作之前。
      expect(prompt, contains('必须晚于其触发动作'));
      expect(prompt, contains('严禁将台词前移至触发动作之前'));
      // 同镜多主体不得合并为同时发生。
      expect(prompt, contains('严禁合并为同时发生'));
    });

    test('scriptBreakdown5D 模板含反应性台词因果时序铁律', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.scriptBreakdown5D,
      );
      expect(prompt, contains('反应性台词因果时序铁律'));
      // 反应台词优先独立成镜。
      expect(prompt, contains('SHALL 优先分配到触发动作之后的独立分镜'));
      // temporal_evolution 必须声明相位先后。
      expect(prompt, contains('触发动作相位早于反应相位'));
      // 同镜多主体不得合并为同时发生。
      expect(prompt, contains('严禁把两个主体的动作写成同时发生'));
      // 剧情保真锁仍在（拆分不得改变剧情事实）。
      expect(prompt, contains('【剧情保真锁】'));
      expect(prompt, contains('SHALL NOT 改变该台词的内容、归属角色或相对顺序'));
    });
  });

  group('拆镜上下文包含节拍级导演字段（spec: 拆镜上下文包含节拍级导演字段）', () {
    /// 抓取 scriptBreakdown5D 实际提交给 AI 的 userPrompt。
    ///
    /// chatFn 收到的是 messages 列表，userPrompt 是最后一条 user 消息的正文。
    Future<String> captureBreakdownPrompt(ScriptContext context) async {
      String? captured;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        captured = messages.last['content'];
        // 返回一个能过 schema 校验的最小合法分镜——这里只关心被提交的
        // userPrompt，不关心解析结果。
        return chatOf(
          '{"shots": [{"number": 1, "duration_sec": 3, "shot_size": "medium",'
          ' "mood": "warm", "function": "advance", "action_zh": "测试",'
          ' "dialogue": "", "character_ids": [], "scene_id": "",'
          ' "camera_move": "static"}]}',
        );
      };
      await AiConstraintEngine.scriptBreakdown5D(
        synopsis: '粗大纲',
        context: context,
      );
      return captured ?? '';
    }

    test('节拍的台词、说话人、景别与机位进入拆镜上下文', () async {
      final prompt = await captureBreakdownPrompt(
        ScriptContext(
          seriesName: '测试剧',
          episodeIndex: 1,
          scenes: [
            DramaScene(
              id: 'SC001',
              sceneNumber: 1,
              title: '镇魔司大殿',
              location: '大殿',
              beats: [
                DramaBeat(
                  id: 'B01',
                  sceneId: 'SC001',
                  order: 1,
                  name: '授刀',
                  action: '东方诏将斩妖刀递与沈长青',
                  dialogueSpeaker: '东方诏',
                  dialogue: '斩妖除魔，护我人族！',
                  shotSize: 'medium',
                  cameraStaging: '平视定机位',
                ),
              ],
            ),
          ],
        ),
      );

      expect(prompt, contains('台词=东方诏：斩妖除魔，护我人族！'));
      expect(prompt, contains('景别=medium'));
      expect(prompt, contains('机位=平视定机位'));
    });

    test('节拍未填写的字段被省略，不写占位符', () async {
      final prompt = await captureBreakdownPrompt(
        ScriptContext(
          seriesName: '测试剧',
          episodeIndex: 1,
          scenes: [
            DramaScene(
              id: 'SC001',
              sceneNumber: 1,
              title: '镇魔司大殿',
              location: '大殿',
              beats: [
                DramaBeat(
                  id: 'B01',
                  sceneId: 'SC001',
                  order: 1,
                  name: '授刀',
                  action: '东方诏将斩妖刀递与沈长青',
                ),
              ],
            ),
          ],
        ),
      );

      expect(prompt, isNot(contains('台词=')));
      expect(prompt, isNot(contains('运镜=')));
      expect(prompt, isNot(contains('视线=')));
      expect(prompt, isNot(contains('潜台词=')));
      // 动作仍在。
      expect(prompt, contains('东方诏将斩妖刀递与沈长青'));
    });

    test('心声与旁白标注发声类型，对白不标注', () async {
      final prompt = await captureBreakdownPrompt(
        ScriptContext(
          seriesName: '测试剧',
          episodeIndex: 1,
          scenes: [
            DramaScene(
              id: 'SC001',
              sceneNumber: 1,
              title: '镇魔司大殿',
              location: '大殿',
              beats: [
                DramaBeat(
                  id: 'B01',
                  sceneId: 'SC001',
                  order: 1,
                  name: '心声',
                  action: '沈长青低头沉思',
                  dialogue: '这小子身手果然不凡',
                  voiceType: UtteranceVoiceType.innerVoice,
                ),
                DramaBeat(
                  id: 'B02',
                  sceneId: 'SC001',
                  order: 2,
                  name: '对白',
                  action: '东方诏正色开口',
                  dialogue: '斩妖除魔',
                  voiceType: UtteranceVoiceType.dialogue,
                ),
              ],
            ),
          ],
        ),
      );

      expect(prompt, contains('发声类型=${UtteranceVoiceType.innerVoice.label}'));
      // 对白是默认类型，不重复标注。
      expect(prompt, isNot(contains('发声类型=${UtteranceVoiceType.dialogue.label}')));
    });
  });

  group('剧本生成注入资产上下文（spec: 剧本生成注入资产上下文）', () {
    Future<String> captureScreenplayPrompt({
      List<String> characterNames = const [],
      List<String> characterProfiles = const [],
      List<String> sceneNames = const [],
      ProtectedContract contract = ProtectedContract.empty,
    }) async {
      String? captured;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        captured = messages.last['content'];
        // 返回一个能过 schema 校验的最小合法场景列表——这里只关心被提交的
        // userPrompt，不关心解析结果。
        return chatOf(
          '{"scenes": [{"id": "SC001", "scene_number": 1, "title": "大殿",'
          ' "location": "镇魔司大殿", "beats": [{"id": "B01", "scene_id": "SC001",'
          ' "order": 1, "name": "授刀", "action": "东方诏递刀"}]}]}',
        );
      };
      await AiConstraintEngine.screenplayGeneration(
        synopsis: '沈长青入职镇魔司。',
        characterNames: characterNames,
        characterProfiles: characterProfiles,
        sceneNames: sceneNames,
        protectedContract: contract,
      );
      return captured ?? '';
    }

    test('角色设定、已有场景卡名与契约均注入提示词', () async {
      final prompt = await captureScreenplayPrompt(
        characterNames: ['沈长青', '东方诏'],
        characterProfiles: ['沈长青（青年除魔使，玄色劲装）', '东方诏（威严长者，官袍）'],
        sceneNames: ['镇魔司大殿', '临安城街道'],
        contract: const ProtectedContract(
          facts: [
            ProtectedFact(id: 'F01', content: '沈长青获得玄铁斩妖刀'),
          ],
          utterances: [
            ProtectedUtterance(
              id: 'U01',
              speaker: '东方诏',
              listener: '沈长青',
              text: '斩妖除魔，护我人族！',
            ),
          ],
        ),
      );

      expect(prompt, contains('【角色设定】'));
      expect(prompt, contains('沈长青（青年除魔使，玄色劲装）'));
      expect(prompt, contains('【资产库已有场景'));
      expect(prompt, contains('镇魔司大殿'));
      expect(prompt, contains('临安城街道'));
      expect(prompt, contains('必须遵守的核心事实'));
      expect(prompt, contains('沈长青获得玄铁斩妖刀'));
      expect(prompt, contains('必须逐字保留的高光台词'));
      expect(prompt, contains('斩妖除魔，护我人族！'));
    });

    test('不传三个新参数时提示词不含这些段', () async {
      final prompt = await captureScreenplayPrompt(
        characterNames: ['沈长青'],
      );

      expect(prompt, contains('【出场角色】沈长青'));
      expect(prompt, isNot(contains('【角色设定】')));
      expect(prompt, isNot(contains('【资产库已有场景')));
      expect(prompt, isNot(contains('必须遵守的核心事实')));
      expect(prompt, isNot(contains('必须逐字保留的高光台词')));
    });
  });

  group('writersRoomMasterExtract 宏观分析与角色/集数规划', () {
    test('System Prompt 包含集数推荐与角色/关系契约要求', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.writersRoomMasterExtract,
      );
      expect(prompt, contains('recommended_episode_count'));
      expect(prompt, contains('episode_count_reason'));
      expect(prompt, contains('characters'));
      expect(prompt, contains('character_relations'));
      expect(prompt, contains('key_props'));
      expect(prompt, contains('核心关键道具清单'));
      expect(prompt, contains('seasons_roadmap'));
      expect(prompt, contains('全书多季宇宙规划路线图'));
    });

    test('MacroArcs System Prompt 包含四幕弧光指导与集数跨度划分', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.writersRoomMacroArcs,
      );
      expect(prompt, contains('四幕弧光设计原则'));
      expect(prompt, contains('破局立威'));
      expect(prompt, contains('绝地反击与季终高潮'));
      expect(prompt, contains('macro_arcs'));
    });

    test('SeasonBeats System Prompt 包含独立推进与四幕弧光指导', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.writersRoomSeasonBeats,
      );
      expect(prompt, contains('严禁机械克隆'));
      expect(prompt, contains('严禁添加任何类似 "(节拍 X)" 的机械化后缀'));
      expect(prompt, contains('结尾极限留钩'));
      expect(prompt, contains('key_props'));
    });

    test('合法 JSON 完整解析并规范化推荐集数、角色与关系列表', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('''
{
  "recommended_episode_count": 80,
  "episode_count_reason": "原著前段篇幅宏大，80集能充分展开悬念反转",
  "master_plot": "韩立偶获掌天瓶逆袭修仙",
  "must_keep": [{"title": "神手谷拜师", "description": "拜墨大夫为师", "significance": "开端"}],
  "can_cut": [{"title": "杂役争吵", "description": "琐事", "reason": "拖慢节奏"}],
  "can_modify": [{"title": "合并巡山师兄", "description": "合并工具人", "suggestion": "减少资产"}],
  "characters": [
    {
      "name": "韩立",
      "role": "主角",
      "personality": "隐忍坚毅",
      "appearance_features": "皮肤黝黑，粗布麻衣 (dark skin, plain robe)",
      "motivation": "求生求长生"
    }
  ],
  "character_relations": [
    {
      "from": "韩立",
      "to": "墨大夫",
      "relation_type": "虚与委蛇的师徒死敌",
      "description": "表面师徒，暗地搏杀"
    }
  ],
  "key_props": [
    {
      "name": "掌天瓶",
      "category": "核心金手指",
      "significance": "吸收月华催熟草药",
      "appearance": "绿色磨砂小玉瓶 (small green jade bottle)"
    }
  ]
}
''');
      };

      final res = await AiConstraintEngine.extractWritersRoomMaster(
        novelText: '测试小说内容',
        seriesName: '凡人修仙',
      );

      expect(res.data['recommended_episode_count'], 80);
      expect(res.data['episode_count_reason'], contains('80集'));
      expect(res.data['master_plot'], contains('韩立'));
      final characters = res.data['characters'] as List;
      expect(characters.length, 1);
      expect(characters.first['name'], '韩立');
      expect(characters.first['role'], '主角');

      final relations = res.data['character_relations'] as List;
      expect(relations.length, 1);
      expect(relations.first['from'], '韩立');
      expect(relations.first['to'], '墨大夫');

      final keyProps = res.data['key_props'] as List;
      expect(keyProps.length, 1);
      expect(keyProps.first['name'], '掌天瓶');
      expect(keyProps.first['category'], '核心金手指');
      expect(keyProps.first['significance'], contains('催熟草药'));
      expect(keyProps.first['appearance'], contains('green jade bottle'));
    });

    test('缺损或异常字段时自愈兜底默认值', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('''
{
  "master_plot": "极简大纲"
}
''');
      };

      final res = await AiConstraintEngine.extractWritersRoomMaster(
        novelText: '测试短篇',
        seriesName: '短篇剧',
      );

      // 自愈默认值
      expect(res.data['recommended_episode_count'], 80);
      expect(res.data['episode_count_reason'], isNotEmpty);
      expect(res.data['season_number'], 1);
      expect(res.data['season_title'], '第1季');
      expect(res.data['characters'], isEmpty);
      expect(res.data['character_relations'], isEmpty);
      expect(res.data['must_keep'], isEmpty);

      // 自愈兜底包含第 1 季的 seasons_roadmap
      final roadmap = res.data['seasons_roadmap'] as List;
      expect(roadmap, isNotEmpty);
      expect(roadmap.first['season_number'], 1);
      expect(roadmap.first['season_title'], '第1季');
      expect(roadmap.first['recommended_episode_count'], 80);
    });

    test('合法 JSON 完整解析并规范化 seasons_roadmap 多季列表', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('''
{
  "recommended_episode_count": 80,
  "episode_count_reason": "宏大篇章",
  "master_plot": "修仙全书",
  "season_number": 1,
  "season_title": "神手夺舍",
  "seasons_roadmap": [
    {
      "season_number": 1,
      "season_title": "神手风云",
      "adapted_chapters_range": "第 1 ~ 80 章",
      "recommended_episode_count": 80,
      "season_theme": "凡躯逆袭修仙",
      "core_antagonist": "墨大夫",
      "season_climax": "反杀墨大夫"
    },
    {
      "season_number": 2,
      "season_title": "宗门秘境",
      "adapted_chapters_range": "第 81 ~ 220 章",
      "recommended_episode_count": 80,
      "season_theme": "血色禁地生死夺宝",
      "core_antagonist": "六宗魔道",
      "season_climax": "筑基成功"
    }
  ]
}
''');
      };

      final res = await AiConstraintEngine.extractWritersRoomMaster(
        novelText: '全书正文',
        seriesName: '凡人修仙',
      );

      final roadmap = res.data['seasons_roadmap'] as List;
      expect(roadmap.length, 2);
      expect(roadmap[0]['season_title'], '神手风云');
      expect(roadmap[0]['adapted_chapters_range'], '第 1 ~ 80 章');
      expect(roadmap[1]['season_number'], 2);
      expect(roadmap[1]['season_title'], '宗门秘境');
      expect(roadmap[1]['season_climax'], '筑基成功');
    });

    test('planWritersRoomSeasonBeats 支持季上下文针对性注入 user prompt', () async {
      String? capturedPrompt;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        capturedPrompt = messages.firstWhere((m) => m['role'] == 'user')['content'];
        return chatOf('''
{
  "season_title": "宗门秘境",
  "target_duration_sec": 90,
  "macro_arcs": [],
  "episodes": [{"episode_number": 1, "title": "初入宗门", "conflict": "杂役考核", "characters": ["韩立"], "hook": "暗藏玄机", "duration_sec": 90}]
}
''');
      };

      await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '长篇主线',
        seriesName: '凡人修仙传',
        seasonNumber: 2,
        seasonTitle: '宗门秘境',
        adaptedChaptersRange: '第 81 ~ 220 章',
        seasonTheme: '血色禁地生死夺宝',
        seasonClimax: '筑基成功',
        episodeCount: 1,
      );

      expect(capturedPrompt, contains('【当前规划季】第 2 季 · 宗门秘境'));
      expect(capturedPrompt, contains('【对应原著章节跨度】第 81 ~ 220 章'));
      expect(capturedPrompt, contains('【本季核心叙事主题】血色禁地生死夺宝'));
      expect(capturedPrompt, contains('【本季终极大高潮】筑基成功'));
    });

    test('SeasonBeats 保持真实模型分集输出：保留模型返回的真实集数且自动清洗节拍后缀与注入篇章', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('''
{
  "season_title": "神手风云",
  "target_duration_sec": 90,
  "macro_arcs": [
    {"arc_number": 1, "title": "拜师与暗藏神瓶", "episode_range": "1-5", "core_conflict": "初入神手谷暗修长春功", "turning_point": "得掌天瓶"},
    {"arc_number": 2, "title": "识海反杀", "episode_range": "6-15", "core_conflict": "夺舍殊死对决", "turning_point": "反杀墨大夫踏入仙路"}
  ],
  "episodes": [
    {"episode_number": 1, "title": "初入神手谷 (节拍 1)", "conflict": "韩立拜师墨大夫", "characters": ["韩立", "墨大夫"], "hook": "密室暗门后有诡异视线", "duration_sec": 90},
    {"episode_number": 2, "title": "偶得绿瓶", "conflict": "夜拾掌天瓶", "characters": ["韩立"], "hook": "瓶身吸收月华异变", "duration_sec": 90},
    {"episode_number": 3, "title": "药草暴长", "conflict": "发现绿液奇效", "characters": ["韩立"], "hook": "药香引来巡夜弟子", "duration_sec": 90},
    {"episode_number": 4, "title": "墨师生疑", "conflict": "墨大夫查验脉象", "characters": ["墨大夫", "韩立"], "hook": "墨大夫脸色陡变", "duration_sec": 90},
    {"episode_number": 5, "title": "功法突破", "conflict": "长春功突破第三层", "characters": ["韩立"], "hook": "门外传来急促敲门声", "duration_sec": 90},
    {"episode_number": 6, "title": "好友张铁", "conflict": "张铁修习象甲功", "characters": ["张铁", "韩立"], "hook": "张铁失踪", "duration_sec": 90},
    {"episode_number": 7, "title": "暗查后山", "conflict": "寻找张铁下落", "characters": ["韩立"], "hook": "撞见诡异血迹", "duration_sec": 90},
    {"episode_number": 8, "title": "外门大比", "conflict": "七玄门内部角逐", "characters": ["厉飞雨", "韩立"], "hook": "厉飞雨服食抽髓丸被撞破", "duration_sec": 90},
    {"episode_number": 9, "title": "立威自保", "conflict": "暗中助厉飞雨", "characters": ["厉飞雨", "韩立"], "hook": "达成秘密同盟", "duration_sec": 90},
    {"episode_number": 10, "title": "毒药暗备", "conflict": "自制防身药散", "characters": ["韩立"], "hook": "墨大夫突然返谷", "duration_sec": 90},
    {"episode_number": 11, "title": "野狼帮夜袭", "conflict": "帮派决战爆发", "characters": ["韩立", "贾天龙"], "hook": "仙师现身震撼全场", "duration_sec": 90},
    {"episode_number": 12, "title": "仙师出手", "conflict": "金光上人御剑飞刃", "characters": ["金光上人", "韩立"], "hook": "符箓威压笼罩全谷", "duration_sec": 90},
    {"episode_number": 13, "title": "暗箭难防", "conflict": "韩立暗杀金光上人", "characters": ["韩立", "金光上人"], "hook": "夺得升仙令", "duration_sec": 90},
    {"episode_number": 14, "title": "墨师绝杀", "conflict": "墨大夫撕破脸皮擒拿韩立", "characters": ["墨大夫", "韩立"], "hook": "元神出窍扑向韩立识海", "duration_sec": 90},
    {"episode_number": 15, "title": "识海反杀", "conflict": "韩立神魂反噬墨大夫", "characters": ["韩立", "墨大夫"], "hook": "踏上修仙寻道长路", "duration_sec": 90}
  ]
}
''');
      };

      final res = await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '凡人修仙',
        seriesName: '神手风云',
        episodeCount: 15,
        targetDurationSec: 90,
      );

      final episodes = res.data['episodes'] as List;
      // 验证保留模型真实返回的 15 集，不进行伪机械拉伸克隆
      expect(episodes.length, 15, reason: '必须遵循模型真实返回，绝不机械插值克隆');
      expect(episodes.first['episode_number'], 1);
      expect(episodes.last['episode_number'], 15);
      expect(episodes.first['title'], '初入神手谷', reason: '必须清洗掉 (节拍 1) 后缀');
      expect(episodes.first['duration_sec'], 90);
      expect(episodes.last['duration_sec'], 90);

      // 验证两级篇章大幕与分集归属
      final arcs = res.data['macro_arcs'] as List;
      expect(arcs.length, 2);
      expect(arcs.first['title'], '拜师与暗藏神瓶');
      expect(episodes.first['arc_name'], contains('拜师'));
      expect(episodes.last['arc_name'], contains('反杀'));
    });

    test('planWritersRoomSeasonBeats 注入剧情独立性与禁止克隆硬约束提示', () async {
      String? capturedPrompt;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        capturedPrompt = messages.firstWhere((m) => m['role'] == 'user')['content'];
        return chatOf('''
{
  "season_title": "神手风云",
  "target_duration_sec": 90,
  "macro_arcs": [{"arc_number": 1, "title": "开局", "episode_range": "1-15"}],
  "episodes": [{"episode_number": 1, "title": "第1集", "conflict": "开篇", "characters": ["韩立"], "hook": "钩子", "duration_sec": 90}]
}
''');
      };

      await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '长篇小说主线',
        seriesName: '凡人修仙传',
        episodeCount: 15,
      );

      expect(capturedPrompt, contains('【剧情独立性硬约束】'));
      expect(capturedPrompt, contains('episodes 数组输出的每一集必须具备独一无二的核心对抗事件与不同断章钩子'));
      expect(capturedPrompt, contains('严禁在多集之间复制相同剧情，严禁添加任何类似 "(节拍 X)" 的机械化后缀'));
    });

    test('planWritersRoomSeasonBeats 大集数 (>20集) 时自动执行两阶段大幕分批推演并聚合', () async {
      int callCount = 0;
      final progressUpdates = <String>[];

      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        callCount++;
        if (callCount == 1) {
          // 阶段一：大幕规划
          return chatOf('''
{
  "season_title": "神手风云",
  "target_duration_sec": 90,
  "macro_arcs": [
    {"arc_number": 1, "title": "拜师药谷", "episode_range": "1-15", "core_conflict": "暗藏灵瓶", "turning_point": "催熟草药"},
    {"arc_number": 2, "title": "识海反杀", "episode_range": "16-30", "core_conflict": "夺舍对决", "turning_point": "反杀墨大夫"}
  ]
}
''');
        }

        if (callCount == 2) {
          // 阶段二：批次 1 (第 1 ~ 15 集)
          final epsList = [
            for (int i = 1; i <= 15; i++)
              '{"episode_number": $i, "title": "第$i集·拜师", "conflict": "冲突$i", "characters": ["韩立"], "hook": "钩子$i", "duration_sec": 90}'
          ].join(',\n');
          return chatOf('{"episodes": [\n$epsList\n]}');
        }

        // 阶段二：批次 2 (第 16 ~ 30 集)
        final epsList = [
          for (int i = 16; i <= 30; i++)
            '{"episode_number": $i, "title": "第$i集·反杀", "conflict": "决战$i", "characters": ["韩立", "墨大夫"], "hook": "钩子$i", "duration_sec": 90}'
        ].join(',\n');
        return chatOf('{"episodes": [\n$epsList\n]}');
      };

      final res = await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '长篇主线',
        seriesName: '凡人修仙',
        episodeCount: 30,
        targetDurationSec: 90,
        onProgress: (msg, prog) => progressUpdates.add(msg),
      );

      expect(callCount, 3);
      final eps = res.data['episodes'] as List;
      expect(eps.length, 30);
      expect(eps.first['episode_number'], 1);
      expect(eps.last['episode_number'], 30);
      expect(eps.first['arc_name'], '拜师药谷');
      expect(eps.last['arc_name'], '识海反杀');
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.any((p) => p.contains('正在构建全季宏观大篇章结构')), isTrue);
      expect(progressUpdates.any((p) => p.contains('拜师药谷')), isTrue);
      expect(progressUpdates.any((p) => p.contains('识海反杀')), isTrue);
    });

    test('SeasonBeats 容错保底：模型未输出 episodes 键时自动基于大幕生成全量 80 集', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('''
{
  "season_title": "大幕篇章",
  "target_duration_sec": 90,
  "macro_arcs": [
    {"arc_number": 1, "title": "初出茅庐", "episode_range": "1-40", "core_conflict": "初试锋芒", "turning_point": "得法宝"},
    {"arc_number": 2, "title": "名震修仙", "episode_range": "41-80", "core_conflict": "终极之战", "turning_point": "飞升"}
  ]
}
''');
      };

      final res = await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '长篇小说',
        seriesName: '修仙演义',
        episodeCount: 80,
      );

      final episodes = res.data['episodes'] as List;
      expect(episodes.length, 80);
      expect(episodes.first['episode_number'], 1);
      expect(episodes.last['episode_number'], 80);
      expect(episodes.first['arc_name'], contains('初出茅庐'));
      expect(episodes.last['arc_name'], contains('名震修仙'));
    });
  });
}

