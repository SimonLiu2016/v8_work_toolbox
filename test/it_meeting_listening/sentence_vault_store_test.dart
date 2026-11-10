import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/sentence_vault_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/sentence_vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File vaultFile;
  late SentenceVaultStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sentence_vault_test');
    vaultFile = File(p.join(tmp.path, 'sentence_vault.json'));
    store = SentenceVaultStore(vaultFile);
    await store.init();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('SentenceVaultStore 增删改查与落盘自愈', () {
    test('初始为空，添加条目后原子写入文件且新实例能重载', () async {
      expect(store.totalCount, 0);
      expect(store.isSaved('clip_1', 2), isFalse);

      final s1 = VaultSentence(
        id: 's1',
        clipId: 'clip_1',
        meetingTitle: 'Daily Standup',
        scene: MeetingScene.realMeeting,
        turnIndex: 2,
        speaker: 'Dev Dave',
        text: 'The query execution plan took 5 seconds before indexing.',
        audioFilePath: '/tmp/clip_1.mp3',
        startMs: 4000,
        endMs: 9000,
        tags: const [VaultTags.complexClause, VaultTags.connectedSpeech],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await store.addOrUpdate(s1);
      expect(store.totalCount, 1);
      expect(store.isSaved('clip_1', 2), isTrue);
      expect(store.find('clip_1', 2)?.id, 's1');
      expect(store.unmasteredCount, 1);
      expect(store.masteredCount, 0);

      // 新建实例读取同一文件
      final store2 = SentenceVaultStore(vaultFile);
      await store2.init();
      expect(store2.totalCount, 1);
      final loaded = store2.find('clip_1', 2);
      expect(loaded?.speaker, 'Dev Dave');
      expect(loaded?.tags.contains(VaultTags.complexClause), isTrue);
    });

    test('切换掌握状态与复盘练习计数递增', () async {
      final s = VaultSentence(
        id: 's_review',
        clipId: 'clip_2',
        meetingTitle: 'Sprint Retro',
        scene: MeetingScene.realMeeting,
        turnIndex: 0,
        speaker: 'Scrum Master',
        text: 'We should keep in mind that the timeline is strict.',
        startMs: 0,
        endMs: 3000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await store.addOrUpdate(s);

      expect(store.masteredCount, 0);
      await store.toggleMastered('s_review');
      expect(store.masteredCount, 1);
      expect(store.unmasteredCount, 0);

      await store.incrementReviewCount('s_review');
      await store.incrementReviewCount('s_review');
      expect(store.find('clip_2', 0)?.reviewCount, 2);

      await store.remove('s_review');
      expect(store.totalCount, 0);
    });

    test('多维度过滤筛选测试', () async {
      final s1 = VaultSentence(
        id: 's1',
        clipId: 'c1',
        meetingTitle: 'Backend Architecture',
        scene: MeetingScene.realMeeting,
        turnIndex: 0,
        speaker: 'Alice',
        text: 'We decoupled the monolithic service into small components.',
        startMs: 0,
        endMs: 4000,
        tags: const [VaultTags.complexClause],
        mastered: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        updatedAt: DateTime.now(),
      );

      final s2 = VaultSentence(
        id: 's2',
        clipId: 'c1',
        meetingTitle: 'Frontend Performance',
        scene: MeetingScene.realMeeting,
        turnIndex: 1,
        speaker: 'Bob',
        text: 'First of all, bundle size was reduced by half.',
        startMs: 4000,
        endMs: 8000,
        tags: const [VaultTags.connectedSpeech],
        mastered: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await store.addOrUpdate(s1);
      await store.addOrUpdate(s2);

      // 按已掌握过滤
      final mastered = store.filter(mastered: true);
      expect(mastered.length, 1);
      expect(mastered.first.id, 's2');

      // 按标签过滤
      final tagFiltered = store.filter(tag: VaultTags.complexClause);
      expect(tagFiltered.length, 1);
      expect(tagFiltered.first.id, 's1');

      // 按关键字搜索 (内容、会议名或发言人)
      final textSearch = store.filter(query: 'monolithic');
      expect(textSearch.length, 1);
      expect(textSearch.first.id, 's1');

      final speakerSearch = store.filter(query: 'Bob');
      expect(speakerSearch.length, 1);
      expect(speakerSearch.first.id, 's2');
    });

    test('损坏 JSON 文件能优雅自愈为空列表不导致崩溃', () async {
      await vaultFile.writeAsString('INVALID_JSON{{{broken');
      final corruptedStore = SentenceVaultStore(vaultFile);
      await corruptedStore.init();
      expect(corruptedStore.totalCount, 0);
    });
  });
}
