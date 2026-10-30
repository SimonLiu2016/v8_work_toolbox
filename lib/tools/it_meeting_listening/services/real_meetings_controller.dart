/// 真实会议控制器：会议列表、导入、说话人设定、单一合成主操作状态机、回答插入与删除。
///
/// 满足 `design.md` D5 的主操作状态机：
/// - 未合成 → `合成语音`
/// - 有设定与音频不一致的组 → `重新合成 n 组`（可取消）
/// - 有失败组 → `重试失败的 n 组`
/// - 分组齐全但整篇音频缺失 → `修复音频`（resume 补拼，零 TTS 请求）
/// - 已合成且一致 → 状态显示 `● 已合成`，主操作为次要的 `重新合成`
library;

import 'package:flutter/foundation.dart';

import '../../reader/services/tts_engine.dart';
import '../models/real_meeting_models.dart';
import 'clip_library.dart';
import 'listening_host.dart';
import 'meeting_vocabulary_index.dart';
import 'real_meeting_baker.dart';
import 'real_meeting_service.dart';
import 'real_meeting_store.dart';
import 'speaker_profile_resolver.dart';
import 'task_tracker.dart';
import 'transcript_parser.dart';

/// 真实会议的主操作形态。
enum RealMeetingPrimaryKind {
  /// 尚未合成。
  bakeInitial,

  /// 设定已改（音色/合并/名字），部分分组待更新。
  rebakePending,

  /// 上次合成存在失败分组。
  retryFailed,

  /// 分组音频都在，但整场拼接文件缺失（坏记录自愈）。
  repairAudio,

  /// 已完整合成且无待更新项。
  ready,
}

/// 单场真实会议的完整视图快照。
class RealMeetingItemSnapshot {
  final RealMeeting meeting;
  final String displayTitle;
  final Map<String, ResolvedSpeaker> speakers;
  final Map<String, String> mergeInto;
  final MeetingBakeState? bakeState;
  final int pendingGroupCount;
  final bool hasPlayableClip;

  const RealMeetingItemSnapshot({
    required this.meeting,
    required this.displayTitle,
    this.speakers = const {},
    this.mergeInto = const {},
    this.bakeState,
    this.pendingGroupCount = 0,
    this.hasPlayableClip = false,
  });

  int get failedGroupCount => bakeState?.failedGroupCount ?? 0;

  /// 推导当前主操作类型。
  RealMeetingPrimaryKind get primaryKind {
    if (bakeState == null) return RealMeetingPrimaryKind.bakeInitial;
    if (pendingGroupCount > 0) return RealMeetingPrimaryKind.rebakePending;
    if (failedGroupCount > 0) return RealMeetingPrimaryKind.retryFailed;
    if (!hasPlayableClip) return RealMeetingPrimaryKind.repairAudio;
    return RealMeetingPrimaryKind.ready;
  }

  /// 主操作按钮文案。
  String get primaryActionLabel {
    return switch (primaryKind) {
      RealMeetingPrimaryKind.bakeInitial => '合成语音',
      RealMeetingPrimaryKind.rebakePending => '重新合成 $pendingGroupCount 组',
      RealMeetingPrimaryKind.retryFailed => '重试失败的 $failedGroupCount 组',
      RealMeetingPrimaryKind.repairAudio => '修复音频',
      RealMeetingPrimaryKind.ready => '重新合成',
    };
  }

  /// 列表与详情展示的状态标记文案。
  String statusBadge({WorkspaceTaskEntry? activeTask}) {
    if (activeTask != null && activeTask.running) {
      if (activeTask.total > 0) {
        return '合成中 ${activeTask.done}/${activeTask.total}';
      }
      return '合成中…';
    }
    return switch (primaryKind) {
      RealMeetingPrimaryKind.bakeInitial => '未合成',
      RealMeetingPrimaryKind.rebakePending => '⚠ $pendingGroupCount 组待更新',
      RealMeetingPrimaryKind.retryFailed => '✕ $failedGroupCount 组失败',
      RealMeetingPrimaryKind.repairAudio => '⚠ 待修复音频',
      RealMeetingPrimaryKind.ready => '● 已合成',
    };
  }
}

/// 真实会议控制器。
class RealMeetingsController extends ChangeNotifier {
  final RealMeetingStore store;
  final RealMeetingService service;
  final ClipLibrary library;
  final TaskTracker tracker;
  final Future<void> Function()? onIndexChanged;

