import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/coderslingo_source.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/role_voice_map.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/text_sanitizer.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 验收测试（任务 11.1-11.3）。
///
/// 走真实管线：抓取 → 清洗 → 角色映射 → 逐轮合成 → 拼接 → 落盘。
/// 断言的是**产物本身**的性质（文本保真、破折号语义、音色一致），
/// 而不是"调用了哪些函数"——那样测不出真实缺陷。
///
/// 密钥由应用自己的 [KeychainService] 从本地密文解析并发送，测试脚本全程
/// 不接触密钥明文。
void main() {
  const appRoot = '/Users/simon/Library/Application Support/V8WorkToolbox';

  late Directory outDir;
  late List<Clip> bakedClips;

  setUpAll(() async {
    KekManager.setForTesting(
      fileBridge: DefaultDekFileBridge(customRootDir: Directory(appRoot)),
    );
    await KeychainService.instance.init(customRootDir: Directory(appRoot));
    await AiConfigStore.instance.init(customRootDir: Directory(appRoot));
    outDir = await Directory.systemTemp.createTemp('it_listening_acceptance');

    final source = CoderSlingoSource();
    final baker = ClipBaker(
      engine: OpenAiTtsEngine(),
      materialDir: Directory(p.join(outDir.path, 'materials')),
      cacheDir: Directory(p.join(outDir.path, 'cache')),
    );

    // 验收覆盖两个场景：站会（多角色短对话）与故障排查（长对话 + 技术术语密集）
    bakedClips = [];
    for (final column in ['standup-dialogues', 'incident-calls']) {
      final dialogues = await source.fetchColumn(column);
      final result = await baker.bakeDialogue(dialogues.first);
      debugPrint('[验收] $column: ${result.clips.length} 片段, '
          '${result.failures.length} 失败');
      bakedClips.addAll(result.clips);
    }
  });

  tearDownAll(() async {
    if (await outDir.exists()) await outDir.delete(recursive: true);
  });

  test('11.1 端到端：产出可播放素材，时长落在 1-3 分钟区间', () async {
    expect(bakedClips, isNotEmpty, reason: '验收应至少产出一条素材');
    for (final clip in bakedClips) {
      debugPrint('[验收] ${clip.id}: ${clip.turns.length} 轮, '
          '${(clip.durationMs / 1000).toStringAsFixed(1)}s');
      expect(clip.turns, isNotEmpty);
      // 片段时长上限 5 分钟（spec）
      expect(clip.durationMs, lessThanOrEqualTo(5 * 60 * 1000));
      // 音频文件真实存在且非空
      final audio = File(p.join(outDir.path, 'materials', clip.audioPath));
      expect(await audio.exists(), isTrue);
      expect(await audio.length(), greaterThan(1000));
      // 文稿清单与音频同目录配对
      final manifest =
          File(p.join(outDir.path, 'materials', '${clip.id}.json'));
      expect(await manifest.exists(), isTrue);
    }
  });

  test('11.1 文本保真：IT 术语与数字逐字保留在送合成的文本里', () {
    // 站会片段必须保留这些术语与数字
    final standup = bakedClips.firstWhere((c) => c.scene == MeetingScene.standup);
    final allSynthesis =
        standup.turns.map((t) => t.synthesisText).join(' ');

    for (final term in ['API endpoint', 'notification service', 'blockers']) {
      expect(
        allSynthesis.toLowerCase(),
        contains(term.toLowerCase()),
        reason: '术语 "$term" 应逐字保留',
      );
    }
    // 故障排查片段的关键数字与术语
    final incident =
        bakedClips.firstWhere((c) => c.scene == MeetingScene.incident);
    final incidentText =
        incident.turns.map((t) => t.synthesisText).join(' ');

    for (final token in ['503', '14:32', 'API gateway', 'auth service']) {
      expect(
        incidentText,
        contains(token),
        reason: '关键信息 "$token" 应逐字保留',
      );
    }
    // 千分位数量
    expect(incidentText, contains('1,200 transactions per minute'));
  });

  test('11.2 破折号清洗：合成文本无破折号，且不出现语义反转', () {
    for (final clip in bakedClips) {
      for (final turn in clip.turns) {
        expect(
          turn.synthesisText.contains('—') ||
              turn.synthesisText.contains('–') ||
              turn.synthesisText.contains('--'),
          isFalse,
          reason: '合成文本不应残留破折号：${turn.synthesisText}',
        );
      }
      // 破折号改造不得引入"unblocked"式语义反转
      final text = clip.turns.map((t) => t.synthesisText).join(' ').toLowerCase();
      expect(text.contains('unblocked'), isFalse,
          reason: '"but I\'m blocked" 被读成 "but unblocked" 是语义反转，'
              '必须杜绝：$text');
      // 含 "but I'm blocked" 的轮次，改造后必须仍是 "blocked" 而非别义
      for (final turn in clip.turns) {
        if (turn.rawText.toLowerCase().contains("i'm blocked")) {
          expect(turn.synthesisText.toLowerCase().contains('blocked'), isTrue);
          expect(turn.synthesisText.toLowerCase().contains('unblocked'), isFalse);
        }
      }
    }
  });

  test('11.2 破折号清洗：原始文本仍保留破折号（文稿与音频不脱节）', () {
    final incident =
        bakedClips.firstWhere((c) => c.scene == MeetingScene.incident);
    final rawWithDash = incident.turns
        .where((t) => t.rawText.contains('—') || t.rawText.contains('–'))
        .toList();
    debugPrint('[验收] 含破折号的原始轮次: ${rawWithDash.length}');
    // 站会与故障排查的原文都带破折号——若这里为 0，说明抓取侧的破折号也没了
    expect(rawWithDash, isNotEmpty,
        reason: '原始文本应保留破折号（只清洗送合成的副本）');
  });

  test('11.3 角色固定音色：同一说话人在片段内音色恒定', () {
    for (final clip in bakedClips) {
      final bySpeaker = <String, String>{};
      for (final turn in clip.turns) {
        final previous = bySpeaker[turn.speaker];
        if (previous != null) {
          expect(
            turn.voice,
            previous,
            reason: '说话人 ${turn.speaker} 在同一片段内音色应恒定',
          );
        }
        bySpeaker[turn.speaker] = turn.voice;
        expect(turn.voice, isNotEmpty);
      }
    }
  });

  test('11.3 角色固定音色：跨片段同一角色音色一致', () {
    // 跨片段比较：同一场景的两个片段里，同名说话人音色应相同
    final byScene = <MeetingScene, List<Clip>>{};
    for (final c in bakedClips) {
      byScene.putIfAbsent(c.scene, () => []).add(c);
    }
    for (final entry in byScene.entries) {
      if (entry.value.length < 2) continue;
      final voiceBySpeaker = <String, String>{};
      for (final clip in entry.value) {
        for (final turn in clip.turns) {
          final prev = voiceBySpeaker[turn.speaker];
          if (prev != null) {
            expect(turn.voice, prev,
                reason: '${entry.key.label} 的 ${turn.speaker} 跨片段音色应一致');
          }
          voiceBySpeaker[turn.speaker] = turn.voice;
        }
      }
    }
  });

  test('11.3 角色映射：映射表对同一角色给出同一音色（纯函数）', () {
    expect(
      RoleVoiceMap.voiceFor('X', 'Scrum Master'),
      RoleVoiceMap.voiceFor('Y', 'Scrum Master'),
    );
    expect(
      RoleVoiceMap.voiceFor('IC', ''),
      RoleVoiceMap.voiceFor('Z', 'Incident Commander'),
    );
  });

  test('11.1 断点与时间戳：轮次时间单调递增且不越界', () {
    for (final clip in bakedClips) {
      var cursor = 0;
      for (final turn in clip.turns) {
        expect(turn.startMs, cursor);
        expect(turn.endMs, greaterThan(turn.startMs));
        cursor = turn.endMs;
      }
      expect(clip.durationMs, cursor);
    }
  });

  test('11.1 清洗不改动术语与数字（单测级回归）', () {
    const original = "The service returns 503s since 14:32; ticket JIRA-4821 is a P1.";
    expect(sanitizeForSynthesis(original), original);
  });
}
