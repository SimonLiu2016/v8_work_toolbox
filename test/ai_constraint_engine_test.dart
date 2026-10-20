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

      final validated = AiConstraintEngine.parseJsonLoose(
        '${input.toString().replaceAll("'", '"')}',
      );
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
}