  List<RealMeeting> _meetings = const [];
  Map<String, RealMeetingItemSnapshot> _snapshots = const {};
  MeetingVocabularyIndex? _vocabularyIndex;
  final Set<String> _cancelRequestedIds = {};

  RealMeetingsController({
    RealMeetingStore? store,
    RealMeetingService? service,
    ClipLibrary? library,
    required this.tracker,
    this.onIndexChanged,
    TtsEngine Function()? ttsEngineFactory,
  })  : store = store ?? RealMeetingStore(),
        library = library ?? ListeningHost.instance.library,
        service = service ??
            RealMeetingService(
              store: store ?? RealMeetingStore(),
              baker: RealMeetingBaker(
                engine: (ttsEngineFactory ?? (() => OpenAiTtsEngine()))(),
                store: store ?? RealMeetingStore(),
              ),
              library: library ?? ListeningHost.instance.library,
            );

  List<RealMeeting> get meetings => _meetings;
  Map<String, RealMeetingItemSnapshot> get snapshots => _snapshots;

  RealMeetingItemSnapshot? snapshotFor(String? meetingId) =>
      meetingId == null ? null : _snapshots[meetingId];

  /// 按搜索词过滤后的会议快照列表。
  List<RealMeetingItemSnapshot> filteredSnapshots(String query) {
    final q = query.trim().toLowerCase();
    final all = _meetings
        .map((m) => _snapshots[m.id])
        .whereType<RealMeetingItemSnapshot>()
        .toList();
    if (q.isEmpty) return all;
    return all
        .where((s) =>
            s.displayTitle.toLowerCase().contains(q) ||
            s.meeting.title.toLowerCase().contains(q))
        .toList();
  }

  /// 载入全部已导入的真实会议及其状态快照。
  Future<void> loadMeetings() async {
    final list = await store.listMeetings();
    final idx = await ListeningHost.instance.loadIndex();
    final nextSnapshots = <String, RealMeetingItemSnapshot>{};

    for (final m in list) {
      final speakers = await service.resolveSpeakers(m);
      final state = await store.loadBakeState(m.id);
      final settings = await store.loadSettings(m.id);
      final pending = (await service.pendingGroups(m)).length;
      final clip = idx.byId(m.id);
      final hasClip = clip != null &&
          !clip.isPlaceholder &&
          library.audioFileFor(clip).existsSync();
      final displayTitle = settings.displayTitle.trim().isNotEmpty
          ? settings.displayTitle.trim()
          : m.title;

      nextSnapshots[m.id] = RealMeetingItemSnapshot(
        meeting: m,
        displayTitle: displayTitle,
        speakers: speakers,
        mergeInto: settings.mergeInto,
        bakeState: state,
        pendingGroupCount: pending,
        hasPlayableClip: hasClip,
      );
    }

    _meetings = list;
    _snapshots = nextSnapshots;
    notifyListeners();
  }

  /// 解析逐字稿文件（第一步，不落盘）。
  Future<TranscriptPreview?> parseTranscriptFile(String path) async {
    try {
      return await service.parseFile(path);
    } on TranscriptParseException catch (e) {
      tracker.emitToast(e.toString(), isError: true);
      return null;
    } catch (e) {
      tracker.emitToast('解析失败：$e', isError: true);
      return null;
    }
  }

  /// 确认导入逐字稿并自动合成（第二步）。返回导入后的会议 id。
  Future<String?> commitImport(TranscriptPreview preview) async {
    const taskId = 'import';
    tracker.start(
      WorkspaceTaskKind.realMeetingImport,
      taskId,
      label: '正在导入并合成…',
    );
    try {
      final outcome = await service.commitImport(
        preview,
        onProgress: (done, total, speaker) {
          tracker.updateProgress(
            WorkspaceTaskKind.realMeetingImport,
            taskId,
            done: done,
            total: total,
            label: '合成中 $done/$total',
          );
        },
      );
      _vocabularyIndex = null;
      await onIndexChanged?.call();
      await loadMeetings();
      await refreshVocabulary();

      final bake = outcome.bake;
      final failed = bake?.failedGroupCount ?? 0;
      if (outcome.unchanged) {
        tracker.complete(
          WorkspaceTaskKind.realMeetingImport,
          taskId,
          message: '文稿内容未变，未做任何改动',
        );
      } else if (failed > 0) {
        tracker.fail(
          WorkspaceTaskKind.realMeetingImport,
          taskId,
          '已导入「${outcome.meeting.title}」，$failed 组合成失败（可重试）',
        );
      } else {
        tracker.complete(
          WorkspaceTaskKind.realMeetingImport,
          taskId,
          message: bake == null
              ? '已导入「${outcome.meeting.title}」'
              : '已导入并合成「${outcome.meeting.title}」',
        );
      }
      return outcome.meeting.id;
    } on TranscriptParseException catch (e) {
      tracker.fail(WorkspaceTaskKind.realMeetingImport, taskId, e.toString());
      return null;
    } catch (e) {
      tracker.fail(WorkspaceTaskKind.realMeetingImport, taskId, '导入失败：$e');
      return null;
    }
  }

