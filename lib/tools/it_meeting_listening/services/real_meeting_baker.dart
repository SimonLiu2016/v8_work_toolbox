/// 真实会议的语音合成与整篇重建。
///
/// **两条独立的路**（design D4）：
///
/// ```
/// bake()         逐组合成 → 每组一个 mp3 → 重建整篇
/// rebuildAudio() 只用已落盘的逐组音频 + 回答音频 concat → 重算时间戳
/// ```
///
/// 插入一段回答时只跑 `rebuildAudio()`：不调用 TTS，成本是"拼几十个本地文件"，
/// 与会议长度无关。这是本功能最关键的一条——否则改一次回答就要重跑几百轮
/// 合成（十几分钟）。
///
/// **合成防线照抄 [RehearsalBaker]**：空音频重试、HTTP 451 降级到 120 字碎片、
/// HTTP 402 配额 fast-fail、900 字按句切分。这些不是凭空设计的规则，是实测
/// 撞出来的：不抄就得再撞一遍。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import '../models/listening_models.dart';
import '../models/real_meeting_models.dart';
import 'audio_toolkit.dart';
import 'clip_baker.dart';
import 'continuation_merger.dart';
import 'real_meeting_store.dart';
import 'speaker_profile_resolver.dart';
import 'text_sanitizer.dart';

/// 合成进度回调：`(已完成组数, 总组数, 当前说话人显示名)`。
typedef RealMeetingBakeProgress = void Function(
    int done, int total, String speaker);

/// 合成结果。
class RealMeetingBakeResult {
  /// 落盘后的合成状态。
  final MeetingBakeState state;

  /// 失败的组下标 → 原因。
  final Map<int, String> failures;

  /// 派生出的素材（无任何音频时为 null）。
  final Clip? clip;

  /// 是否因用户取消而提前结束（未处理的组保持原状）。
  final bool cancelled;

  const RealMeetingBakeResult({
    required this.state,
    this.failures = const {},
    this.clip,
    this.cancelled = false,
  });

  bool get hasAudio => clip != null;

  /// 整篇音频是否真的可播（而不是一条指向缺失文件的占位记录）。
  ///
  /// 与 [hasAudio] 分开：逐组可能全部合成成功、但整篇拼接失败。此时素材仍要
  /// 进素材库（否则用户以为导入丢了），但它不能算"可播"。
  bool get hasPlayableAudio => clip != null && !clip!.isPlaceholder;

  int get failedGroupCount => failures.length;
}

/// 真实会议合成器。
class RealMeetingBaker {
  /// 单组合成的重试次数（不含首次）。
  static const int turnRetries = 2;

  /// 失败组在时间轴上占用的静音时长。
  ///
  /// 没有占位的话，失败组之后的所有轮次时间戳都会前移，用户点第 N 轮会跳到
  /// 错误的音频位置——按轮定位是整个练习入口，不能错。
  static const int failureSilenceMs = 1200;

  /// 送入 TTS 的单段文本上限（端点硬限制 1000，留余量）。
  static const int maxSynthesisChars = 900;

  final TtsEngine _engine;
  final RealMeetingStore _store;
  final AudioToolkit _audio;

  RealMeetingBaker({
    required TtsEngine engine,
    required RealMeetingStore store,
    AudioToolkit? audio,
  })  : _engine = engine,
        _store = store,
        _audio = audio ?? FfmpegAudioToolkit();

  // ---------------------------------------------------------------------
  // 合成
  // ---------------------------------------------------------------------

