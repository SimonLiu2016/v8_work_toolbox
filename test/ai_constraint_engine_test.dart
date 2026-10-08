import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';

/// `AiConstraintEngine` 的模板与解析契约测试。
///
/// 这里固定的是 spec「AI 约束引擎集成」的三条承诺：
/// 1. 每个任务的 System Prompt 里都有取值域与 JSON Schema 示例；
/// 2. 合法 JSON 一次通过，坏 JSON 触发重试，重试耗尽抛
///    [ConstraintParseError] 且保留原始文本；
/// 3. 字段级硬约束（台词字数 = 时长 × 5）真的会拒收超标的 AI 输出。
void main() {
  /// 27 个汉字，超过 3 秒镜头的 15 字上限（时长 × 5 字/秒）。
  const tooLongDialogue = '这里有一句非常非常长的台词长到三秒钟绝对说不完这么多字';

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
      // 时长 2-6 秒与 5 字/秒
      expect(prompt, contains('2 到 6 秒'));
      expect(prompt, contains('× 5 个汉字'));
      // 8-12 个分镜
      expect(prompt, contains('8 到 12 个分镜'));
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

    test('时长超出 2-6 秒时拒收', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf(
          '{"shots": [{"number": 1, "duration_sec": 12, "shot_size": "medium", '
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
}
