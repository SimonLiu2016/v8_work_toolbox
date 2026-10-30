import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/rehearsal_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_audio_player.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_host.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_player_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meetings_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/task_tracker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/it_meeting_listening_page.dart';

/// 假播放器：`audioplayers` 在 flutter test 里没有平台实现，用此替身驱动。
class _FakePlayer implements ListeningAudioPlayer {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _done = StreamController<void>.broadcast();
  final _state = StreamController<PlayerState>.broadcast();
  String? playingPath;

  @override
  Stream<Duration> get onPositionChanged => _pos.stream;

  @override
  Stream<Duration> get onDurationChanged => _dur.stream;

  @override
  Stream<void> get onPlayerComplete => _done.stream;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _state.stream;

  @override
  Future<void> playFile(String path) async {
    playingPath = path;
    _dur.add(const Duration(seconds: 46));
    _state.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async => _state.add(PlayerState.paused);

  @override
  Future<void> resume() async => _state.add(PlayerState.playing);

  @override
  Future<void> stop() async => _state.add(PlayerState.stopped);

  @override
  Future<void> seek(Duration position) async => _pos.add(position);

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Future<void> release() async {}
}

/// 让页面的磁盘异步（索引载入）落地。
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  });
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;
  late _FakePlayer fake;

  setUp(() async {
    await AppPaths.init();
    tmp = await Directory.systemTemp.createTemp('it_listening_page_test');
    AppPaths.overrideRootForTesting(tmp);
    fake = _FakePlayer();
    ListeningHost.instance.setControllerForTesting(
      ListeningPlayerController(player: fake),
    );
    ListeningHost.instance.setIndexForTesting(const ClipIndex());
  });

  tearDown(() async {
    ListeningHost.instance.setControllerForTesting(null);
    ListeningHost.instance.setIndexForTesting(const ClipIndex());
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  void seedPublicIndex({bool withAudioFile = false}) {
    if (withAudioFile) {
      final audioFile =
          File('${AppPaths.itMeetingListeningDir.path}/standup_demo_0_s0.mp3');
      audioFile.parent.createSync(recursive: true);
      audioFile.writeAsBytesSync(const [1, 2, 3, 4]);
    }
    final clip = Clip(
      id: 'standup_demo_0_s0',
      scene: MeetingScene.standup,
      title: 'Morning standup',
      summary: 'Daily sync on API blocker and sprint progress.',
      audioPath: 'standup_demo_0_s0.mp3',
      durationMs: 46000,
      turns: const [
        SpeakerTurn(
          speaker: 'Lena',
          role: 'Scrum Master',
          rawText: "Good morning. I'm blocked on the API spec.",
          synthesisText: "Good morning. I'm blocked on the API spec.",
          voice: 'step_boy',
          startMs: 0,
          endMs: 46000,
        ),
      ],
      source: const ClipSource(
        sourceId: 'coderslingo',
        site: 'CoderSlingo',
        pageUrl: 'https://coderslingo.com/',
        column: 'Stand-up Meeting Dialogues',
      ),
    );
    ListeningHost.instance.setIndexForTesting(
      ClipIndex(version: 1, clips: [clip]),
    );
  }

  Widget app() => MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ItMeetingListeningPage(),
      );

  testWidgets('三类内容全空时展示三张引导卡片且顶栏无溢出', (tester) async {
    ListeningHost.instance.setIndexForTesting(const ClipIndex());
    await tester.pumpWidget(app());
    await _settle(tester);

    expect(find.byKey(const ValueKey('onboarding-empty-state')), findsOneWidget);
    expect(find.text('随便听听'), findsOneWidget);
    expect(find.text('准备会议'), findsOneWidget);
    expect(find.text('复听会议'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-new-menu-btn')), findsOneWidget);
  });

  testWidgets('场景列表只呈现会议场景，不含应试/日常类目', (tester) async {
    seedPublicIndex();
    await tester.pumpWidget(app());
    await _settle(tester);

    // 有素材的场景出现在侧栏
    expect(find.text('站会'), findsWidgets);
    // 没素材的场景不占位置
    expect(find.text('圆桌技术讨论'), findsNothing);
    // 明确不应出现的通用英语类目
    for (final forbidden in ['雅思', '四级', '六级', '日常对话', '口语打卡']) {
      expect(
        find.text(forbidden),
        findsNothing,
        reason: '不应出现通用英语类目 "$forbidden"',
      );
    }
  });

  testWidgets('片段显示标题与摘要，默认不展示逐句文稿，点精听按钮打开右侧抽屉', (tester) async {
    seedPublicIndex(withAudioFile: true);
    await tester.pumpWidget(app());
    await _settle(tester);

    expect(find.text('Morning standup'), findsWidgets);
    expect(
      find.text('Daily sync on API blocker and sprint progress.'),
      findsOneWidget,
    );
    // 逐句文稿默认不显示
    expect(find.byKey(const ValueKey('transcript-drawer')), findsNothing);
    expect(
      find.textContaining("Good morning. I'm blocked", findRichText: true),
      findsNothing,
    );

    // 点选该片段开始播放，精听抽屉仍保持收起
    await tester.tap(find.text('Morning standup').first);
    await _settle(tester);
    expect(find.byKey(const ValueKey('transcript-drawer')), findsNothing);

    // 点底部播放条的「精听」按钮展开右侧抽屉
    await tester.tap(find.byKey(const ValueKey('player-bar-transcript-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transcript-drawer')), findsOneWidget);
    expect(
      find.textContaining("Good morning. I'm blocked", findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('播放中切换左侧分区不中断底部播放条，点击播放条标题跳回原分区', (tester) async {
    seedPublicIndex(withAudioFile: true);
    await tester.pumpWidget(app());
    await _settle(tester);

    // 播放公开素材「Morning standup」
    await tester.tap(find.text('Morning standup').first);
    await _settle(tester);
    expect(ListeningHost.instance.controller.clip?.id, 'standup_demo_0_s0');

    // 切换到「真实会议」分区
    await tester.tap(find.byKey(const ValueKey('nav-real-meetings')));
    await tester.pumpAndSettle();
    expect(find.text('还没有真实会议'), findsOneWidget);
    // 底部播放条仍持有 Morning standup
    expect(ListeningHost.instance.controller.clip?.id, 'standup_demo_0_s0');

    // 点击底部播放条左侧标题区域，跳回「站会」公开素材场景
    await tester.tap(find.byKey(const ValueKey('player-bar-title-jump')));
    await tester.pumpAndSettle();
    expect(
      find.text('Daily sync on API blocker and sprint progress.'),
      findsOneWidget,
    );
  });

  testWidgets('多场排练与讲稿编辑器：修改讲稿触发未保存标记，切换时弹出未保存确认，保存后标记剧本已过期',
      (tester) async {
    await tester.runAsync(() async {
      final store = RehearsalStore();
      final mat = RehearsalMaterial(
        id: 'mat_1',
        title: 'Q4 Architecture Review',
        sourcePath: '/tmp/q4.md',
        fileName: 'q4.md',
        text: 'Architecture review details for Q4.',
        importedAt: DateTime(2026, 10, 24, 10, 0),
        targetMinutes: 30,
      );
      final draft = SpeechDraft(
        id: 'draft_v1',
        materialId: 'mat_1',
        title: 'Q4 Architecture Speech',
        sections: const [
          DraftSection(title: 'Context', body: 'We are scaling the gateway.'),
          DraftSection(title: 'Plan', body: 'Phase 1 starts next week.'),
          DraftSection(title: 'Risks', body: 'Latency under peak load.'),
        ],
        generatedAt: DateTime(2026, 10, 24, 10, 5),
      );
      final script = MeetingScript(
        id: 'script_1',
        materialId: 'mat_1',
        draftId: 'draft_v1',
        title: 'Q4 Architecture Rehearsal',
        targetMinutes: 30,
        turns: const [
          ScriptTurn(
            role: RehearsalRole.xiaofeng,
            text: 'Welcome everyone.',
          ),
        ],
        generatedAt: DateTime(2026, 10, 24, 10, 10),
      );
      await store.saveMaterial(mat);
      await store.saveDraft(draft);
      await store.saveScript(script);
    });
    ListeningHost.instance.setIndexForTesting(const ClipIndex());

    await tester.pumpWidget(app());
    await _settle(tester);

    // 自动选中排练分区与 mat_1
    expect(find.text('Q4 Architecture Review'), findsWidgets);

    // 切到步骤 2「生成讲稿」
    await tester.tap(find.byKey(const ValueKey('rehearsal-step-tab-draft')));
    await tester.pumpAndSettle();

    // 修改讲稿标题，应出现「有未保存的修改」标记
    await tester.enterText(
      find.byKey(const ValueKey('draft-title-field')),
      'Updated Q4 Speech Title',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('draft-dirty-badge')), findsOneWidget);

    // 尝试切换到「真实会议」分区，应弹出未保存提示框
    await tester.tap(find.byKey(const ValueKey('nav-real-meetings')));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的讲稿修改'), findsOneWidget);

    // 点击「取消」留在当前排练讲稿编辑页
    await tester.tap(find.byKey(const ValueKey('unsaved-cancel-btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft-dirty-badge')), findsOneWidget);

    // 点击「保存讲稿」，dirty 标记消失，且步骤 3「生成剧本」显示「已过期」
    await tester.runAsync(() async {
      final onPressed = tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-draft-btn')))
          .onPressed;
      onPressed?.call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('draft-dirty-badge')), findsNothing);
    expect(find.text('已过期'), findsOneWidget);
  });

  group('RealMeetingItemSnapshot 单一主操作状态机与 TaskTracker', () {
    final sampleMeeting = RealMeeting(
      id: 'rm_state_test',
      title: 'Sprint Retro',
      sourcePath: '/tmp/retro.md',
      fileName: 'retro.md',
      contentHash: 'hash',
      declaredDurationMs: 0,
      keywords: const [],
      slots: const [SpeakerSlot(id: '发言人 1', turnCount: 1)],
      turns: const [
        MeetingTurn(index: 0, slotId: '发言人 1', timestampMs: 0, text: 'hi'),
      ],
      importedAt: DateTime(2026, 10, 24),
    );

    test('主操作状态按 未合成 -> 待更新 -> 失败 -> 修复音频 -> 已合成 严格映射', () {
      final snapUnbaked = RealMeetingItemSnapshot(
        meeting: sampleMeeting,
        displayTitle: 'Sprint Retro',
        bakeState: null,
      );
      expect(snapUnbaked.primaryKind, RealMeetingPrimaryKind.bakeInitial);
      expect(snapUnbaked.primaryActionLabel, '合成语音');
      expect(snapUnbaked.statusBadge(), '未合成');

      final snapPending = RealMeetingItemSnapshot(
        meeting: sampleMeeting,
        displayTitle: 'Sprint Retro',
        bakeState: MeetingBakeState(
          groups: const [],
          bakedAt: DateTime(2026, 10, 24),
        ),
        pendingGroupCount: 3,
        hasPlayableClip: true,
      );
      expect(snapPending.primaryKind, RealMeetingPrimaryKind.rebakePending);
      expect(snapPending.primaryActionLabel, '重新合成 3 组');
      expect(snapPending.statusBadge(), '⚠ 3 组待更新');

      final snapFailed = RealMeetingItemSnapshot(
        meeting: sampleMeeting,
        displayTitle: 'Sprint Retro',
        bakeState: MeetingBakeState(
          groups: const [
            TurnGroupAudio(turnIndices: [0], fileName: 'g0.mp3', failed: true),
            TurnGroupAudio(turnIndices: [1], fileName: 'g1.mp3', failed: true),
          ],
          bakedAt: DateTime(2026, 10, 24),
        ),
        pendingGroupCount: 0,
        hasPlayableClip: true,
      );
      expect(snapFailed.primaryKind, RealMeetingPrimaryKind.retryFailed);
      expect(snapFailed.primaryActionLabel, '重试失败的 2 组');
      expect(snapFailed.statusBadge(), '✕ 2 组失败');

      final snapRepair = RealMeetingItemSnapshot(
        meeting: sampleMeeting,
        displayTitle: 'Sprint Retro',
        bakeState: MeetingBakeState(
          groups: const [],
          bakedAt: DateTime(2026, 10, 24),
        ),
        pendingGroupCount: 0,
        hasPlayableClip: false,
      );
      expect(snapRepair.primaryKind, RealMeetingPrimaryKind.repairAudio);
      expect(snapRepair.primaryActionLabel, '修复音频');

      final snapReady = RealMeetingItemSnapshot(
        meeting: sampleMeeting,
        displayTitle: 'Sprint Retro',
        bakeState: MeetingBakeState(
          groups: const [],
          bakedAt: DateTime(2026, 10, 24),
        ),
        pendingGroupCount: 0,
        hasPlayableClip: true,
      );
      expect(snapReady.primaryKind, RealMeetingPrimaryKind.ready);
      expect(snapReady.primaryActionLabel, '重新合成');
      expect(snapReady.statusBadge(), '● 已合成');
    });

    test('TaskTracker 按 (kind, itemId) 独立追踪进度与完成通知', () {
      final tracker = TaskTracker();
      final toasts = <WorkspaceToastEvent>[];
      tracker.onToast = toasts.add;

      tracker.start(
        WorkspaceTaskKind.realMeetingBake,
        'rm_1',
        label: '合成中 0/5',
        done: 0,
        total: 5,
      );
      tracker.start(
        WorkspaceTaskKind.rehearsalStep,
        'mat_1',
        label: '正在生成讲稿…',
      );

      expect(tracker.isRunning(WorkspaceTaskKind.realMeetingBake, 'rm_1'), isTrue);
      expect(tracker.isRunning(WorkspaceTaskKind.rehearsalStep, 'mat_1'), isTrue);

      tracker.updateProgress(
        WorkspaceTaskKind.realMeetingBake,
        'rm_1',
        done: 3,
        total: 5,
      );
      expect(
        tracker.entryFor(WorkspaceTaskKind.realMeetingBake, 'rm_1')?.done,
        3,
      );

      tracker.complete(
        WorkspaceTaskKind.realMeetingBake,
        'rm_1',
        message: 'rm_1 完成',
      );
      expect(
        tracker.isRunning(WorkspaceTaskKind.realMeetingBake, 'rm_1'),
        isFalse,
      );
      expect(tracker.isRunning(WorkspaceTaskKind.rehearsalStep, 'mat_1'), isTrue);
      expect(toasts.length, 1);
      expect(toasts.first.message, 'rm_1 完成');
    });
  });
}