  /// 合成整场会议。
  ///
  /// [resume] 为真时复用已落盘且上次未失败的组——这是"60 分钟会议合成到一半
  /// 被停掉，下次接着来"的实现方式（spec: 长会议的续跑烘焙）。
  ///
  /// [forceGroups] 里的组**强制重合成**，且走"临时文件 → 成功后 rename 覆盖"
  /// 的路径：失败时保留旧音频。改音色后的重烘依赖这一点——先删后建会让一次
  /// 误操作毁掉整段音频。
  ///
  /// [shouldCancel] 只在**组与组之间**检查：一次 TTS 请求中途打断只会留下半截
  /// 文件，没有收益。
  Future<RealMeetingBakeResult> bake(
    RealMeeting meeting, {
    required Map<String, ResolvedSpeaker> speakers,
    RealMeetingBakeProgress? onProgress,
    bool resume = true,
    Set<int> forceGroups = const {},
    bool Function()? shouldCancel,
  }) async {
    final groups = ContinuationMerger.group(meeting.turns);
    final turnsDir = _store.turnsDir(meeting.id);
    await turnsDir.create(recursive: true);

    // 上一次失败过的组不复用：它们落盘的是静音占位，复用等于永远修不好。
    final previous = resume ? await _store.loadBakeState(meeting.id) : null;
    final previousGroups = previous?.groups ?? const <TurnGroupAudio>[];
    final previousFailed = <int>{
      for (var i = 0; i < previousGroups.length; i++)
        if (previousGroups[i].failed) i,
    };

    // 以旧状态为底：未处理的组（例如被取消掉的）保持原样，不会被写成空条目。
    final groupAudios = <TurnGroupAudio>[
      for (var i = 0; i < groups.length; i++)
        i < previousGroups.length
            ? previousGroups[i].copyWith(turnIndices: groups[i].turnIndices)
            : TurnGroupAudio(
                turnIndices: groups[i].turnIndices,
                fileName: groupAudioFileName(i),
              ),
    ];
    final failures = <int, String>{};
    var cancelled = false;

    for (var i = 0; i < groups.length; i++) {
      if (shouldCancel?.call() ?? false) {
        cancelled = true;
        break;
      }
      final group = groups[i];
      final fileName = groupAudioFileName(i);
      final file = File(p.join(turnsDir.path, fileName));
      final speaker = speakers[group.slotId];
      final voice = speaker?.voiceId ?? MyIdentity.defaultVoiceId;
      final forced = forceGroups.contains(i);

      onProgress?.call(i, groups.length, speaker?.displayName ?? group.slotId);

      // 续跑：文件已在且上次没失败 → 直接复用，不再请求 TTS。
      if (!forced &&
          resume &&
          !previousFailed.contains(i) &&
          await file.exists() &&
          await file.length() > 0) {
        continue;
      }

      final text = sanitizeForSynthesis(
          ContinuationMerger.synthesisText(meeting.turns, group));
      if (text.isEmpty) {
        failures[i] = '该组文本为空';
        if (!forced) {
          await _audio.writeSilence(file.path, failureSilenceMs);
          groupAudios[i] = groupAudios[i].copyWith(failed: true, voiceId: voice);
        }
        continue;
      }

      // 强制重烘走临时文件；普通烘焙直接写目标（没有更旧的东西要保护）。
      final target = forced
          ? File(p.join(turnsDir.path, '$fileName.new'))
          : file;
      final ok = await _synthesizeToFile(
        text: text,
        voice: voice,
        target: target,
        tag: '${meeting.id}_g$i',
        turnsDir: turnsDir,
      );

      if (ok) {
        if (forced) {
          // rename 在同一文件系统内是原子的：要么新音频就位，要么旧的原封不动。
          await target.rename(file.path);
        }
        groupAudios[i] =
            groupAudios[i].copyWith(fileName: fileName, failed: false, voiceId: voice);
        failures.remove(i);
        continue;
      }

      failures[i] = '合成失败';
      if (forced) {
        // 保留旧音频与旧音色记录：这一组仍然"待更新"，但用户还能听。
        if (await target.exists()) {
          try {
            await target.delete();
          } catch (_) {}
        }
        continue;
      }
      await _audio.writeSilence(file.path, failureSilenceMs);
      groupAudios[i] = groupAudios[i].copyWith(failed: true, voiceId: voice);
    }

    onProgress?.call(groups.length, groups.length, '');

    final rebuilt = await rebuildAudio(
      meeting,
      speakers: speakers,
      groups: groupAudios,
    );
    // 落盘：重建（插入回答、改音色）与续跑都靠这份状态决定"哪些组已经有音频"。
    // 不写回去，下次打开会议就找不到任何已合成的组。
    await _store.saveBakeState(meeting.id, rebuilt.$2);
    return RealMeetingBakeResult(
      state: rebuilt.$2,
      failures: failures,
      clip: rebuilt.$1,
      cancelled: cancelled,
    );
  }