  /// 执行指定会议的单一合成主操作（根据当前状态自动选择：首次合成 / 重新合成待更新组 / 重试失败组 / 修复整场音频）。
  Future<void> runPrimaryAction(String meetingId) async {
    final snap = _snapshots[meetingId];
    if (snap == null) return;
    if (tracker.isRunning(WorkspaceTaskKind.realMeetingBake, meetingId)) return;

    _cancelRequestedIds.remove(meetingId);

    if (snap.primaryKind == RealMeetingPrimaryKind.rebakePending) {
      await _rebakePendingFor(snap.meeting);
      return;
    }

    tracker.start(
      WorkspaceTaskKind.realMeetingBake,
      meetingId,
      label: snap.primaryKind == RealMeetingPrimaryKind.repairAudio
          ? '正在修复整场音频…'
          : '正在合成语音…',
    );
    try {
      final result = await service.bake(
        snap.meeting,
        onProgress: (done, total, speaker) {
          tracker.updateProgress(
            WorkspaceTaskKind.realMeetingBake,
            meetingId,
            done: done,
            total: total,
            label: '合成中 $done/$total',
          );
        },
      );
      await onIndexChanged?.call();
      await loadMeetings();
      if (result.failedGroupCount > 0) {
        tracker.fail(
          WorkspaceTaskKind.realMeetingBake,
          meetingId,
          '${result.failedGroupCount} 组合成失败，可重试',
        );
      } else if (!result.hasPlayableAudio) {
        tracker.fail(
          WorkspaceTaskKind.realMeetingBake,
          meetingId,
          '整篇音频拼接失败',
        );
      } else {
        tracker.complete(
          WorkspaceTaskKind.realMeetingBake,
          meetingId,
          message: '「${snap.displayTitle}」合成完成',
        );
      }
    } catch (e) {
      tracker.fail(
        WorkspaceTaskKind.realMeetingBake,
        meetingId,
        '合成失败：$e',
      );
    }
  }

  Future<void> _rebakePendingFor(RealMeeting meeting) async {
    final pending = await service.pendingGroups(meeting);
    if (pending.isEmpty) {
      tracker.emitToast('没有需要重新合成的组');
      return;
    }
    tracker.start(
      WorkspaceTaskKind.realMeetingBake,
      meeting.id,
      label: '正在重新合成 0/${pending.length} 组…',
      done: 0,
      total: pending.length,
    );
    try {
      final result = await service.rebakeGroups(
        meeting,
        pending.toSet(),
        shouldCancel: () => _cancelRequestedIds.contains(meeting.id),
        onProgress: (done, total, speaker) {
          tracker.updateProgress(
            WorkspaceTaskKind.realMeetingBake,
            meeting.id,
            done: done,
            total: total,
            label: '正在重新合成 $done/$total 组…',
          );
        },
      );
      await onIndexChanged?.call();
      await loadMeetings();
      if (result.cancelled) {
        tracker.complete(
          WorkspaceTaskKind.realMeetingBake,
          meeting.id,
          message: '已取消重新合成：完成的组已更新，其余仍待更新',
        );
      } else if (result.failedGroupCount > 0) {
        tracker.fail(
          WorkspaceTaskKind.realMeetingBake,
          meeting.id,
          '重新合成完成，${result.failedGroupCount} 组失败（保留旧音频）',
        );
      } else {
        tracker.complete(
          WorkspaceTaskKind.realMeetingBake,
          meeting.id,
          message: '重新合成完成',
        );
      }
    } catch (e) {
      tracker.fail(
        WorkspaceTaskKind.realMeetingBake,
        meeting.id,
        '重新合成失败：$e',
      );
    } finally {
      _cancelRequestedIds.remove(meeting.id);
    }
  }

  /// 请求取消指定会议正在进行的重新合成。
  void requestCancelBake(String meetingId) {
    _cancelRequestedIds.add(meetingId);
    notifyListeners();
  }

