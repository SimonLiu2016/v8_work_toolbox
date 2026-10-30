
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/source_sync_state.dart';

void main() {
  late Directory tmp;
  late SourceSyncStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sync_state_test');
    store = SourceSyncStore(File(p.join(tmp.path, 'sync_state.json')));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('SourceSyncStore 同步状态读写', () {
    test('文件不存在时返回空表', () async {
      expect(await store.loadAll(), isEmpty);
    });

    test('写入后可读回', () async {
      await store.save(SourceSyncState(
        sourceId: 'coderslingo',
        columnSlug: 'standup-dialogues',
        lastSyncedAt: _time,
        siteChangeToken: 'tok',
        contentHash: 'h1',
      ));
      final s = await store.load('coderslingo', 'standup-dialogues');
      expect(s, isNotNull);
      expect(s!.contentHash, 'h1');
      expect(s.siteChangeToken, 'tok');
      expect(s.hasSynced, isTrue);
    });

    test('同栏目重复写入覆盖旧值', () async {
      await store.save(SourceSyncState(
          sourceId: 'c', columnSlug: 'col', lastSyncedAt: _time, contentHash: 'a'));
      await store.save(SourceSyncState(
          sourceId: 'c', columnSlug: 'col', lastSyncedAt: _time, contentHash: 'b'));
      expect((await store.load('c', 'col'))!.contentHash, 'b');
    });

    test('不同来源的同栏目互不覆盖', () async {
      await store.save(SourceSyncState(
          sourceId: 'a', columnSlug: 'col', lastSyncedAt: _time, contentHash: 'x'));
      await store.save(SourceSyncState(
          sourceId: 'b', columnSlug: 'col', lastSyncedAt: _time, contentHash: 'y'));
      expect((await store.load('a', 'col'))!.contentHash, 'x');
      expect((await store.load('b', 'col'))!.contentHash, 'y');
    });

    test('记录失败累加次数并保留原因', () async {
      await store.recordFailure('c', 'col', '网络不可达');
      await store.recordFailure('c', 'col', '又超时');
      final s = await store.load('c', 'col');
      expect(s!.failureCount, 2);
      expect(s.lastFailure, '又超时');
    });

    test('文件损坏时降级为空表，不抛异常', () async {
      await File(p.join(tmp.path, 'sync_state.json')).writeAsString('{ 坏 json');
      expect(await store.loadAll(), isEmpty);
    });

    test('状态在重新构造 store 后仍在（持久化）', () async {
      await store.save(SourceSyncState(
          sourceId: 'c', columnSlug: 'col', lastSyncedAt: _time, contentHash: 'h'));
      final reopened = SourceSyncStore(File(p.join(tmp.path, 'sync_state.json')));
      expect((await reopened.load('c', 'col'))!.contentHash, 'h');
    });
  });

  group('SourceSyncState 变更判定', () {
    test('站点级标识变化即视为变更', () {
      const s = SourceSyncState(
          sourceId: 'c', columnSlug: 'col', siteChangeToken: 'old');
      expect(s.siteChanged('new'), isTrue);
      expect(s.siteChanged('old'), isFalse);
    });

    test('当前标识为 null 时不判定为变更（保守全量）', () {
      const s = SourceSyncState(
          sourceId: 'c', columnSlug: 'col', siteChangeToken: 'old');
      expect(s.siteChanged(null), isFalse);
    });

    test('内容哈希变化即视为变更', () {
      const s =
          SourceSyncState(sourceId: 'c', columnSlug: 'col', contentHash: 'h1');
      expect(s.contentChanged('h2'), isTrue);
      expect(s.contentChanged('h1'), isFalse);
    });
  });

  group('computeContentHash 内容哈希', () {
    List<SpeakerTurn> turns(String text) => [
          SpeakerTurn(
            speaker: 'Lena',
            role: 'Scrum Master',
            rawText: text,
            synthesisText: text,
            voice: 'step_boy',
          ),
        ];

    test('相同内容得到相同哈希', () {
      expect(computeContentHash(turns('Hello there.')),
          computeContentHash(turns('Hello there.')));
    });

    test('文本变化得到不同哈希', () {
      expect(computeContentHash(turns('Hello there.')),
          isNot(computeContentHash(turns('Hello there!'))));
    });

    test('说话人变化得到不同哈希', () {
      final a = [
        SpeakerTurn(
            speaker: 'Lena',
            role: 'SM',
            rawText: 'hi',
            synthesisText: 'hi',
            voice: 'v'),
      ];
      final b = [
        SpeakerTurn(
            speaker: 'Alex',
            role: 'SM',
            rawText: 'hi',
            synthesisText: 'hi',
            voice: 'v'),
      ];
      expect(computeContentHash(a), isNot(computeContentHash(b)));
    });

    test('空白差异不算内容变化', () {
      expect(computeContentHash(turns('Hello   there.')),
          computeContentHash(turns('Hello there.')));
    });
  });
}

final _time = DateTime.utc(2026, 10, 22);
