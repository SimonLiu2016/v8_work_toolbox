import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_library.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/coderslingo_source.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 试点烘焙（任务组 0）。
///
/// 走的是**正式管线**（[CoderSlingoSource] → [ClipBaker] → [ClipLibrary]），
/// 不是一次性脚本：试点若通过，第 5 组的实现即已就位。
///
/// 密钥由应用自己的 [KeychainService] 从本地密文解析并发送，测试脚本全程
/// 不接触密钥明文。
void main() {
  const appRoot = '/Users/simon/Library/Application Support/V8WorkToolbox';

  /// 每次运行用**独立**目录。
  ///
  /// 固定目录会让并行运行互相删对方的目录（`PathNotFoundException`）——
  /// 那是测试自身的数据竞争，与产品代码无关，但会让 CI 偶发红。
  late Directory outDir;

  setUpAll(() async {
    KekManager.setForTesting(
      fileBridge: DefaultDekFileBridge(customRootDir: Directory(appRoot)),
    );
    await KeychainService.instance.init(customRootDir: Directory(appRoot));
    await AiConfigStore.instance.init(customRootDir: Directory(appRoot));
    outDir = await Directory.systemTemp.createTemp('it_listening_pilot');
  });

  tearDownAll(() async {
    if (await outDir.exists()) await outDir.delete(recursive: true);
  });

  test('试点：抓取 + 烘焙站会 / 故障排查 / Sprint 规划各一条', () async {
    final source = CoderSlingoSource();
    final materialDir = Directory(p.join(outDir.path, 'materials'));
    final cacheDir = Directory(p.join(outDir.path, 'cache'));
    final library = ClipLibrary(materialDir);

    final baker = ClipBaker(
      engine: OpenAiTtsEngine(),
      materialDir: materialDir,
      cacheDir: cacheDir,
    );

    final pilotColumns = [
      'standup-dialogues',
      'incident-calls',
      'sprint-planning',
    ];

    final allClips = <Clip>[];
    final report = <String, dynamic>{};

    for (final column in pilotColumns) {
      final dialogues = await source.fetchColumn(column);
      debugPrint('COLUMN $column: ${dialogues.length} blocks');
      report[column] = <String, dynamic>{'blocks': dialogues.length};

      // 试点只取每个栏目的第一块——先验证质量，再谈铺量。
      final dialogue = dialogues.first;
      final result = await baker.bakeDialogue(dialogue,
          onProgress: (id, done, total) {
        if (done < total) debugPrint('  BAKING $id ($done/$total)');
      });

      for (final failure in result.failures.entries) {
        debugPrint('  FAILED ${failure.key}: ${failure.value}');
      }
      for (final clip in result.clips) {
        debugPrint('  CLIP ${clip.id} scene=${clip.scene.id} turns=${clip.turns.length} '
            'dur=${(clip.durationMs / 1000).toStringAsFixed(1)}s');
        for (final t in clip.turns) {
          debugPrint('    [${t.displayName}] voice=${t.voice} '
              '${(t.durationMs / 1000).toStringAsFixed(1)}s :: ${t.rawText}');
        }
      }
      allClips.addAll(result.clips);
      report[column]['clips'] = result.clips.length;
      report[column]['failures'] = result.failures.length;
    }

    await library.rebuildIndex(allClips);
    debugPrint('INDEX: ${allClips.length} clips written');

    await File(p.join(outDir.path, 'pilot_report.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );

    expect(allClips, isNotEmpty, reason: '试点应至少产出一条素材');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
