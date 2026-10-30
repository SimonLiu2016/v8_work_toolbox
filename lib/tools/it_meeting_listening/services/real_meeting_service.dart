/// 真实会议的编排层：把解析、仓库、合成器、素材索引串起来。
///
/// **为什么需要这一层**：`RealMeetingBaker` 只管"文本 → 音频"，`RealMeetingStore`
/// 只管"读写文件"。但一个真实操作（改音色、插回答）往往要动三处——删掉旧音频、
/// 重合成、重建整篇并写回索引。让界面直接编排这三步，迟早会出现"改了音色但
/// 索引没更新"的脏状态。这里把"一次操作 = 一组原子步骤"封起来。
///
/// **素材索引是派生产物**（design D1）：每次会议数据变化后由这里重建 Clip 并
/// 覆盖写进索引，绝不反向从索引读回会议状态。
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/listening_models.dart';
import '../models/real_meeting_models.dart';
import 'clip_library.dart';
import 'real_meeting_baker.dart';
import 'real_meeting_store.dart';
import 'speaker_profile_resolver.dart';
import 'transcript_parser.dart';

/// 导入结果。
class ImportOutcome {
  /// 会议数据。
  final RealMeeting meeting;

  /// 是否因为"内容未变"而什么都没做。
  final bool unchanged;

  /// 合成结果（[unchanged] 为真时为 null）。
  final RealMeetingBakeResult? bake;

  const ImportOutcome({
    required this.meeting,
    this.unchanged = false,
    this.bake,
  });
}

/// 解析预览：**只描述"这份文件会被理解成什么"，不落盘、不合成**。
///
/// 格式放宽之后，"解析成功"不再等价于"这是我要的那场会"——真按错的理解去
/// 合成，代价是一条二十分钟的假音频加几百次 TTS 调用。这张卡片就是把判断权
/// 交回用户的那一步。
class TranscriptPreview {
  final String sourcePath;
  final String fileName;
  final String title;
  final String meetingId;
  final String contentHash;

  final int turnCount;
  final int durationMs;
  final List<String> slotIds;

  /// 前几轮样例（说话人 + 正文），供用户一眼判断解析对不对。
  final List<({String slot, String text})> samples;

  /// 没找到「关键词」段（豆包导出件就没有）。
  final bool keywordsMissing;

  /// 看着像人工整理的归档件（说明表格 + 内嵌原文 + 附录）。
  final bool isProcessedDocument;

  /// 同一路径已导入过且内容未变。
  final bool contentUnchanged;

  /// 解析结果本体——提交时直接用，避免重读重解。
  final ParsedTranscript parsed;

  const TranscriptPreview({
    required this.sourcePath,
    required this.fileName,
    required this.title,
    required this.meetingId,
    required this.contentHash,
    required this.turnCount,
    required this.durationMs,
    required this.slotIds,
    required this.samples,
    required this.parsed,
    this.keywordsMissing = false,
    this.isProcessedDocument = false,
    this.contentUnchanged = false,
  });
}

/// 真实会议服务。
class RealMeetingService {
  static const _uuid = Uuid();

  final RealMeetingStore store;
  final RealMeetingBaker baker;
  final ClipLibrary library;

  /// 每场会议正在进行的"重建整篇音频"链条。
  ///
  /// 「生成音频」与「重新合成」都能把同一场会议的几百个 mp3 重新拼一遍，两者
  /// 并发会互相覆盖同一个输出文件。这里按会议串行化：后到的排队等前一个结束，
  /// 而不是在 UI 层把按钮互相禁用（那会让用户以为功能没了）。
  final Map<String, Future<void>> _rebuildChain = {};

