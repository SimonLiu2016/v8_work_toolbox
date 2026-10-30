import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_audio_player.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_hot_key_service.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_host.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_player_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_progress_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/resume_recorder.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/term_highlighter.dart';

class _TestPlayer implements ListeningAudioPlayer {
  final pos = StreamController<Duration>.broadcast();
  final dur = StreamController<Duration>.broadcast();
  final done = StreamController<void>.broadcast();
  final state = StreamController<PlayerState>.broadcast();
  Duration? lastSeek;

  @override
  Stream<Duration> get onPositionChanged => pos.stream;
  @override
  Stream<Duration> get onDurationChanged => dur.stream;
  @override
  Stream<void> get onPlayerComplete => done.stream;
  @override
  Stream<PlayerState> get onPlayerStateChanged => state.stream;

  @override
  Future<void> playFile(String path) async {
    state.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async => state.add(PlayerState.paused);

  @override
  Future<void> resume() async => state.add(PlayerState.playing);

  @override
  Future<void> stop() async => state.add(PlayerState.stopped);

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    pos.add(position);
  }

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Future<void> release() async {}
}

Clip _makeClip(String id, MeetingScene scene, {int durationMs = 100000}) {
  return Clip(
    id: id,
    scene: scene,
    title: id,
    audioPath: '$id.mp3',
    durationMs: durationMs,
    turns: const [],
    source: const ClipSource(
      sourceId: 'rehearsal',
      site: 'Local',
      pageUrl: '',
      column: 'Rehearsal',
    ),
  );
}

