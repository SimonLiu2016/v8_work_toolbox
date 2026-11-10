import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_session_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/vocabulary_practice_dialog.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/vocabulary_review_dialog.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late VocabularyStudyStore store;
  late MeetingVocabularyIndex index;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('v8_vocab_study_test_');

    // 预填部分单词 profile
    final initialData = VocabularyStudyData(
      focusedWords: {'governance', 'refactoring', 'latency', 'sharding'},
      wordProfiles: const {
        'governance': VocabularyWordProfile(
          word: 'governance',
          phonetic: '/ˈɡʌvənəns/',
          partOfSpeech: 'n.',
          definitionZh: 'n. 治理；管理机制',
        ),
        'refactoring': VocabularyWordProfile(
          word: 'refactoring',
          phonetic: '/riːˈfæktərɪŋ/',
          partOfSpeech: 'n.',
          definitionZh: 'n. 代码重构',
        ),
        'latency': VocabularyWordProfile(
          word: 'latency',
          phonetic: '/ˈleɪtənsi/',
          partOfSpeech: 'n.',
          definitionZh: 'n. 延迟；响应时间',
        ),
        'sharding': VocabularyWordProfile(
          word: 'sharding',
          phonetic: '/ˈʃɑːdɪŋ/',
          partOfSpeech: 'n.',
          definitionZh: 'n. 分库分表；数据分片',
        ),
      },
    );

    final storeFile = File(p.join(tmpDir.path, 'vocabulary_study_store.json'));
    await storeFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(initialData.toJson()),
    );

    store = VocabularyStudyStore(baseDir: tmpDir);

    index = const MeetingVocabularyIndex(
      postings: {
        'governance': [
          VocabularyPosting(
            meetingId: 'meeting-1',
            meetingTitle: 'Architecture Review',
            turnIndex: 0,
            slotId: 'Alice',
            timestampMs: 0,
            sentence: 'We need tighter governance around schema migrations.',
          ),
        ],
        'refactoring': [
          VocabularyPosting(
            meetingId: 'meeting-1',
            meetingTitle: 'Architecture Review',
            turnIndex: 1,
            slotId: 'Bob',
            timestampMs: 5000,
            sentence: 'Refactoring this legacy module reduces technical debt.',
          ),
        ],
      },
      display: {
        'governance': 'governance',
        'refactoring': 'refactoring',
        'latency': 'latency',
        'sharding': 'sharding',
      },
    );
  });

  tearDown(() async {
    try {
      if (tmpDir.existsSync()) {
        await tmpDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('WordMemoryState 与记忆曲线更新', () {
    test('初始生词状态到期需复习', () {
      final state = store.memoryStateFor('governance');
      expect(state.proficiency, 0);
      expect(state.streak, 0);
      expect(state.mistakeCount, 0);
      expect(state.isDue(), isTrue);
    });

    test('测验正确：streak 递增，熟练度提升，复习间隔延长', () {
      store.recordQuizResult('governance', isCorrect: true);
      final s1 = store.memoryStateFor('governance');
      expect(s1.proficiency, 1);
      expect(s1.streak, 1);
      expect(s1.mistakeCount, 0);
      expect(s1.nextReviewDue, isNotEmpty);

      // 再次答对
      store.recordQuizResult('governance', isCorrect: true);
      final s2 = store.memoryStateFor('governance');
      expect(s2.proficiency, 2);
      expect(s2.streak, 2);
    });

    test('测验错误：streak 归零，错误计数递增，安排当天复习', () {
      // 先答对两次
      store.recordQuizResult('latency', isCorrect: true);
      store.recordQuizResult('latency', isCorrect: true);
      expect(store.memoryStateFor('latency').proficiency, 2);

      // 答错
      store.recordQuizResult('latency', isCorrect: false);
      final afterMistake = store.memoryStateFor('latency');
      expect(afterMistake.streak, 0);
      expect(afterMistake.mistakeCount, 1);
      expect(afterMistake.proficiency, 1);
      expect(afterMistake.isMistake, isTrue);
    });

    test('闪卡翻牌自评调整记忆状态', () {
      // 评级 0：遗忘
      store.recordSelfAssessment('sharding', rating: 0);
      expect(store.memoryStateFor('sharding').proficiency, 0);
      expect(store.memoryStateFor('sharding').mistakeCount, 1);

      // 评级 3：秒懂
      store.recordSelfAssessment('sharding', rating: 3);
      expect(store.memoryStateFor('sharding').proficiency, greaterThanOrEqualTo(3));
      expect(store.memoryStateFor('sharding').isMastered, isTrue);
    });

    test('筛选接口：dueWords / mistakeWords / masteredWords 正确分类', () {
      store.recordQuizResult('governance', isCorrect: false); // 错题
      store.recordSelfAssessment('refactoring', rating: 3);   // 秒懂掌握

      final due = store.getDueWords();
      expect(due, contains('governance'));

      final mistakes = store.getMistakeWords();
      expect(mistakes, contains('governance'));
      expect(mistakes, isNot(contains('refactoring')));

      final mastered = store.getMasteredWords();
      expect(mastered, contains('refactoring'));
    });
  });

  group('VocabularySessionController 会话引擎', () {
    test('盲听 4 选 1 测验生成 4 个互斥选项且包含正确答案', () {
      final session = VocabularySessionController.create(
        mode: VocabularyPracticeMode.quiz4Choice,
        words: ['governance', 'refactoring'],
        index: index,
        studyStore: store,
      );

      expect(session.totalCount, 2);
      final firstItem = session.currentItem;
      expect(firstItem, isNotNull);
      expect(firstItem!.word, 'governance');
      expect(firstItem.choices.length, 4);
      expect(firstItem.choices, contains('n. 治理；管理机制'));

      // 作答
      session.selectChoice(firstItem.correctChoiceIndex);
      expect(firstItem.isAnswered, isTrue);
      expect(firstItem.isCorrect, isTrue);
      expect(session.correctCount, 1);
    });
  });

  group('VocabularyPracticeDialog Widget 交互测试', () {
    testWidgets('盲听 4 选 1 测验界面作答与对错解析展示', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = VocabularySessionController.create(
        mode: VocabularyPracticeMode.quiz4Choice,
        words: ['governance'],
        index: index,
        studyStore: store,
      );

      final playedTexts = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: VocabularyPracticeDialog(
              session: session,
              onPlayTts: (text) async => playedTexts.add(text),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // 验证首屏自动播放发音
      expect(playedTexts, contains('governance'));
      expect(find.text('听音辨析 · 请选出正确释义'), findsOneWidget);

      // 点击正确选项作答
      final correctChoice = session.currentItem!.correctChoiceIndex;
      await tester.tap(find.byKey(ValueKey('quiz-choice-$correctChoice')));
      await tester.pump(const Duration(milliseconds: 50));

      // 作答后展开英文拼写与原句出处
      expect(find.text('governance'), findsOneWidget);
      expect(find.text('We need tighter governance around schema migrations.'), findsOneWidget);

      // 点击下一题完成会话
      await tester.tap(find.byKey(const ValueKey('vocab-quiz-next-btn')));
      await tester.pump(const Duration(milliseconds: 50));

      // 呈现报告卡
      expect(find.text('会话完成！'), findsOneWidget);
    });

    testWidgets('闪卡模式翻牌与自评更新记忆状态', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = VocabularySessionController.create(
        mode: VocabularyPracticeMode.flashcards,
        words: ['refactoring'],
        index: index,
        studyStore: store,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: VocabularyPracticeDialog(
              session: session,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // 翻牌前
      expect(find.text('？在脑海中回忆它的意思与会议语境'), findsOneWidget);

      // 点击翻牌
      await tester.tap(find.byKey(const ValueKey('vocab-flashcard-flip-btn')));
      await tester.pump(const Duration(milliseconds: 50));

      // 翻牌后显示释义与自评按键
      expect(find.text('n. 代码重构'), findsOneWidget);
      expect(find.byKey(const ValueKey('assess-btn-3')), findsOneWidget);

      // 自评秒懂 (rating 3)
      await tester.tap(find.byKey(const ValueKey('assess-btn-3')));
      await tester.pump(const Duration(milliseconds: 50));

      expect(store.memoryStateFor('refactoring').isMastered, isTrue);
      expect(find.text('会话完成！'), findsOneWidget);
    });

    test('练习进度持久化存储与会话断点接续与重置', () {
      expect(store.getPracticeProgress('study'), isNull);

      // 保存学习模式进度
      store.savePracticeProgress('study', 'latency');
      expect(store.getPracticeProgress('study'), equals('latency'));

      // 重启并读取新 store 实例验证持久化落盘
      final reloadedStore = VocabularyStudyStore(baseDir: tmpDir);
      expect(reloadedStore.getPracticeProgress('study'), equals('latency'));

      // 会话引擎传入 initialWord 自动定位至 latency (索引 2)
      final session = VocabularySessionController.create(
        mode: VocabularyPracticeMode.study,
        words: ['governance', 'refactoring', 'latency', 'sharding'],
        index: index,
        studyStore: reloadedStore,
        initialWord: reloadedStore.getPracticeProgress('study'),
      );
      expect(session.currentIndex, equals(2));
      expect(session.currentItem?.word, equals('latency'));

      // 一键从头开始重置
      session.resetToBeginning();
      expect(session.currentIndex, equals(0));
      expect(session.currentItem?.word, equals('governance'));

      // 清除进度
      reloadedStore.clearPracticeProgress('study');
      expect(reloadedStore.getPracticeProgress('study'), isNull);
    });

    testWidgets('盲听测验未作答前 4 项字重完全一致防泄题，作答后呈现对错解析', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = VocabularySessionController.create(
        mode: VocabularyPracticeMode.quiz4Choice,
        words: ['governance'],
        index: index,
        studyStore: store,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: VocabularyPracticeDialog(
              session: session,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // 验证未作答前：所有选项文字字重均为 normal，无任何提前加粗泄题
      final item = session.currentItem!;
      expect(item.isAnswered, isFalse);

      for (var i = 0; i < item.choices.length; i++) {
        final choiceFinder = find.descendant(
          of: find.byKey(ValueKey('quiz-choice-$i')),
          matching: find.text(item.choices[i]),
        );
        expect(choiceFinder, findsOneWidget);
        final textWidget = tester.widget<Text>(choiceFinder);
        expect(
          textWidget.style?.fontWeight,
          equals(FontWeight.normal),
          reason: '选项 $i 在未作答前不能加粗，避免泄露答案',
        );
      }

      // 点击作答
      final correctChoice = item.correctChoiceIndex;
      await tester.tap(find.byKey(ValueKey('quiz-choice-$correctChoice')));
      await tester.pump(const Duration(milliseconds: 50));

      // 作答后：正确选项字重应变为 w600
      final correctFinder = find.descendant(
        of: find.byKey(ValueKey('quiz-choice-$correctChoice')),
        matching: find.text(item.choices[correctChoice]),
      );
      final answeredTextWidget = tester.widget<Text>(correctFinder);
      expect(answeredTextWidget.style?.fontWeight, equals(FontWeight.w600));
    });

    testWidgets('练习面板断点接续提示展示及从头开始重置交互', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 预设上次学习到 latency (index 2)
      store.savePracticeProgress('study', 'latency');

      final session = VocabularySessionController.create(
        mode: VocabularyPracticeMode.study,
        words: ['governance', 'refactoring', 'latency', 'sharding'],
        index: index,
        studyStore: store,
        initialWord: store.getPracticeProgress('study'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: VocabularyPracticeDialog(
              session: session,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // 验证断点接续提示与当前位置
      expect(find.text('已接续上次进度'), findsOneWidget);
      expect(find.text('3 / 4'), findsOneWidget);
      expect(find.text('latency'), findsOneWidget);

      // 点击「从头开始」按钮
      await tester.tap(find.byKey(const ValueKey('vocab-practice-reset-btn')));
      await tester.pump(const Duration(milliseconds: 50));

      // 验证重置回第 1 题且接续提示消失
      expect(find.text('1 / 4'), findsOneWidget);
      expect(find.text('governance'), findsOneWidget);
      expect(find.text('已接续上次进度'), findsNothing);
    });

    test('ReviewTimeRange 时间跨度筛选与沉浸学习记录', () {
      final now = DateTime.now();

      // 沉浸学习记录：记录 governance
      store.recordWordStudied('governance');
      expect(store.memoryStateFor('governance').lastReviewedAt, isNotEmpty);

      // 手动设置不同时间段的最后学习时间
      store.recordQuizResult('refactoring', isCorrect: true); // now

      // latency 设置为 5 天前
      final fiveDaysAgo = now.subtract(const Duration(days: 5));
      final latencyState = WordMemoryState(
        word: 'latency',
        lastReviewedAt: fiveDaysAgo.toIso8601String(),
      );
      // 直接写入内存测试
      store.memoryStatesMapForTesting['latency'] = latencyState;

      // sharding 设置为 35 天前
      final thirtyFiveDaysAgo = now.subtract(const Duration(days: 35));
      final shardingState = WordMemoryState(
        word: 'sharding',
        lastReviewedAt: thirtyFiveDaysAgo.toIso8601String(),
      );
      store.memoryStatesMapForTesting['sharding'] = shardingState;

      // 验证今日学习：包含 governance 和 refactoring
      final todayWords = store.getWordsStudiedInRange(ReviewTimeRange.today, asOf: now);
      expect(todayWords, containsAll(['governance', 'refactoring']));
      expect(todayWords, isNot(contains('latency')));
      expect(todayWords, isNot(contains('sharding')));

      // 验证近 7 天：包含今日词汇 + 5 天前的 latency
      final last7DaysWords = store.getWordsStudiedInRange(ReviewTimeRange.last7Days, asOf: now);
      expect(last7DaysWords, containsAll(['governance', 'refactoring', 'latency']));
      expect(last7DaysWords, isNot(contains('sharding')));

      // 验证全部已学：包含所有 4 个词汇
      final allWords = store.getWordsStudiedInRange(ReviewTimeRange.allStudied, asOf: now);
      expect(allWords.length, equals(4));
      expect(allWords, containsAll(['governance', 'refactoring', 'latency', 'sharding']));
    });

    testWidgets('VocabularyReviewDialog 组件交互：时间跨度切换、模式自选与随机乱序出题', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 预先记录两个单词的学习
      store.recordWordStudied('governance');
      store.recordQuizResult('refactoring', isCorrect: true);

      VocabularyReviewConfig? resultConfig;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    resultConfig = await VocabularyReviewDialog.show(
                      ctx,
                      studyStore: store,
                    );
                  },
                  child: const Text('打开复习定制'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 点击打开弹窗
      await tester.tap(find.text('打开复习定制'));
      await tester.pumpAndSettle();

      // 验证弹窗各元素
      expect(find.text('复习定制'), findsOneWidget);
      expect(find.text('复习时间范围'), findsOneWidget);
      expect(find.byKey(const ValueKey('review-range-chip-today')), findsOneWidget);

      // 今日应该有 2 词
      expect(find.text('今日学习 (2)'), findsOneWidget);

      // 切换考核方式为「闪卡自评」
      await tester.tap(find.byKey(const ValueKey('review-mode-flashcards')));
      await tester.pumpAndSettle();

      // 点击开始复习
      await tester.tap(find.byKey(const ValueKey('review-start-submit-btn')));
      await tester.pumpAndSettle();

      expect(resultConfig, isNotNull);
      expect(resultConfig!.mode, equals(VocabularyPracticeMode.flashcards));
      expect(resultConfig!.words.length, equals(2));
      expect(resultConfig!.words, containsAll(['governance', 'refactoring']));
      expect(resultConfig!.isShuffled, isTrue);
    });

    group('自适应听觉熟悉度评估与末尾加测机制', () {
      test('evaluateAuditoryFamiliarity 认知分级判定准确性', () {
        // 1. 选错 -> lapse
        expect(
          VocabularyStudyStore.evaluateAuditoryFamiliarity(isCorrect: false, playCount: 1),
          equals(AuditoryFamiliarity.lapse),
        );
        expect(
          VocabularyStudyStore.evaluateAuditoryFamiliarity(isCorrect: false, playCount: 3),
          equals(AuditoryFamiliarity.lapse),
        );

        // 2. 答对，听 3 次或更多 -> struggling
        expect(
          VocabularyStudyStore.evaluateAuditoryFamiliarity(isCorrect: true, playCount: 3),
          equals(AuditoryFamiliarity.struggling),
        );
        expect(
          VocabularyStudyStore.evaluateAuditoryFamiliarity(isCorrect: true, playCount: 4),
          equals(AuditoryFamiliarity.struggling),
        );

        // 3. 答对，听 2 次 -> hesitant
        expect(
          VocabularyStudyStore.evaluateAuditoryFamiliarity(isCorrect: true, playCount: 2),
          equals(AuditoryFamiliarity.hesitant),
        );

        // 4. 答对，听 1 次且耗时 <= 4 秒 -> instant
        expect(
          VocabularyStudyStore.evaluateAuditoryFamiliarity(
            isCorrect: true,
            playCount: 1,
            responseDuration: const Duration(seconds: 2),
          ),
          equals(AuditoryFamiliarity.instant),
        );

        // 5. 答对，听 1 次且耗时 > 4 秒 -> normal
        expect(
          VocabularyStudyStore.evaluateAuditoryFamiliarity(
            isCorrect: true,
            playCount: 1,
            responseDuration: const Duration(seconds: 5),
          ),
          equals(AuditoryFamiliarity.normal),
        );
      });

      test('recordQuizResult 依据 Familiarity 动态缩短与延长复习排期', () {
        final now = DateTime.now();

        // 1. 秒懂精通：熟练度升级，排期延长
        final fam1 = store.recordQuizResult(
          'governance',
          isCorrect: true,
          playCount: 1,
          responseDuration: const Duration(milliseconds: 1500),
        );
        expect(fam1, equals(AuditoryFamiliarity.instant));
        final state1 = store.memoryStateFor('governance');
        expect(state1.proficiency, equals(1));
        expect(state1.streak, equals(1));
        final due1 = DateTime.parse(state1.nextReviewDue);
        expect(due1.difference(now).inDays, greaterThanOrEqualTo(1));

        // 2. 迟疑辨析：听 2 次，熟练度保持，排期仅 1 天（提高频次）
        final fam2 = store.recordQuizResult(
          'refactoring',
          isCorrect: true,
          playCount: 2,
        );
        expect(fam2, equals(AuditoryFamiliarity.hesitant));
        final state2 = store.memoryStateFor('refactoring');
        expect(state2.proficiency, equals(0));
        final due2 = DateTime.parse(state2.nextReviewDue);
        expect(due2.difference(now).inDays, equals(1));

        // 3. 辨音吃力：听 3 次答对，streak 归零，排期当天
        final fam3 = store.recordQuizResult(
          'latency',
          isCorrect: true,
          playCount: 3,
        );
        expect(fam3, equals(AuditoryFamiliarity.struggling));
        final state3 = store.memoryStateFor('latency');
        expect(state3.streak, equals(0));
        final due3 = DateTime.parse(state3.nextReviewDue);
        expect(due3.difference(now).inHours, lessThanOrEqualTo(1));

        // 4. 辨音盲区：选错，熟练度降级，streak 归零，排期当天
        final fam4 = store.recordQuizResult(
          'sharding',
          isCorrect: false,
          playCount: 1,
        );
        expect(fam4, equals(AuditoryFamiliarity.lapse));
        final state4 = store.memoryStateFor('sharding');
        expect(state4.proficiency, equals(0));
        expect(state4.streak, equals(0));
        expect(state4.mistakeCount, equals(1));
      });

      test('会话控制器末尾生疏词追加加测与防死循环机制', () {
        final session = VocabularySessionController.create(
          mode: VocabularyPracticeMode.quiz4Choice,
          words: ['governance', 'refactoring'],
          index: index,
          studyStore: store,
        );

        expect(session.totalCount, equals(2));
        expect(session.pendingReinforceCount, equals(0));

        // 第 1 题：选错 (lapse)，进入待加测队列
        final item1 = session.currentItem!;
        final wrongIndex = (item1.correctChoiceIndex + 1) % item1.choices.length;
        session.selectChoice(wrongIndex);
        expect(item1.familiarity, equals(AuditoryFamiliarity.lapse));
        expect(session.pendingReinforceCount, equals(1));

        // 切到第 2 题
        expect(session.next(), isTrue);
        expect(session.currentIndex, equals(1));

        // 第 2 题：听 1 次且秒选答对 (instant)
        final item2 = session.currentItem!;
        item2.playCount = 1;
        item2.displayedAt = DateTime.now().subtract(const Duration(seconds: 1));
        session.selectChoice(item2.correctChoiceIndex);
        expect(item2.familiarity, equals(AuditoryFamiliarity.instant));
        // pending 数量仍为 1（仅治理词治理）
        expect(session.pendingReinforceCount, equals(1));

        // 原题目已到最后一题，next() 应自动将 governance 作为加测题目追加到 items 末尾
        expect(session.isLast, isTrue);
        final advanced = session.next();
        expect(advanced, isTrue);
        expect(session.totalCount, equals(3));
        expect(session.currentIndex, equals(2));
        expect(session.pendingReinforceCount, equals(0));

        // 验证当前加测题
        final reinforceItem = session.currentItem!;
        expect(reinforceItem.word, equals('governance'));
        expect(reinforceItem.isReinforcement, isTrue);

        // 加测题目即便答错，也不会死循环二次追加
        final reinforceWrongIdx = (reinforceItem.correctChoiceIndex + 1) % reinforceItem.choices.length;
        session.selectChoice(reinforceWrongIdx);
        expect(session.pendingReinforceCount, equals(0));

        // 此时 next() 应真正完成会话
        expect(session.isLast, isTrue);
        final finished = session.next();
        expect(finished, isFalse);
        expect(session.isCompleted, isTrue);
      });

      testWidgets('盲听测验 UI 交互：作答后呈现熟悉度诊断微章与加测条', (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final session = VocabularySessionController.create(
          mode: VocabularyPracticeMode.quiz4Choice,
          words: ['governance'],
          index: index,
          studyStore: store,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      VocabularyPracticeDialog.show(
                        ctx,
                        session: session,
                      );
                    },
                    child: const Text('开始测验'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('开始测验'));
        await tester.pumpAndSettle();

        // 初始未作答，不应有熟悉度诊断微章
        expect(find.byKey(const ValueKey('vocab-familiarity-diagnosis-banner')), findsNothing);

        // 点击正确选项作答
        final item = session.currentItem!;
        await tester.tap(find.byKey(ValueKey('quiz-choice-${item.correctChoiceIndex}')));
        await tester.pumpAndSettle();

        // 作答后，熟悉度诊断卡片展示
        expect(find.byKey(const ValueKey('vocab-familiarity-diagnosis-banner')), findsOneWidget);
        expect(find.textContaining('听音 1 次'), findsOneWidget);
      });
    });

    group('词典真人发音优先与多级弹性降级发音体系', () {
      test('isSingleEnglishWord 单词与长句识别准确性', () {
        expect(VocabularyStudyStore.isSingleEnglishWord('governance'), isTrue);
        expect(VocabularyStudyStore.isSingleEnglishWord('idempotency'), isTrue);
        expect(VocabularyStudyStore.isSingleEnglishWord('multi-tenant'), isTrue);
        expect(VocabularyStudyStore.isSingleEnglishWord('user_service'), isTrue);

        expect(VocabularyStudyStore.isSingleEnglishWord(''), isFalse);
        expect(VocabularyStudyStore.isSingleEnglishWord('   '), isFalse);
        expect(VocabularyStudyStore.isSingleEnglishWord('We need governance'), isFalse);
        expect(VocabularyStudyStore.isSingleEnglishWord('hello world'), isFalse);
      });

      test('口音偏好切换与持久化（默认美音，支持英音）', () {
        expect(store.accent, equals(VocabularyAccent.us));

        store.setAccent(VocabularyAccent.uk);
        expect(store.accent, equals(VocabularyAccent.uk));

        // 重新从磁盘读取，验证持久化生效
        final reloaded = VocabularyStudyStore(baseDir: tmpDir);
        expect(reloaded.accent, equals(VocabularyAccent.uk));

        reloaded.setAccent(VocabularyAccent.us);
        expect(reloaded.accent, equals(VocabularyAccent.us));
      });

      test('发音三级降级链路：词典真人原声优先 ➔ 本机离线语音 ➔ AI TTS 终极兜底', () async {
        var dictCalled = 0;
        var nativeCalled = 0;

        // 1. 词典音频成功
        final storeWithDict = VocabularyStudyStore(
          baseDir: tmpDir,
          dictionaryAudioFetcher: (word, accent) async {
            dictCalled++;
            return Uint8List.fromList([0x49, 0x44, 0x33, 0x01, 0x02, 0x03]); // mock MP3 header
          },
          nativeSpeechSynthesizer: (word, accent) async {
            nativeCalled++;
            return null;
          },
        );

        final file1 = await storeWithDict.synthesizeOrGetTtsFile('governance');
        expect(await file1.exists(), isTrue);
        expect(dictCalled, equals(1));
        expect(nativeCalled, equals(0)); // 本机离线未被调用

        // 2. 词典失败，自动降级至本机离线发音
        final storeWithNative = VocabularyStudyStore(
          baseDir: tmpDir,
          dictionaryAudioFetcher: (word, accent) async => null,
          nativeSpeechSynthesizer: (word, accent) async {
            nativeCalled++;
            return Uint8List.fromList([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]); // mock M4A
          },
        );

        final file2 = await storeWithNative.synthesizeOrGetTtsFile('latency', forceRegenerate: true);
        expect(await file2.exists(), isTrue);
        expect(nativeCalled, equals(1));

        // 3. 词典与本机均失败，回退到 AI TTS 兜底
        var aiTtsCalled = 0;
        final fakeAiEngine = _MockAiTtsEngine(() {
          aiTtsCalled++;
        });

        final storeWithAi = VocabularyStudyStore(
          baseDir: tmpDir,
          ttsEngine: fakeAiEngine,
          dictionaryAudioFetcher: (word, accent) async => null,
          nativeSpeechSynthesizer: (word, accent) async => null,
        );

        final file3 = await storeWithAi.synthesizeOrGetTtsFile('sharding', forceRegenerate: true);
        expect(await file3.exists(), isTrue);
        expect(aiTtsCalled, equals(1));
      });

      testWidgets('VocabularyPracticeDialog 支持发音口音切换交互', (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final session = VocabularySessionController.create(
          mode: VocabularyPracticeMode.study,
          words: ['governance'],
          index: index,
          studyStore: store,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      VocabularyPracticeDialog.show(ctx, session: session);
                    },
                    child: const Text('学习'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('学习'));
        await tester.pumpAndSettle();

        // 验证当前显示默认美音
        expect(find.byKey(const ValueKey('vocab-practice-accent-toggle-btn')), findsOneWidget);
        expect(find.text('美音'), findsOneWidget);

        // 点击切换为英音
        await tester.tap(find.byKey(const ValueKey('vocab-practice-accent-toggle-btn')));
        await tester.pumpAndSettle();

        expect(store.accent, equals(VocabularyAccent.uk));
        expect(find.text('英音'), findsOneWidget);
      });
    });
  });
}

class _MockAiTtsEngine implements TtsEngine {
  final VoidCallback onSynthesize;
  _MockAiTtsEngine(this.onSynthesize);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    onSynthesize();
    return Uint8List.fromList([0xFF, 0xFB, 0x90, 0x64, 0x00, 0x00]);
  }
}