  /// 修改说话人显示名（瞬时，不触发 TTS）。
  Future<void> renameSpeaker(
      String meetingId, String slotId, String name) async {
    await service.renameSpeaker(meetingId, slotId, name);
    await onIndexChanged?.call();
    await loadMeetings();
  }

  /// 修改说话人音色（瞬时，不触发 TTS）。
  Future<void> setSpeakerVoice(
      String meetingId, String slotId, String voiceId) async {
    await service.setSpeakerVoice(meetingId, slotId, voiceId);
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast('已切换「$slotId」的音色，音频待重新合成');
  }

  /// 切换"是我"标记（瞬时，不触发 TTS）。
  Future<void> toggleSpeakerIsMe(
      String meetingId, String slotId, bool isMe) async {
    await service.markSlotAsMe(meetingId, slotId, isMe: isMe);
    await onIndexChanged?.call();
    await loadMeetings();
  }

  /// 合并说话人槽位（瞬时，不触发 TTS）。
  Future<void> mergeSpeaker(
      String meetingId, String fromSlot, String intoSlot) async {
    await service.mergeSpeakers(meetingId, fromSlot, intoSlot);
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast('已把「$fromSlot」合并到「$intoSlot」，音频待重新合成');
  }

  /// 取消合并说话人槽位（瞬时，不触发 TTS）。
  Future<void> unmergeSpeaker(String meetingId, String slotId) async {
    await service.unmergeSpeaker(meetingId, slotId);
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast('已取消「$slotId」的合并，音频待重新合成');
  }

  /// 重命名会议（覆盖层，不改原稿；传空串恢复文稿标题）。
  Future<void> renameMeeting(String meetingId, String newDisplayTitle) async {
    await service.renameMeeting(meetingId, newDisplayTitle);
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast(
      newDisplayTitle.trim().isEmpty
          ? '已恢复文稿标题'
          : '已重命名为「${newDisplayTitle.trim()}」',
    );
  }

  /// 删除一场真实会议及其音频、设定、插入的回答（原稿文件不受影响）。
  Future<void> deleteMeeting(String meetingId) async {
    final hostPlayer = ListeningHost.instance.controller;
    if (hostPlayer.clip?.id == meetingId) {
      await hostPlayer.stop();
    }
    await store.deleteMeeting(meetingId);
    await store.deleteSettings(meetingId);

    final idx = await library.loadIndex();
    final remaining = idx.clips.where((c) => c.id != meetingId).toList();
    if (remaining.length != idx.clips.length) {
      await library.rebuildIndex(remaining);
    }

    _vocabularyIndex = null;
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast('已删除该会议');
  }

  /// 读取全局「我的身份」。
  Future<MyIdentity> loadMyIdentity() => store.loadMyIdentity();

  /// 保存全局「我的身份」。
  Future<void> saveMyIdentity(MyIdentity identity) async {
    await service.setMyIdentity(identity);
    await onIndexChanged?.call();
    await loadMeetings();
  }

  /// 读取指定会议已插入的回答。
  Future<List<InsertedAnswer>> loadAnswers(String meetingId) =>
      store.loadAnswers(meetingId);

  /// 插入一条我的回答。返回 null 表示成功，非 null 为失败原因。
  Future<String?> insertAnswer({
    required String meetingId,
    required int questionTurnIndex,
    required String textEn,
    required String textZh,
  }) async {
    final inserted = await service.insertAnswer(
      meetingId: meetingId,
      questionTurnIndex: questionTurnIndex,
      textEn: textEn,
      textZh: textZh,
    );
    if (inserted == null) return '插入失败：合成没有产出音频';
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast('已插入回答');
    return null;
  }

  /// 修改已插入回答的文本并重新合成。
  Future<void> updateAnswerText(
    String meetingId,
    String answerId,
    String newTextEn,
  ) async {
    await service.updateAnswerText(meetingId, answerId, newTextEn);
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast('回答已更新');
  }

  /// 删除一条已插入的回答。
  Future<void> deleteAnswer(String meetingId, String answerId) async {
    await service.deleteAnswer(meetingId, answerId);
    await onIndexChanged?.call();
    await loadMeetings();
    tracker.emitToast('已删除该回答');
  }

  /// 重建或读取缓存的真实会议词汇表索引。
  Future<MeetingVocabularyIndex> refreshVocabulary({bool force = false}) async {
    final cached = _vocabularyIndex;
    if (!force && cached != null) return cached;
    final built = await MeetingVocabularyStore().rebuild(_meetings);
    _vocabularyIndex = built;
    return built;
  }
}