  /// 合成一组文本到目标文件。
  ///
  /// 超长文本按句子切分后逐段合成再拼回——端点对单次 input 有 1000 字硬限制，
  /// 不切就整组丢失。
  Future<bool> _synthesizeToFile({
    required String text,
    required String voice,
    required File target,
    required String tag,
    required Directory turnsDir,
  }) async {
    final parts = ClipBaker.splitLongTurn(text, limit: maxSynthesisChars);
    final tmpDir = Directory(p.join(turnsDir.path, '.tmp'));
    await tmpDir.create(recursive: true);

    final partFiles = <String>[];
    var ok = true;
    for (var k = 0; k < parts.length; k++) {
      final bytes = await _synthesize(parts[k], voice, '${tag}_p$k');
      if (bytes == null) {
        ok = false;
        break;
      }
      for (var j = 0; j < bytes.length; j++) {
        final partFile = File(p.join(tmpDir.path, '${tag}_p${k}_$j.mp3'));
        await partFile.writeAsBytes(bytes[j], flush: true);
        partFiles.add(partFile.path);
      }
    }

    try {
      if (!ok || partFiles.isEmpty) return false;
      if (partFiles.length == 1) {
        await File(partFiles.single).copy(target.path);
      } else {
        // 多段拼接失败必须让调用方知道：曾经这里会静默只保留第一段，
        // 产出一条被腰斩的音频而界面报成功。
        await _audio.concat(partFiles, target.path);
      }
      return await target.exists() && await target.length() > 0;
    } catch (e) {
      debugPrint('[RealMeetingBaker] "$tag" 拼接失败: $e');
      return false;
    } finally {
      for (final f in partFiles) {
        try {
          final file = File(f);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  /// 合成一段文本，失败时重试。返回非空音频片段列表，全失败返回 null。
  Future<List<List<int>>?> _synthesize(
      String text, String voice, String tag) async {
    Object? lastError;
    for (var attempt = 0; attempt <= turnRetries; attempt++) {
      try {
        final bytes = await _engine.synthesize(
          text,
          const TtsSynthesisConfig(
            mode: TtsMode.customAi,
            useSystemAiConfig: true,
          ).copyWith(customVoiceId: voice),
        );
        if (bytes.isNotEmpty) return [bytes];
        lastError = '返回空音频';
      } catch (e) {
        lastError = e;
        // 配额耗尽重试多少次都一样，立即放弃这一组，让整场标记失败等配额恢复。
        if (_isQuotaExhausted(e)) {
          debugPrint('[RealMeetingBaker] "$tag" 配额耗尽，跳过重试: $e');
          return null;
        }
        if (_isCensorshipRejection(e)) {
          final finer = _splitFiner(text);
          if (finer.length > 1) {
            final parts = <List<int>>[];
            var ok = true;
            for (var i = 0; i < finer.length; i++) {
              final sub = await _synthesize(finer[i], voice, '${tag}_f$i');
              if (sub == null || sub.isEmpty) {
                ok = false;
                break;
              }
              parts.addAll(sub);
            }
            if (ok) return parts;
            lastError = '内容审查拒绝，细分后仍失败';
          }
        }
      }
      if (attempt < turnRetries) {
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    debugPrint('[RealMeetingBaker] "$tag" 合成失败: $lastError');
    return null;
  }

  static bool _isQuotaExhausted(Object error) {
    final text = error.toString();
    return text.contains('402') ||
        text.contains('quota_exceeded') ||
        text.contains('quota exceeded');
  }

  static bool _isCensorshipRejection(Object error) {
    final text = error.toString();
    return text.contains('451') || text.contains('censorship');
  }

  /// 更细的切分（按词，120 字一块），用于绕开整段内容审查。
  static List<String> _splitFiner(String text, {int limit = 120}) {
    if (text.length <= limit) return [text];
    final out = <String>[];
    var chunk = '';
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final candidate = chunk.isEmpty ? word : '$chunk $word';
      if (candidate.length <= limit) {
        chunk = candidate;
      } else {
        if (chunk.isNotEmpty) out.add(chunk);
        chunk = word;
      }
    }
    if (chunk.isNotEmpty) out.add(chunk);
    return out.isEmpty ? [text] : out;
  }

  /// 合成一段插入的回答，写到该会议的逐轮目录。
  ///
  /// 与整篇共用一个目录：重建时按同一套路径解析，回答与原始组没有"两个
  /// 音频源"之分。
  Future<String?> bakeAnswer({
    required String meetingId,
    required String textEn,
    required String voiceId,
    required String fileName,
  }) async {
    final text = sanitizeForSynthesis(textEn);
    if (text.isEmpty) return null;
    final turnsDir = _store.turnsDir(meetingId);
    await turnsDir.create(recursive: true);
    final target = File(p.join(turnsDir.path, fileName));
    final ok = await _synthesizeToFile(
      text: text,
      voice: voiceId,
      target: target,
      tag: '${meetingId}_${p.basenameWithoutExtension(fileName)}',
      turnsDir: turnsDir,
    );
    return ok ? fileName : null;
  }

  // ---------------------------------------------------------------------
  // 重建
  // ---------------------------------------------------------------------

  /// 用已落盘的逐组音频 + 回答音频重建整篇音频与素材。
  ///
  /// 返回 `(Clip?, MeetingBakeState)`；没有任何可用音频时 Clip 为 null。
  ///
  /// [groups] 为 null 时从已存的合成状态读取；[answers] 为 null 时从仓库读取。
  Future<(Clip?, MeetingBakeState)> rebuildAudio(
    RealMeeting meeting, {
    required Map<String, ResolvedSpeaker> speakers,
    List<TurnGroupAudio>? groups,
    List<InsertedAnswer>? answers,
  }) async {
    final state = groups ?? (await _store.loadBakeState(meeting.id))?.groups;
    if (state == null || state.isEmpty) {
      return (null, const MeetingBakeState());
    }
    final allAnswers = answers ?? await _store.loadAnswers(meeting.id);
    final turnsDir = _store.turnsDir(meeting.id);
    final audioFile = _store.audioFile(meeting.id);

    // 轮次 → 组下标，用来把回答挂在它所属的组之后。
    final groupOfTurn = <int, int>{};
    for (var g = 0; g < state.length; g++) {
      for (final t in state[g].turnIndices) {
        groupOfTurn[t] = g;
      }
    }

    // 回答按"锚点所在组"归类；锚点越界的标记为失效、不参与拼接。
    final answersAfterGroup = <int, List<InsertedAnswer>>{};
    final stale = <InsertedAnswer>[];
    for (final a in allAnswers) {
      if (a.audioFile.isEmpty) continue;
      final g = groupOfTurn[a.anchorTurnIndex];
      if (g == null) {
        stale.add(a);
        continue;
      }
      answersAfterGroup.putIfAbsent(g, () => []).add(a);
    }

    // 拼接序列：组 → 坠在该组之后的回答 → 下一组。
    final sequence = <_Segment>[];
    for (var g = 0; g < state.length; g++) {
      final grp = state[g];
      sequence.add(_Segment(
        kind: _SegmentKind.group,
        filePath: p.join(turnsDir.path, grp.fileName),
        groupIndex: g,
        turnIndices: grp.turnIndices,
      ));
      for (final a in answersAfterGroup[g] ?? const <InsertedAnswer>[]) {
        sequence.add(_Segment(
          kind: _SegmentKind.answer,
          filePath: p.join(turnsDir.path, a.audioFile),
          answer: a,
        ));
      }
    }

    // 没有任何实体文件时不必拼一条空音频。
    final existing = <_Segment>[];
    for (final seg in sequence) {
      if (await File(seg.filePath).exists()) existing.add(seg);
    }
    if (existing.isEmpty) {
      return (null, MeetingBakeState(groups: state));
    }

    // 无条件拼接。曾经这里套着 `if (_audio.isAvailable)`——那个属性背后是
    // 惰性解析，启动后恒为 false，于是整篇音频从来没被拼出来，而素材照样
    // 以"有音频"的形态进了索引（design D1）。拼接失败就记下来，由下面
    // 「文件是否真的存在」决定发布形态。
    var concatError = '';
    try {
      await audioFile.parent.create(recursive: true);
      await _audio.concat(
          existing.map((e) => e.filePath).toList(), audioFile.path);
    } catch (e) {
      concatError = '$e';
      debugPrint('[RealMeetingBaker] 整篇拼接失败: $e');
    }
    final audioReady = concatError.isEmpty && await audioFile.exists();

    // 逐段探时长并累加，得到每组与每条回答的起止。
    var cursor = 0;
    final timedGroups = List<TurnGroupAudio>.from(state);
    final answerSpans = <String, (int, int)>{};
    for (final seg in existing) {
      final dur = await _audio.probeDurationMs(seg.filePath);
      if (seg.kind == _SegmentKind.group) {
        timedGroups[seg.groupIndex!] =
            timedGroups[seg.groupIndex!].copyWith(startMs: cursor, endMs: cursor + dur);
      } else {
        answerSpans[seg.answer!.id] = (cursor, cursor + dur);
      }
      cursor += dur;
    }
    final totalMs = cursor;

    // 组装 Clip 轮次：按组顺序 + 回答穿插。
    final clipTurns = <SpeakerTurn>[];
    final byIndex = {for (final t in meeting.turns) t.index: t};
    for (var g = 0; g < timedGroups.length; g++) {
      final grp = timedGroups[g];
      // 整组用组首说话人的音色合成（续句合并的直接后果）。组内后几轮的
      // **展示名仍是原文里的说话人**——展示层不合并；但 `voice` 必须记成
      // 实际念它的那个音色，否则"音色分配可追溯"就是假的。
      //
      // **优先用组记录的实际音色**：用户改了设定但还没重新合成时，磁盘上的
      // 音频仍是旧音色，`Clip` 写新音色会让追溯变成猜测。
      final configuredVoice = grp.turnIndices.isEmpty
          ? MyIdentity.defaultVoiceId
          : speakers[byIndex[grp.turnIndices.first]?.slotId ?? '']?.voiceId ??
              MyIdentity.defaultVoiceId;
      final groupVoice =
          grp.voiceId.isNotEmpty ? grp.voiceId : configuredVoice;
      for (final idx in grp.turnIndices) {
        final turn = byIndex[idx];
        if (turn == null) continue;
        final sp = speakers[turn.slotId];
        clipTurns.add(SpeakerTurn(
          speaker: sp?.displayName ?? turn.slotId,
          role: '',
          rawText: turn.text,
          synthesisText: sanitizeForSynthesis(turn.text),
          voice: groupVoice,
          startMs: grp.startMs,
          endMs: grp.endMs,
        ));
      }
      for (final a in answersAfterGroup[g] ?? const <InsertedAnswer>[]) {
        final span = answerSpans[a.id];
        if (span == null) continue;
        clipTurns.add(SpeakerTurn(
          speaker: a.speakerName,
          role: InsertedAnswer.roleMarker,
          rawText: a.textEn,
          synthesisText: sanitizeForSynthesis(a.textEn),
          voice: a.voiceId,
          startMs: span.$1,
          endMs: span.$2,
        ));
      }
    }

    final clip = Clip(
      id: meeting.id,
      scene: MeetingScene.realMeeting,
      title: meeting.title,
      // 相对素材根目录（it_meeting_listening/），与既有素材的解析方式一致。
      //
      // **只有文件真的存在才写路径**：写一条指向不存在文件的记录，等于在
      // 索引里撒谎——用户点播放得到"尚未生成音频"，点「生成音频」又说
      // "没有待生成的素材"，两边都堵死（design D2）。
      audioPath:
          audioReady ? 'real_meetings/audio/${meeting.id}.mp3' : '',
      durationMs: totalMs,
      turns: clipTurns,
      source: ClipSource(
        sourceId: 'real-meeting',
        site: '真实会议',
        pageUrl: meeting.sourcePath,
        column: '真实会议',
        license: '本地生成',
      ),
      summary: '${clipTurns.length} 轮 · ${speakers.length} 个说话人'
          '${stale.isEmpty ? '' : ' · ${stale.length} 条回答锚点失效'}'
          '${audioReady ? '' : ' · 整篇音频尚未生成'}',
    );

    final newState = MeetingBakeState(
      // 保留原组的失败标记：重建不改变"这一组合成失败过"的事实。
      groups: [
        for (var g = 0; g < timedGroups.length; g++)
          timedGroups[g].copyWith(failed: state[g].failed),
      ],
      audioFile: '${meeting.id}.mp3',
      totalMs: totalMs,
      bakedAt: DateTime.now(),
    );
    return (clip, newState);
  }
}

/// 拼接序列里的一项。
enum _SegmentKind { group, answer }

class _Segment {
  final _SegmentKind kind;
  final String filePath;
  final int? groupIndex;
  final List<int> turnIndices;
  final InsertedAnswer? answer;

  const _Segment({
    required this.kind,
    required this.filePath,
    this.groupIndex,
    this.turnIndices = const [],
    this.answer,
  });
}
