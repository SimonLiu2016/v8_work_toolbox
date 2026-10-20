import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import 'infinite_canvas_bridge_models.dart';

/// 无限画布资产桥：AI 短视频工坊 ⇄ 无限画布（spec: 资产导出的内容范围 /
/// 导回的推送与归集）。
///
/// **与 Toonflow 桥的根本差异**：不经过共享目录。无限画布的密钥、画布、素材
/// 与生成记录全在浏览器本地存储里，宿主机文件系统上一个字节都没有——导出由
/// 画布侧插件从 HTTP 拉取，导回由插件把 Blob POST 回来（design D1）。
///
/// **只写「内容节点与其素材」这一层**：不写画布连线（connections 恒为空）、
/// 不写节点生成状态、不碰模型配置。连线与生成由用户在无限画布内完成
/// （spec: 写画布内容的权限边界）。
///
/// **密钥边界**：本桥绝不读写无限画布的配置文件内容。那个文件明文保存用户的
/// API Key 与 WebDAV 密码（design D8）。
class InfiniteCanvasAssetBridge {
  InfiniteCanvasAssetBridge._();
  static final InfiniteCanvasAssetBridge instance =
      InfiniteCanvasAssetBridge._();

  final StudioProjectManager _manager = StudioProjectManager.instance;

  /// 参考图 URL 的宿主。由资产桥服务在启动时注入——没有它就无法生成可被
  /// 浏览器拉取的 URL。
  String? referenceBaseUrl;

  // -------------------------------------------------------------------------
  // 导出
  // -------------------------------------------------------------------------

  /// 把一个剧集 + 一集渲染成画布节点载荷（design D3）。
  ///
  /// 导出内容（spec: 资产导出的内容范围）：
  /// - 世界观 + 风格词 → 文本节点
  /// - 本集大纲 + 分镜表 → 文本节点
  /// - 角色卡（含基准参考图）→ 图片节点
  /// - 场景卡（含主视图）→ 图片节点
  ///
  /// **幂等**：节点 id 由 `sha1(seriesId:episodeId:kind:localId)` 派生，
  /// 重复导出命中同一批 id 而不是建第二套。
  Future<CanvasExportPayload> buildExport({
    required String seriesId,
    required String episodeId,
  }) async {
    final series = _manager.readSeries(seriesId);
    if (series == null) {
      throw StateError('剧集项目已不存在');
    }
    final episode = _manager.readEpisode(seriesId, episodeId);
    if (episode == null) {
      throw StateError('目标集已不存在');
    }

    final nodes = <CanvasNodeSpec>[];
    final notes = <String>[];

    // --- 世界观 + 风格词 ---
    if (series.worldview.trim().isNotEmpty ||
        series.styleTokens.trim().isNotEmpty) {
      final nodeId = canvasNodeId(seriesId, episodeId, 'outline', 'worldview');
      nodes.add(
        CanvasNodeSpec(
          id: nodeId,
          kind: 'text',
          title: '世界观与风格',
          markdown: _renderWorldview(series),
          metadata: _v8Meta(
            seriesId: seriesId,
            episodeId: episodeId,
            entityKind: 'worldview',
            entityId: 'worldview',
          ),
        ),
      );
    }

    // --- 本集大纲 + 分镜表 ---
    final scriptNodeId = canvasNodeId(seriesId, episodeId, 'outline', 'script');
    nodes.add(
      CanvasNodeSpec(
        id: scriptNodeId,
        kind: 'text',
        title: '第${episode.index}集剧本与分镜',
        markdown: _renderScript(series, episode),
        metadata: _v8Meta(
          seriesId: seriesId,
          episodeId: episodeId,
          entityKind: 'script',
          entityId: 'script',
        ),
      ),
    );

    // --- 角色卡 ---
    final characters = await _manager.listCharacters(seriesId);
    for (final c in characters) {
      final nodeId = canvasNodeId(seriesId, episodeId, 'character', c.id);
      final imageUrl = await _referenceUrl(
        seriesId,
        _manager.characterDir(seriesId, c.id).path,
        c.referenceImages,
      );
      if (imageUrl == null) {
        notes.add('角色「${c.name}」没有参考图，需要你在画布上自行生成');
      }
      nodes.add(
        CanvasNodeSpec(
          id: nodeId,
          kind: 'image',
          title: '角色 · ${c.name}',
          prompt: c.basePromptPositive,
          negativePrompt: c.basePromptNegative,
          imageUrl: imageUrl ?? '',
          metadata: _v8Meta(
            seriesId: seriesId,
            episodeId: episodeId,
            entityKind: 'character',
            entityId: c.id,
          ),
        ),
      );
    }

    // --- 场景卡 ---
    final scenes = await _manager.listScenes(seriesId);
    for (final s in scenes) {
      final nodeId = canvasNodeId(seriesId, episodeId, 'scene', s.id);
      final imageUrl = await _referenceUrl(
        seriesId,
        _manager.sceneDir(seriesId, s.id).path,
        s.referenceImages,
      );
      if (imageUrl == null) {
        notes.add('场景「${s.name}」没有参考图，需要你在画布上自行生成');
      }
      nodes.add(
        CanvasNodeSpec(
          id: nodeId,
          kind: 'image',
          title: '场景 · ${s.name}',
          prompt: s.promptEn,
          imageUrl: imageUrl ?? '',
          metadata: _v8Meta(
            seriesId: seriesId,
            episodeId: episodeId,
            entityKind: 'scene',
            entityId: s.id,
          ),
        ),
      );
    }

    return CanvasExportPayload(
      seriesId: seriesId,
      episodeId: episodeId,
      episodeIndex: episode.index,
      nodes: nodes,
      skippedNotes: notes,
    );
  }