void main() {
  group('ListeningProgressStore 断点记忆', () {
    late Directory tmp;
    late ListeningProgressStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('progress_test');
      store = ListeningProgressStore(File(p.join(tmp.path, 'progress.json')));
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('文件不存在时返回空表（不抛异常）', () async {
      expect(await store.loadAll(), isEmpty);
    });

    test('写入后可读回', () async {
      await store.save('standup', 'clip-a', 12345);
      final p = await store.load('standup');
      expect(p, isNotNull);
      expect(p!.clipId, 'clip-a');
      expect(p.offsetMs, 12345);
    });

    test('同一场景重复写入覆盖旧值', () async {
      await store.save('standup', 'clip-a', 100);
      await store.save('standup', 'clip-b', 200);
      final p = await store.load('standup');
      expect(p!.clipId, 'clip-b');
      expect(p.offsetMs, 200);
    });

    test('不同场景互不覆盖', () async {
      await store.save('standup', 'clip-a', 100);
      await store.save('incident', 'clip-b', 200);
      expect((await store.load('standup'))!.clipId, 'clip-a');
      expect((await store.load('incident'))!.clipId, 'clip-b');
    });

    test('清除某场景后其它场景仍在', () async {
      await store.save('standup', 'clip-a', 100);
      await store.save('incident', 'clip-b', 200);
      await store.clear('standup');
      expect(await store.load('standup'), isNull);
      expect(await store.load('incident'), isNotNull);
    });

    test('文件损坏时降级为空表', () async {
      await File(p.join(tmp.path, 'progress.json')).writeAsString('{ 这不是 json');
      expect(await store.loadAll(), isEmpty);
      expect((await store.loadState()).isEmpty, isTrue);
    });

    test('v2 结构读写往返（items / scenes / lastPlayed / completedAt）', () async {
      final now = DateTime.utc(2026, 10, 24, 12, 0, 0);
      final doneAt = DateTime.utc(2026, 10, 24, 12, 30, 0);
      final state = ListeningProgressState(
        items: {
          'rm_1': ItemProgress(
            clipId: 'rm_1',
            offsetMs: 760000,
            durationMs: 2890000,
            updatedAt: now,
          ),
          'rehearsal_a': ItemProgress(
            clipId: 'rehearsal_a',
            offsetMs: 0,
            durationMs: 1800000,
            updatedAt: doneAt,
            completedAt: doneAt,
          ),
        },
        scenes: {
          'real-meeting': SceneProgress(
            sceneId: 'real-meeting',
            clipId: 'rm_1',
            updatedAt: now,
          ),
        },
        lastPlayed: LastPlayedPointer(clipId: 'rm_1', updatedAt: now),
      );
      await store.saveState(state);

      final loaded = await store.loadState();
      expect(loaded.items['rm_1']?.offsetMs, 760000);
      expect(loaded.items['rm_1']?.durationMs, 2890000);
      expect(loaded.items['rm_1']?.isCompleted, isFalse);
      expect(loaded.items['rehearsal_a']?.isCompleted, isTrue);
      expect(loaded.items['rehearsal_a']?.ratio, 1.0);
      expect(loaded.scenes['real-meeting']?.clipId, 'rm_1');
      expect(loaded.lastPlayed?.clipId, 'rm_1');
    });

    test('v1 旧格式文件自动迁移为 v2，lastPlayed 取最新时间', () async {
      final v1Text = '''
{
  "standup": {
    "sceneId": "standup",
    "clipId": "clip_old",
    "offsetMs": 5000,
    "updatedAt": "2026-10-20T10:00:00.000Z"
  },
  "incident": {
    "sceneId": "incident",
    "clipId": "clip_new",
    "offsetMs": 42000,
    "updatedAt": "2026-10-22T15:30:00.000Z"
  }
}
''';
      await File(p.join(tmp.path, 'progress.json')).writeAsString(v1Text);

      final migrated = await store.loadState();
      expect(migrated.scenes['standup']?.clipId, 'clip_old');
      expect(migrated.scenes['incident']?.clipId, 'clip_new');
      expect(migrated.items['clip_old']?.offsetMs, 5000);
      expect(migrated.items['clip_new']?.offsetMs, 42000);
      expect(migrated.lastPlayed?.clipId, 'clip_new');
    });

    test('并发 updateState 串行化，不丢失任何一次写入', () async {
      await Future.wait([
        for (var i = 0; i < 10; i++)
          store.save('scene_$i', 'clip_$i', i * 1000, durationMs: 60000),
      ]);
      final state = await store.loadState();
      expect(state.items.length, 10);
      expect(state.scenes.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(state.items['clip_$i']?.offsetMs, i * 1000);
      }
    });
  });

  group('TermHighlighter 术语识别', () {
    test('识别常见 IT 术语', () {
      final terms = TermHighlighter.extractTerms(
          'The rollback is blocked by the flaky test in the pipeline.');
      final lower = terms.map((t) => t.toLowerCase()).toList();
      expect(lower, contains('rollback'));
      expect(lower, contains('blocked'));
      expect(lower, contains('flaky test'));
      expect(lower, contains('pipeline'));
    });

    test('不把普通词当术语', () {
      final terms = TermHighlighter.extractTerms('I think we should go home now.');
      expect(terms, isEmpty);
    });

    test('不发生子串误报（latest 不含 test）', () {
      final terms = TermHighlighter.extractTerms('Check the latest build.');
      final lower = terms.map((t) => t.toLowerCase()).toList();
      expect(lower, isNot(contains('test')));
    });

    test('大写开头的术语也能识别', () {
      final terms = TermHighlighter.extractTerms('We need a Hotfix and a Rollback.');
      final lower = terms.map((t) => t.toLowerCase()).toList();
      expect(lower, contains('hotfix'));
      expect(lower, contains('rollback'));
    });
  });

  group('ResumeRecorder 记录器与已听完判定', () {
    late Directory tmp;
    late ListeningProgressStore store;
    late DateTime now;
    late ResumeRecorder recorder;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('resume_recorder_test');
      store = ListeningProgressStore(File(p.join(tmp.path, 'progress.json')));
      now = DateTime.utc(2026, 10, 24, 12, 0, 0);
      recorder = ResumeRecorder(
        store: store,
        throttleInterval: const Duration(seconds: 5),
        clock: () => now,
      );
      await recorder.init();
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('周期节流：5 秒内只更新内存，满 5 秒或 flushNow 时落盘', () async {
      final clip = _makeClip('rm_1', MeetingScene.realMeeting, durationMs: 600000);
      await recorder.onClipStarted(clip, initialOffsetMs: 0);

      // 2 秒后心跳：内存已更新，但磁盘还是 0
      now = now.add(const Duration(seconds: 2));
      await recorder.onPositionTick(clip, 2000);
      expect(recorder.offsetFor('rm_1'), 2000);
      expect((await store.loadState()).items['rm_1']?.offsetMs, 0);

      // 满 5 秒后心跳：自动落盘
      now = now.add(const Duration(seconds: 3));
      await recorder.onPositionTick(clip, 5000);
      expect((await store.loadState()).items['rm_1']?.offsetMs, 5000);

      // 6 秒后心跳 + 立即 flushNow：立刻落盘
      now = now.add(const Duration(seconds: 1));
      await recorder.onPositionTick(clip, 6000);
      await recorder.flushNow();
      expect((await store.loadState()).items['rm_1']?.offsetMs, 6000);
    });

    test('已听完判定：剩余 < 5 秒或 ≥ 98% 时 offset 归零并记 completedAt，重新播放清除', () async {
      // 100 秒音频：播到 96 秒（剩余 4 秒 < 5 秒）视为已听完
      final clipA = _makeClip('clip_a', MeetingScene.standup, durationMs: 100000);
      await recorder.flushNow(clip: clipA, offsetMs: 96000, durationMs: 100000);
      expect(recorder.progressFor('clip_a')?.isCompleted, isTrue);
      expect(recorder.offsetFor('clip_a'), 0);

      // 1000 秒音频：播到 985 秒（剩余 15 秒，但已达 98.5% ≥ 98%）视为已听完
      final clipB =
          _makeClip('clip_b', MeetingScene.realMeeting, durationMs: 1000000);
      await recorder.flushNow(clip: clipB, offsetMs: 985000, durationMs: 1000000);
      expect(recorder.progressFor('clip_b')?.isCompleted, isTrue);
      expect(recorder.offsetFor('clip_b'), 0);

      // 重新开始播放 clipA 后清除 completedAt
      await recorder.onClipStarted(clipA, initialOffsetMs: 0);
      expect(recorder.progressFor('clip_a')?.isCompleted, isFalse);
    });

    test('偏移超出新时长时自动归零', () async {
      final clip = _makeClip('rehearsal_1', MeetingScene.rehearsal, durationMs: 120000);
      await recorder.flushNow(clip: clip, offsetMs: 80000, durationMs: 120000);
      expect(recorder.offsetFor('rehearsal_1', currentDurationMs: 120000), 80000);
      // 重新合成后时长缩短为 60 秒，80 秒超出新时长 → 从 0 开始
      expect(recorder.offsetFor('rehearsal_1', currentDurationMs: 60000), 0);
    });
  });

  group('ListeningPlayerController 断点集成', () {
    late Directory tmp;
    late ListeningProgressStore store;
    late _TestPlayer fakePlayer;
    late ListeningPlayerController controller;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('controller_resume_test');
      store = ListeningProgressStore(File(p.join(tmp.path, 'progress.json')));
      fakePlayer = _TestPlayer();
      controller = ListeningPlayerController(
        player: fakePlayer,
        recorder: ResumeRecorder(store: store),
      );
      await controller.recorder.init();
      ListeningHost.instance.setControllerForTesting(controller);
    });

    tearDown(() async {
      ListeningHost.instance.setControllerForTesting(null);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('全局热键暂停后立即落盘，重开从暂停位置继续', () async {
      final clip = _makeClip('rm_x', MeetingScene.realMeeting, durationMs: 1800000);
      await controller.play(clip, filePath: '/tmp/rm_x.mp3');
      fakePlayer.pos.add(const Duration(seconds: 760));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 通过全局热键暂停
      await ListeningHost.instance.handleHotKeyAction(ListeningHotKeyAction.toggle);
      expect(controller.isPlaying, isFalse);

      // 磁盘已保存 760000ms 及 lastPlayed
      final diskState = await store.loadState();
      expect(diskState.items['rm_x']?.offsetMs, 760000);
      expect(diskState.lastPlayed?.clipId, 'rm_x');

      // 模拟重开后再次播放 rm_x，自动 seek 到 760000ms
      final freshPlayer = _TestPlayer();
      final freshController = ListeningPlayerController(
        player: freshPlayer,
        recorder: ResumeRecorder(store: store),
      );
      await freshController.recorder.init();
      await freshController.play(clip, filePath: '/tmp/rm_x.mp3');
      expect(freshPlayer.lastSeek, const Duration(milliseconds: 760000));
    });

    test('切换内容时旧内容位置被保存，多场排练进度互不覆盖', () async {
      final rehA = _makeClip('rehearsal_a', MeetingScene.rehearsal, durationMs: 1800000);
      final rehB = _makeClip('rehearsal_b', MeetingScene.rehearsal, durationMs: 1800000);

      // 排练 A 听到 10 分钟（600000ms）
      await controller.play(rehA, filePath: '/tmp/a.mp3');
      fakePlayer.pos.add(const Duration(minutes: 10));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 直接切换到排练 B 听到 3 分钟（180000ms）
      await controller.play(rehB, filePath: '/tmp/b.mp3');
      fakePlayer.pos.add(const Duration(minutes: 3));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.pause();

      // 验证 A 与 B 的记录互不覆盖
      final diskState = await store.loadState();
      expect(diskState.items['rehearsal_a']?.offsetMs, 600000);
      expect(diskState.items['rehearsal_b']?.offsetMs, 180000);

      // 再回到排练 A，从 10 分钟处继续
      await controller.play(rehA, filePath: '/tmp/a.mp3');
      expect(fakePlayer.lastSeek, const Duration(minutes: 10));
    });
  });
}
