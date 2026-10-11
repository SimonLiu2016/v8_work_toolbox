import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_asset_bridge.dart';

/// 画布标记必须排在 JSON 首字段（spec: 写画布内容的权限边界）。
///
/// 上游 `isCanvasFile` 先读 4096 字节文件头，用
/// `/^\s*\{\s*"toonflowCanvas"\s*:\s*true\s*[,}]/` 判定是不是画布。
/// 标记排在 `nodes` 之后就认不出来，工作台不会把文件当画布打开——而这种
/// 失败在 V8 侧毫无症状，只有用户在 Toonflow 里看不到节点时才发现。
void main() {
  test('toonflowCanvas 是画布 JSON 的首字段', () async {
    final tempDir = Directory.systemTemp.createTempSync('canvas_marker');
    AppPaths.overrideRootForTesting(tempDir);
    try {
      final manager = StudioProjectManager.instance;
      final series = await manager.createSeries(name: 's');
      final created = await manager.createEpisode(seriesId: series.id);
      var ep = manager.readEpisode(series.id, created.episode.id)!;
      ep = ep.copyWith(shots: const [
        StudioShot(number: 1, durationSec: 3, actionZh: 'a'),
      ]);
      await manager.saveEpisode(ep);

      final result = await ToonflowAssetBridge.instance.export(
        seriesId: series.id,
        episodeId: created.episode.id,
      );
      final raw = File('${result.workspaceDir}/画布1.json').readAsStringSync();

      // 上游的正则（去掉 Dart 字符串转义后）。
      expect(
        RegExp(r'^\s*\{\s*"toonflowCanvas"\s*:\s*true\s*[,}]').hasMatch(raw),
        isTrue,
        reason: '文件头判定认不出来就不算画布',
      );
      // 顺序断言：解出来的第一个键必须是标记本身。
      final keys =
          (jsonDecode(raw) as Map<String, dynamic>).keys.toList();
      expect(keys.first, 'toonflowCanvas');
    } finally {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  });
}