  /// 剧集 + 集列表，供插件面板下拉选择。
  Future<List<Map<String, dynamic>>> listSelectableEpisodes() async {
    final result = <Map<String, dynamic>>[];
    for (final series in await _manager.listSeries()) {
      final episodes = await _manager.listEpisodes(series.id);
      result.add({
        'seriesId': series.id,
        'seriesName': series.name,
        'episodes': episodes
            .map((e) => {'episodeId': e.id, 'index': e.index, 'title': e.title})
            .toList(),
      });
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // 导回
  // -------------------------------------------------------------------------

  /// 把画布侧 POST 回来的视频归集进工坊。
  ///
  /// [targetIsSegment] 决定落 `segments/`（写 `StudioSegment.clipPath`）还是
  /// `clips/`（写 `StudioShot.clipPath`）。
  ///
  /// **配对策略**（spec: 按分镜顺序写回剧集数据）：按 mtime 倒序收到的条目在
  /// 这里反转成分镜顺序，依次填入「还没有 clipPath 的片段/分镜」。用户若想
  /// 指定对应关系，可以在工坊里手工改——本方法只做确定性的顺序填充，不猜内容。
  ///
  /// **复制而非移动**：画布侧的原始产物不动，用户可能仍在画布里使用它。
  Future<CanvasImportResult> importVideos({
    required String seriesId,
    required String episodeId,
    required List<CanvasVideoEntry> entries,
    bool targetIsSegment = true,
  }) async {
    try {
      final episode = _manager.readEpisode(seriesId, episodeId);
      if (episode == null) {
        return const CanvasImportResult(
          ok: false,
          error: '目标集已不存在',
        );
      }

      final dir = targetIsSegment
          ? _manager.episodeSegmentsDir(seriesId, episodeId)
          : _manager.episodeClipsDir(seriesId, episodeId);
      if (!dir.existsSync()) await dir.create(recursive: true);

      final imported = <String>[];
      final assignments = <CanvasImportAssignment>[];
      final unassigned = <String>[];

      if (targetIsSegment) {
        // 只填还没有成片的片段，避免覆盖用户已确认的成果。
        final pending = episode.segments
            .where((s) => s.clipPath == null || s.clipPath!.isEmpty)
            .toList();
        var cursor = 0;
        for (final entry in entries) {
          final name = entry.fileName;
          final src = File(
            p.join(AppPaths.infiniteCanvasDir.path, 'inbox', name),
          );
          if (!src.existsSync()) {
            unassigned.add(name);
            continue;
          }
          final target = p.join(dir.path, name);
          await src.copy(target);
          imported.add(name);
          if (cursor < pending.length) {
            final segment = pending[cursor];
            assignments.add(
              CanvasImportAssignment(
                segmentId: segment.id,
                fileName: name,
                shotNumbers: segment.shotNumbers,
              ),
            );
            cursor++;
          } else {
            unassigned.add(name);
          }
        }
        if (assignments.isNotEmpty) {
          final byId = <String, String>{
            for (final a in assignments) a.segmentId: a.fileName,
          };
          final updated = episode.segments.map((s) {
            final path = byId[s.id];
            if (path == null) return s;
            // 同时把状态推到 done：clipPath 有了而状态仍是 pending 会让看板
            // 显示「待生成」却带着成片，用户会以为导入失败了。
            return s.copyWith(clipPath: path, status: SegmentStatus.done);
          }).toList();
          await _manager.saveEpisode(episode.copyWith(segments: updated));
        }
      } else {
        final pending = episode.shots
            .where((s) => s.clipPath == null || s.clipPath!.isEmpty)
            .toList();
        var cursor = 0;
        for (final entry in entries) {
          final name = entry.fileName;
          final src = File(
            p.join(AppPaths.infiniteCanvasDir.path, 'inbox', name),
          );
          if (!src.existsSync()) {
            unassigned.add(name);
            continue;
          }
          final target = p.join(dir.path, name);
          await src.copy(target);
          imported.add(name);
          if (cursor < pending.length) {
            final shot = pending[cursor];
            assignments.add(
              CanvasImportAssignment(
                segmentId: 'shot-${shot.number}',
                fileName: name,
                shotNumbers: <int>[shot.number],
              ),
            );
            cursor++;
          } else {
            unassigned.add(name);
          }
        }
        if (assignments.isNotEmpty) {
          final byShot = <int, String>{
            for (final a in assignments) a.shotNumbers.first: a.fileName,
          };
          final updated = episode.shots.map((s) {
            final path = byShot[s.number];
            if (path == null) return s;
            return s.copyWith(clipPath: path);
          }).toList();
          await _manager.saveEpisode(episode.copyWith(shots: updated));
        }
      }

      return CanvasImportResult(
        ok: true,
        imported: imported,
        assignments: assignments,
        unassigned: unassigned,
      );
    } catch (e) {
      return CanvasImportResult(ok: false, error: '$e');
    }
  }


  /// 把一批已暂存的视频归集进工坊（spec: 导回的推送与归集）。
  ///
  /// 按 (seriesId, episodeId, targetIsSegment) 分组分别归集——一次导回可能
  /// 同时涉及多个集，而每个集的「按分镜顺序填空」是独立游标。
  Future<List<({String episodeId, CanvasImportResult result})>> drainStaged({
    required List<StagedVideoInput> staged,
  }) async {
    final groups = <String, List<StagedVideoInput>>{};
    for (final item in staged) {
      final key = '${item.seriesId}|${item.episodeId}|${item.targetIsSegment}';
      groups.putIfAbsent(key, () => <StagedVideoInput>[]).add(item);
    }

    final results = <({String episodeId, CanvasImportResult result})>[];
    for (final entry in groups.entries) {
      final first = entry.value.first;
      final result = await importVideos(
        seriesId: first.seriesId,
        episodeId: first.episodeId,
        entries: entry.value
            .map(
              (e) => CanvasVideoEntry(
                fileName: e.fileName,
                bytes: e.bytes,
                v8: <String, dynamic>{
                  'seriesId': e.seriesId,
                  'episodeId': e.episodeId,
                },
              ),
            )
            .toList(),
        targetIsSegment: first.targetIsSegment,
      );
      results.add((episodeId: first.episodeId, result: result));
    }
    return results;
  }

  /// 把插件 POST 上来的视频字节写进 inbox，返回落盘后的文件名。
  ///
  /// 文件名由 V8 生成而不是信任插件的 `fileName`：后者是用户可见的标题，
  /// 可能含路径分隔符或与既有文件冲突。
  Future<String> stageIncomingVideo({
    required String episodeId,
    required String suggestedName,
    required List<int> bytes,
  }) async {
    final inbox = Directory(p.join(AppPaths.infiniteCanvasDir.path, 'inbox'));
    if (!inbox.existsSync()) await inbox.create(recursive: true);
    final ext = p.extension(suggestedName).toLowerCase();
    final safeExt = (ext == '.mp4' || ext == '.mov' || ext == '.webm')
        ? ext
        : '.mp4';
    final digest = sha1.convert(bytes).toString().substring(0, 12);
    final name = 'canvas-$episodeId-$digest$safeExt';
    final file = File(p.join(inbox.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return name;
  }

  // -------------------------------------------------------------------------
  // 内部：渲染与参考图
  // -------------------------------------------------------------------------

  /// 参考图的可拉取 URL。没有参考图时返回 null。
  ///
  /// URL 指向资产桥的 `/assets/*`，由插件经 `uploadImage` 拉进 IndexedDB
  /// （design D2）。服务未启动时 [referenceBaseUrl] 为 null，此时返回 null
  /// ——图片节点仍会被导出，只是没有内容。
  Future<String?> _referenceUrl(
    String seriesId,
    String cardDir,
    List<String> referenceImages,
  ) async {
    if (referenceImages.isEmpty) return null;
    final base = referenceBaseUrl;
    if (base == null || base.isEmpty) return null;
    final file = File(p.join(cardDir, referenceImages.first));
    if (!file.existsSync()) return null;
    final rel = p
        .relative(file.path, from: AppPaths.videoStudioSeriesDir.path)
        .replaceAll(r'\', '/');
    // 只暴露剧集目录下的文件：/assets/<seriesId>/<...>
    return '$base/assets/$seriesId/$rel';
  }

  Map<String, dynamic> _v8Meta({
    required String seriesId,
    required String episodeId,
    required String entityKind,
    required String entityId,
  }) => {
    'v8': {
      'seriesId': seriesId,
      'episodeId': episodeId,
      'entityKind': entityKind,
      'entityId': entityId,
    },
  };

  String _renderWorldview(StudioSeries series) {
    final buffer = StringBuffer()
      ..writeln('# ${series.name}')
      ..writeln();
    if (series.worldview.trim().isNotEmpty) {
      buffer.writeln('## 世界观');
      buffer.writeln(series.worldview.trim());
      buffer.writeln();
    }
    if (series.styleTokens.trim().isNotEmpty) {
      buffer.writeln('## 风格锁');
      buffer.writeln(series.styleTokens.trim());
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _renderScript(StudioSeries series, StudioEpisode episode) {
    final buffer = StringBuffer()
      ..writeln('# 第${episode.index}集 ${episode.title}')
      ..writeln();
    if (episode.synopsis.trim().isNotEmpty) {
      buffer.writeln('## 本集大纲');
      buffer.writeln(episode.synopsis.trim());
      buffer.writeln();
    }
    buffer.writeln('## 分镜表');
    buffer.writeln();
    for (final shot in episode.shots) {
      buffer.writeln(
        '### 镜头 ${shot.number}（${shot.shotSize.label} · '
        '${shot.durationSec.toStringAsFixed(1)}s）',
      );
      if (shot.actionZh.trim().isNotEmpty) {
        buffer.writeln('- 画面：${shot.actionZh.trim()}');
      }
      if (shot.dialogue.trim().isNotEmpty) {
        buffer.writeln('- 台词：${shot.dialogue.trim()}');
      }
      if (shot.cameraMove.trim().isNotEmpty) {
        buffer.writeln('- 运镜：${shot.cameraMove.trim()}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}