  /// 在同一会议的串行队列里执行 [action]。
  Future<T> _serialized<T>(String meetingId, Future<T> Function() action) async {
    final previous = _rebuildChain[meetingId] ?? Future<void>.value();
    final gate = Completer<void>();
    _rebuildChain[meetingId] = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_rebuildChain[meetingId], gate.future)) {
        _rebuildChain.remove(meetingId);
      }
    }
  }

  RealMeetingService({
    required this.store,
    required this.baker,
    required this.library,
  });

  // ---------------------------------------------------------------------
  // 导入
  // ---------------------------------------------------------------------

  /// 解析一份逐字稿，返回预览。**不写文件、不合成、不动词汇表**。
  ///
  /// 用户看过预览点确认后才走 [commitImport]。
  Future<TranscriptPreview> parseFile(String path) async {
    final text = await TranscriptParser.readFileText(path);
    final parsed = TranscriptParser.parse(text);
    final hash = TranscriptParser.contentHashOf(text);
    final existing = await store.findBySourcePath(path);

    const sampleSize = 5;
    return TranscriptPreview(
      sourcePath: path,
      fileName: path.split('/').last,
      title: parsed.title,
      meetingId: TranscriptParser.meetingIdFor(path),
      contentHash: hash,
      turnCount: parsed.turns.length,
      durationMs: parsed.effectiveDurationMs,
      slotIds: parsed.slots.map((s) => s.id).toList(),
      samples: [
        for (final t in parsed.turns.take(sampleSize))
          (slot: t.slotId, text: t.text),
      ],
      parsed: parsed,
      keywordsMissing: parsed.keywordsMissing,
      isProcessedDocument: parsed.isProcessedDocument,
      contentUnchanged: existing != null && existing.contentHash == hash,
    );
  }

  /// 按预览落盘并合成。
  Future<ImportOutcome> commitImport(
    TranscriptPreview preview, {
    RealMeetingBakeProgress? onProgress,
  }) async {
    final parsed = preview.parsed;
    final path = preview.sourcePath;

    final existing = await store.findBySourcePath(path);
    if (existing != null && existing.contentHash == preview.contentHash) {
      return ImportOutcome(meeting: existing, unchanged: true);
    }

    final meeting = RealMeeting(
      id: preview.meetingId,
      title: parsed.title,
      sourcePath: path,
      fileName: preview.fileName,
      contentHash: preview.contentHash,
      declaredDurationMs: parsed.declaredDurationMs,
      keywords: parsed.keywords,
      slots: parsed.slots,
      turns: parsed.turns,
      importedAt: DateTime.now(),
    );
    await store.saveMeeting(meeting);

    // 文稿被更新过：回答保留，但锚点可能越界。
    if (existing != null) {
      final answers = await store.loadAnswers(meeting.id);
      if (answers.isNotEmpty) {
        await store.saveAnswers(meeting.id, [
          for (final a in answers)
            a.copyWith(stale: a.anchorTurnIndex >= meeting.turns.length),
        ]);
      }
    }

    final speakers = await resolveSpeakers(meeting);
    final bake =
        await baker.bake(meeting, speakers: speakers, onProgress: onProgress);
    await _publish(meeting, bake.clip);
    return ImportOutcome(meeting: meeting, bake: bake);
  }

  /// 一步导入（解析 + 落盘 + 合成）。
  ///
  /// 保留给**非交互**场景（测试、脚本）。界面必须走 [parseFile] +
  /// [commitImport]，否则用户没有机会在几百次 TTS 之前看一眼解析结果。
  Future<ImportOutcome> importFile(
    String path, {
    RealMeetingBakeProgress? onProgress,
  }) async {
    final preview = await parseFile(path);
    return commitImport(preview, onProgress: onProgress);
  }

  /// 重新合成整场（续跑：已成功的组不重复合成）。
  Future<RealMeetingBakeResult> bake(
    RealMeeting meeting, {
    RealMeetingBakeProgress? onProgress,
  }) =>
      _serialized(meeting.id, () async {
        final speakers = await resolveSpeakers(meeting);
        final result = await baker.bake(meeting,
            speakers: speakers, onProgress: onProgress);
        await _publish(meeting, result.clip);
        return result;
      });

  // ---------------------------------------------------------------------
  // 说话人设定
  // ---------------------------------------------------------------------

  /// 解析某场会议的全部说话人。
  Future<Map<String, ResolvedSpeaker>> resolveSpeakers(
      RealMeeting meeting) async {
    final settings = await store.loadSettings(meeting.id);
    final identity = await store.loadMyIdentity();
    return SpeakerProfileResolver.resolveAll(
      slotIds: meeting.slotIds,
      settings: settings,
      identity: identity,
    );
  }

  /// 改显示名。只重建素材，不重新合成（名字不进音频）。
  Future<Clip?> renameSpeaker(
    String meetingId,
    String slotId,
    String displayName,
  ) async {
    final meeting = await _requireMeeting(meetingId);
    final settings = await store.loadSettings(meetingId);
    await store.saveSettings(meetingId,
        settings.withSlot(slotId, settings.of(slotId).copyWith(displayName: displayName)));
    return refresh(meeting);
  }

  /// 把某槽位标记为「我」（使用「我的身份」的名字与音色）。
  Future<Clip?> markSlotAsMe(String meetingId, String slotId,
      {bool isMe = true}) async {
    final meeting = await _requireMeeting(meetingId);
    final settings = await store.loadSettings(meetingId);
    await store.saveSettings(meetingId,
        settings.withSlot(slotId, settings.of(slotId).copyWith(isMe: isMe)));
    // **不在这里重合成**：设定是声明，合成是执行（design D1）。立刻重建素材
    // 让界面显示新设置，音频留待用户显式发起重烘。
    return refresh(meeting);
  }

  /// 把 [fromSlot] 合并到 [intoSlot]：两者此后使用同一显示名与音色。
  ///
  /// 只重合成被合并槽位的组——目标槽位的音频没变，不需要重跑。
  Future<Clip?> mergeSpeakers(
      String meetingId, String fromSlot, String intoSlot) async {
    if (fromSlot == intoSlot) return null;
    final meeting = await _requireMeeting(meetingId);
    final settings = await store.loadSettings(meetingId);
    await store
        .saveSettings(meetingId, settings.withMerge(fromSlot, intoSlot));
    return refresh(meeting);
  }

  /// 取消 [slotId] 的合并，恢复它自己的显示名与音色。
  Future<Clip?> unmergeSpeaker(String meetingId, String slotId) async {
    final meeting = await _requireMeeting(meetingId);
    final settings = await store.loadSettings(meetingId);
    await store.saveSettings(meetingId, settings.withoutMerge(slotId));
    return refresh(meeting);
  }

  /// 改音色：只重合成该槽位所属的组，其余组复用已有音频。
  Future<Clip?> setSpeakerVoice(
      String meetingId, String slotId, String voiceId) async {
    final meeting = await _requireMeeting(meetingId);
    final settings = await store.loadSettings(meetingId);
    await store.saveSettings(
        meetingId,
        settings.withSlot(
            slotId, settings.of(slotId).copyWith(voiceId: voiceId)));
    // 只改设定，不合成。界面立刻回填；音频标记为「待更新」由 [pendingGroups] 给出。
    return refresh(meeting);
  }

  /// 找出「设定音色 ≠ 该组实际合成音色」的组下标。
  ///
  /// 旧数据没有记录音色时**不算待更新**：不知道当时用的什么，不等于用错了。
  /// 把所有历史会议标成待更新是恐吓式提示。
  Future<List<int>> pendingGroups(RealMeeting meeting) async {
    final state = await store.loadBakeState(meeting.id);
    if (state == null || state.groups.isEmpty) return const [];
    final speakers = await resolveSpeakers(meeting);
    final byIndex = {for (final t in meeting.turns) t.index: t};
    final out = <int>[];
    for (var i = 0; i < state.groups.length; i++) {
      final grp = state.groups[i];
      if (grp.voiceId.isEmpty || grp.turnIndices.isEmpty) continue;
      final slotId = byIndex[grp.turnIndices.first]?.slotId;
      final desired = speakers[slotId]?.voiceId ?? '';
      if (desired.isNotEmpty && desired != grp.voiceId) out.add(i);
    }
    return out;
  }

  /// 重烘指定的组（通常是 [pendingGroups] 的结果），并重建整篇音频。
  ///
  /// 失败的单组保留旧音频；[shouldCancel] 为真时在组边界停止，已完成的组保留。
  Future<RealMeetingBakeResult> rebakeGroups(
    RealMeeting meeting,
    Set<int> groupIndices, {
    RealMeetingBakeProgress? onProgress,
    bool Function()? shouldCancel,
  }) async {
    return _serialized(meeting.id, () async {
      final speakers = await resolveSpeakers(meeting);
      final result = await baker.bake(
        meeting,
        speakers: speakers,
        onProgress: onProgress,
        forceGroups: groupIndices,
        shouldCancel: shouldCancel,
      );
      await store.saveBakeState(meeting.id, result.state);
      await _publish(meeting, result.clip);
      return result;
    });
  }

  /// 设置会议的自定义显示名（空串即清除，回落到文稿标题）。
  Future<Clip?> renameMeeting(String meetingId, String title) async {
    final meeting = await _requireMeeting(meetingId);
    final settings = await store.loadSettings(meetingId);
    await store.saveSettings(meetingId, settings.withTitle(title));
    return refresh(meeting);
  }

  /// 把覆盖层里的显示名套到派生素材上。
  ///
  /// Clip 是派生产物（design D1 of `add-real-meeting-import`）：标题必须在这里
  /// 统一改写，否则「改名后列表还是老名字」。
  Future<Clip> _withDisplayTitle(RealMeeting meeting, Clip clip) async {
    final settings = await store.loadSettings(meeting.id);
    final title = settings.displayTitle.trim();
    if (title.isEmpty || title == clip.title) return clip;
    return clip.copyWith(title: title);
  }

  /// 更新「我的身份」。
  ///
  /// 历史回答里的名字与音色是**快照**，不随这次修改变化——它们已经被合成进
  /// 音频里了，改名会让文稿与声音对不上。
  Future<void> setMyIdentity(MyIdentity identity) =>
      store.saveMyIdentity(identity);

  // ---------------------------------------------------------------------
  // 回答层
  // ---------------------------------------------------------------------

  /// 插入一段回答。
  ///
  /// 只合成新增那一段，整篇靠重新 concat 重建（design D4）。
  Future<InsertedAnswer?> insertAnswer({
    required String meetingId,
    required int questionTurnIndex,
    required String textEn,
    String textZh = '',
  }) async {
    final meeting = await _requireMeeting(meetingId);
    if (textEn.trim().isEmpty) return null;
    final identity = await store.loadMyIdentity();
    final id = 'ans_${_uuid.v4().substring(0, 8)}';
    final fileName = '$id.mp3';

    final baked = await baker.bakeAnswer(
      meetingId: meetingId,
      textEn: textEn,
      voiceId: identity.voiceId,
      fileName: fileName,
    );
    if (baked == null) return null;

    final answer = InsertedAnswer(
      id: id,
      anchorTurnIndex: questionTurnIndex,
      questionTurnIndex: questionTurnIndex,
      speakerName: identity.name,
      voiceId: identity.voiceId,
      textEn: textEn,
      textZh: textZh,
      audioFile: fileName,
    );
    final answers = await store.loadAnswers(meetingId);
    await store.saveAnswers(meetingId, [...answers, answer]);
    await _rebuild(meeting);
    return answer;
  }

  /// 改回答文本：重合成该段并重建整篇。
  Future<Clip?> updateAnswerText(
    String meetingId,
    String answerId,
    String textEn, {
    String? textZh,
  }) async {
    final meeting = await _requireMeeting(meetingId);
    final answers = await store.loadAnswers(meetingId);
    final idx = answers.indexWhere((a) => a.id == answerId);
    if (idx < 0) return null;
    final old = answers[idx];

    final baked = await baker.bakeAnswer(
      meetingId: meetingId,
      textEn: textEn,
      voiceId: old.voiceId,
      fileName: old.audioFile.isEmpty ? '${old.id}.mp3' : old.audioFile,
    );
    answers[idx] = old.copyWith(
      textEn: textEn,
      textZh: textZh ?? old.textZh,
      audioFile: baked ?? old.audioFile,
    );
    await store.saveAnswers(meetingId, answers);
    await _rebuild(meeting);
    return _loadClip(meetingId);
  }

  /// 删除一条回答并重建（时间戳随之后移复原）。
  Future<Clip?> deleteAnswer(String meetingId, String answerId) async {
    final meeting = await _requireMeeting(meetingId);
    final answers = await store.loadAnswers(meetingId);
    final target = answers.where((a) => a.id == answerId).toList();
    await store.saveAnswers(
        meetingId, answers.where((a) => a.id != answerId).toList());
    // 音频文件一并删掉，否则 turns 目录会堆下越来越多没人引用的 mp3。
    for (final a in target) {
      if (a.audioFile.isEmpty) continue;
      final file = store.turnAudioFile(meetingId, a.audioFile);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    await _rebuild(meeting);
    return _loadClip(meetingId);
  }

  // ---------------------------------------------------------------------
  // 读取
  // ---------------------------------------------------------------------

  /// 读取某场会议当前的素材（从已落盘的合成状态重建）。
  Future<Clip?> _loadClip(String meetingId) async {
    final meeting = await store.loadMeeting(meetingId);
    if (meeting == null) return null;
    final speakers = await resolveSpeakers(meeting);
    final (clip, _) = await baker.rebuildAudio(meeting, speakers: speakers);
    return clip;
  }

  /// 重新派生素材并写回索引。
  Future<Clip?> refresh(RealMeeting meeting) async {
    final speakers = await resolveSpeakers(meeting);
    final (clip, _) = await baker.rebuildAudio(meeting, speakers: speakers);
    if (clip == null) return null;
    final titled = await _withDisplayTitle(meeting, clip);
    await _publish(meeting, clip);
    return titled;
  }

  Future<void> _rebuild(RealMeeting meeting) async {
    final speakers = await resolveSpeakers(meeting);
    final (clip, state) = await baker.rebuildAudio(meeting, speakers: speakers);
    await store.saveBakeState(meeting.id, state);
    await _publish(meeting, clip);
  }

  /// 把素材写进索引（按 id 覆盖）。
  Future<void> _publish(RealMeeting meeting, Clip? clip) async {
    if (clip == null) return;
    final titled = await _withDisplayTitle(meeting, clip);
    final index = await library.loadIndex();
    final clips = [
      ...index.clips.where((c) => c.id != titled.id),
      titled,
    ];
    await library.rebuildIndex(clips);
  }

  Future<RealMeeting> _requireMeeting(String id) async {
    final meeting = await store.loadMeeting(id);
    if (meeting == null) {
      throw StateError('会议不存在：$id');
    }
    return meeting;
  }
}
