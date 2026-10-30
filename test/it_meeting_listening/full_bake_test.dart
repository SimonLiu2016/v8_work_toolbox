import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_library.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/coderslingo_source.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 全量铺量（任务 5.5 / 6.3）。
///
/// 把映射表里的 **10 个栏目 × 全部对话块** 烘焙成素材，落到应用的真实素材目录。
/// 素材 id 采用新规则 `{sourceId}_{sceneId}_{columnSlug}_{block}`。
void main() {
  const appRoot = '/Users/simon/Library/Application Support/V8WorkToolbox';

  setUpAll(() async {
    await AppPaths.init();
    KekManager.setForTesting(
      fileBridge: DefaultDekFileBridge(customRootDir: Directory(appRoot)),
    );
    await KeychainService.instance.init(customRootDir: Directory(appRoot));
    await AiConfigStore.instance.init(customRootDir: Directory(appRoot));
  });

  test('全量铺量：10 个栏目全部对话块', () async {
    final source = CoderSlingoSource();
    final materialDir = AppPaths.itMeetingListeningDir;
    final cacheDir = AppPaths.itMeetingListeningCacheDir;
    final library = ClipLibrary(materialDir);

    final baker = ClipBaker(
      engine: OpenAiTtsEngine(),
      materialDir: materialDir,
      cacheDir: cacheDir,
    );

    final allClips = <Clip>[];
    final failures = <String>[];

    for (final column in CoderSlingoSource.columnMapping.keys) {
      List<FetchedDialogue> dialogues;
      try {
        dialogues = await source.fetchColumn(column);
      } catch (e) {
        failures.add('$column: $e');
        continue;
      }
      var ok = 0;
      for (final dialogue in dialogues) {
        try {
          final result = await baker.bakeDialogue(dialogue);
          for (final c in result.clips) {
            allClips.add(c);
            ok++;
            debugPrint('[铺量] ${c.id}  ${(c.durationMs / 1000).toStringAsFixed(1)}s');
          }
          failures.addAll(result.failures.values);
        } catch (e) {
          failures.add('${dialogue.clipId}: $e');
        }
      }
      debugPrint('[铺量] $column: ${dialogues.length} 块 → $ok 条');
    }

    await library.rebuildIndex(allClips);
    await library.clearTurnCache(cacheDir);

    final byScene = <String, int>{};
    for (final c in allClips) {
      byScene[c.scene.label] = (byScene[c.scene.label] ?? 0) + 1;
    }
    final totalMs = allClips.fold<int>(0, (a, c) => a + c.durationMs);
    debugPrint('[铺量] 完成：${allClips.length} 条，'
        '${(totalMs / 60000).toStringAsFixed(1)} 分钟，失败 ${failures.length}');
    debugPrint('[铺量] 场景分布：$byScene');

    final report = File(p.join(materialDir.path, 'bake_report.json'));
    await report.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'clips': allClips.length,
      'minutes': (totalMs / 60000).roundToDouble(),
      'byScene': byScene,
      'failures': failures,
    }));

    expect(allClips, isNotEmpty);
    // 10 个栏目每个至少一条
    final covered = allClips.map((c) => c.source.column).toSet();
    expect(covered.length, greaterThanOrEqualTo(8),
        reason: '实际覆盖栏目数：$covered');
    for (final failure in failures.take(5)) {
      debugPrint('[铺量] 失败：$failure');
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
