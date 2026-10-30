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
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_summarizer.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/coderslingo_source.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 批量铺量（任务 11.7）。
///
/// 把映射表里的每个栏目各烘若干条，落到**应用的真实素材目录**，
/// 供用户直接在工具里播放。
///
/// 这个测试会消耗外部 TTS 配额（每轮一次请求），跑一次约 10-15 分钟。
void main() {
  const appRoot = '/Users/simon/Library/Application Support/V8WorkToolbox';

  /// 每个栏目烘焙的块数（首块 + 后续块）。
  const blocksPerColumn = 4;

  setUpAll(() async {
    // AppPaths 必须在读取任何导出路径之前初始化——它未初始化时直接抛
    // StateError（刻意设计：静默 null 会把路径拼成 "null/xxx"）。
    await AppPaths.init();
    KekManager.setForTesting(
      fileBridge: DefaultDekFileBridge(customRootDir: Directory(appRoot)),
    );
    await KeychainService.instance.init(customRootDir: Directory(appRoot));
    await AiConfigStore.instance.init(customRootDir: Directory(appRoot));
  });



  test('11.7 批量铺量：6 个场景各若干条，落到真实素材目录', () async {
    final source = CoderSlingoSource();
    final materialDir = AppPaths.itMeetingListeningDir;
    final cacheDir = AppPaths.itMeetingListeningCacheDir;
    final library = ClipLibrary(materialDir);

    final baker = ClipBaker(
      engine: OpenAiTtsEngine(),
      materialDir: materialDir,
      cacheDir: cacheDir,
      summarizer: ClipSummarizer(),
    );

    // 已有素材（重跑时不重复烘焙）。
    //
    // **以磁盘上的 manifest 为准，而不是索引**：上一次运行可能已经烘好了
    // 片段但索引写入前就退出了——只看索引会把它们当成"没有"而重做一遍。
    final existingIds = <String>{};
    for (final f in materialDir.listSync().whereType<File>()) {
      final name = f.path.split('/').last;
      if (!name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - 5);
      if (id == 'index' || id == 'bake_report') continue;
      existingIds.add(id);
    }
    debugPrint('[铺量] 磁盘已有素材 ${existingIds.length} 条');

    final allClips = <Clip>[];
    final failures = <String>[];
    var totalTurns = 0;

    for (final column in CoderSlingoSource.columnMapping.keys) {
      final (scene, columnName) = CoderSlingoSource.columnMapping[column]!;
      List<FetchedDialogue> dialogues;
      try {
        dialogues = await source.fetchColumn(column);
      } on ClipFetchException catch (e) {
        failures.add('$columnName: ${e.message}');
        continue;
      }
      debugPrint('[铺量] $columnName: ${dialogues.length} 块可用');

      var baked = 0;
      for (final dialogue in dialogues.take(blocksPerColumn)) {
        // 已烘焙过的块直接跳过（幂等）
        if (existingIds.contains(dialogue.clipId)) {
          // 从磁盘上的 manifest 读回（索引可能还没收录它）
          final manifest = File(p.join(materialDir.path, '${dialogue.clipId}.json'));
          if (await manifest.exists()) {
            try {
              final clip = Clip.fromJson(
                  jsonDecode(await manifest.readAsString()) as Map<String, dynamic>);
              if (!clip.isPlaceholder) {
                allClips.add(clip);
                baked++;
              }
            } catch (_) {
              // manifest 损坏 → 重新烘焙
            }
          }
          continue;
        }
        final result = await baker.bakeDialogue(dialogue);
        for (final c in result.clips) {
          allClips.add(c);
          totalTurns += c.turns.length;
          debugPrint('[铺量]   ${c.id}: ${c.turns.length} 轮, '
              '${(c.durationMs / 1000).toStringAsFixed(1)}s, '
              'summary=${c.summary.isEmpty ? "—" : c.summary}');
        }
        for (final f in result.failures.entries) {
          failures.add('${f.key}: ${f.value}');
        }
        baked += result.clips.length;
      }
      debugPrint('[铺量] $columnName: 本次产出 $baked 条');
    }

    // 索引 = 磁盘上所有 manifest（不只本次产出的）。
    //
    // 只写本次产出会在"增量补烘"时丢掉其它场景的条目——上一轮已烘好的
    // 片段就会从索引里消失，工具里再也看不到。
    final onDisk = <Clip>[];
    for (final f in materialDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final name = f.path.split('/').last;
      if (name == 'index.json' || name == 'bake_report.json') continue;
      try {
        final c = Clip.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        if (!c.isPlaceholder) onDisk.add(c);
      } catch (_) {
        // 损坏的 manifest 跳过
      }
    }
    await library.rebuildIndex(onDisk);
    await library.clearTurnCache(cacheDir);
    allClips
      ..clear()
      ..addAll(onDisk);

    debugPrint('[铺量] 完成：共 ${allClips.length} 条，$totalTurns 轮，'
        '${failures.length} 个失败');

    // 落盘一份报告，便于事后核对
    final byScene = <String, int>{};
    for (final c in allClips) {
      byScene[c.scene.id] = (byScene[c.scene.id] ?? 0) + 1;
    }
    final report = File(p.join(materialDir.path, 'bake_report.json'));
    await report.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'clips': allClips.length,
      'turns': totalTurns,
      'byScene': byScene,
      'failures': failures,
    }));

    expect(allClips, isNotEmpty, reason: '铺量应至少产出一条素材');
    // 每个已映射场景都应有素材
    for (final column in CoderSlingoSource.columnMapping.values) {
      final scene = column.$1;
      expect(
        allClips.where((c) => c.scene == scene).isNotEmpty,
        isTrue,
        reason: '场景 ${scene.label} 应有素材',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
