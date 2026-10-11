import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';

/// 资产桥：V8 工坊 ⇄ Toonflow 工作区（spec: 资产导出的内容范围）。
///
/// **只写「内容节点 + 素材文件」这一层**，不写画布连线（edges 恒为空数组）、
/// 不写节点生成状态、不碰模型配置。连线与生成由用户在 Toonflow 工作台内通过
/// 它的 Agent 完成——Toonflow 的 canvas Skill 明确「不通过编辑画布 JSON 绕过
/// 工具」，静态写出的边很可能与用户实际选择的模型能力不匹配，反而造成难以
/// 排查的半成品。
///
/// **密钥边界**：本桥绝不读写 `toonflow_data/settings.json`，诊断与错误文本
/// 也不含其内容。那个文件保存 Toonflow 自己的供应商密钥（明文）。
/// 一次导出的结果。
@immutable
class ExportResult {
  const ExportResult({
    required this.ok,
    this.workspaceDir,
    this.writtenFiles = const <String>[],
    this.skippedNotes = const <String>[],
    this.error,
  });

  const ExportResult.failure(String message)
    : ok = false,
      workspaceDir = null,
      writtenFiles = const <String>[],
      skippedNotes = const <String>[],
      error = message;

  final bool ok;

  /// 写入的工作区目录（`toonflow_data/workspaces/<series-id>/`）。
  final String? workspaceDir;

  /// 实际写入的文件路径清单（报给用户）。
  final List<String> writtenFiles;

  /// 被跳过但用户该知道的事（如「角色 X 没有参考图」）。
  final List<String> skippedNotes;

  final String? error;
}

/// 一次导回中，一个视频与目标片段的对应关系。
@immutable
class ImportAssignment {
  const ImportAssignment({
    required this.segmentId,
    required this.fileName,
    this.shotNumbers = const <int>[],
  });

  /// 目标片段 id（`seg-<n>`）；无法配对时为空串。
  final String segmentId;

  /// 复制到 `segments/`（或 `clips/`）后的文件名。
  final String fileName;

  /// 该片段覆盖的镜号，按分镜顺序。用于向用户说明「这个视频顶掉了哪几镜」。
  final List<int> shotNumbers;
}

/// 一次导回的结果。
@immutable
class ImportResult {
  const ImportResult({
    required this.ok,
    this.imported = const <String>[],
    this.assignments = const <ImportAssignment>[],
    this.unassigned = const <String>[],
    this.error,
  });

  final bool ok;

  /// 已复制到工坊的文件名（相对目标目录）。
  final List<String> imported;

  /// 与片段的对应关系，按分镜顺序（spec: 按分镜顺序写回剧集数据）。
  final List<ImportAssignment> assignments;

  /// 复制成功但没有对应片段可写入的文件名。
  ///
  /// 视频比片段多时才会有。不静默丢弃——用户得知道这几个文件还在工作区里。
  final List<String> unassigned;

  final String? error;
}

class ToonflowAssetBridge {
  ToonflowAssetBridge._();
  static final ToonflowAssetBridge instance = ToonflowAssetBridge._();

  final StudioProjectManager _manager = StudioProjectManager.instance;

  /// 工作区根目录：`toonflow_data/workspaces/`。
  Directory get _workspacesRoot =>
      Directory(p.join(AppPaths.toonflowDataDir.path, 'workspaces'));

  /// 某剧集的工作区目录。
  Directory workspaceDirFor(String seriesId) =>
      Directory(p.join(_workspacesRoot.path, seriesId));

  // -------------------------------------------------------------------------
  // 导出
  // -------------------------------------------------------------------------

  /// 把一个剧集 + 一集导出成 Toonflow 工作区。
  ///
  /// 导出内容（spec: 资产导出的内容范围）：
  /// - 世界观 + 风格词 → 文本节点
  /// - 本集大纲 + 分镜表 → 文本节点
  /// - 角色卡（含基准参考图）→ 图片生成节点 + 素材文件
  /// - 场景卡（含主视图）→ 图片生成节点 + 素材文件
  ///
  /// **幂等**：节点 id 由 `sha1(seriesId:episodeId:kind:localId)` 派生，
  /// 重复导出覆盖同名内容而不是建第二份。
  Future<ExportResult> export({
    required String seriesId,
    required String episodeId,
  }) async {
    try {
      final series = _manager.readSeries(seriesId);
      if (series == null) return const ExportResult.failure('剧集项目已不存在');
      final episode = _manager.readEpisode(seriesId, episodeId);
      if (episode == null) return const ExportResult.failure('目标集已不存在');

      final workspace = workspaceDirFor(seriesId);
      final assetsDir = Directory(p.join(workspace.path, 'assets'));
      if (!assetsDir.existsSync()) {
        await assetsDir.create(recursive: true);
      }

      final written = <String>[];
      final notes = <String>[];
      final nodes = <Map<String, dynamic>>[];

      // --- 世界观 + 风格词 ---
      if (series.worldview.trim().isNotEmpty) {
        final nodeId = _nodeId(seriesId, episodeId, 'outline', 'worldview');
        final text = _renderWorldview(series);
        await _writeTextNode(assetsDir, nodeId, text);
        nodes.add(_textNode(nodeId, '世界观与风格'));
        written.add('assets/$nodeId/content.md');
      }

      // --- 本集大纲 + 分镜表 ---
      final scriptText = _renderScript(series, episode);
      final scriptNodeId = _nodeId(seriesId, episodeId, 'outline', 'script');
      await _writeTextNode(assetsDir, scriptNodeId, scriptText);
      nodes.add(_textNode(scriptNodeId, '第${episode.index}集剧本与分镜'));
      written.add('assets/$scriptNodeId/content.md');

      // --- 角色卡 ---
      final characters = await _manager.listCharacters(seriesId);
      for (final c in characters) {
        final nodeId = _nodeId(seriesId, episodeId, 'character', c.id);
        final copied = await _copyReference(
          assetsDir,
          nodeId,
          _manager.characterDir(seriesId, c.id).path,
          c.referenceImages,
        );
        if (copied.isEmpty) {
          notes.add('角色「${c.name}」没有参考图，Toonflow 侧需要自行生成');
        }
        for (final f in copied) {
          written.add('assets/$nodeId/$f');
        }
        nodes.add(_imageNode(nodeId, '角色 · ${c.name}', c.basePromptPositive));
      }

      // --- 场景卡 ---
      final scenes = await _manager.listScenes(seriesId);
      for (final s in scenes) {
        final nodeId = _nodeId(seriesId, episodeId, 'scene', s.id);
        final copied = await _copyReference(
          assetsDir,
          nodeId,
          _manager.sceneDir(seriesId, s.id).path,
          s.referenceImages,
        );
        for (final f in copied) {
          written.add('assets/$nodeId/$f');
        }
        nodes.add(_imageNode(nodeId, '场景 · ${s.name}', s.promptEn));
      }

      // --- 画布 JSON ---
      //
      // `edges` 恒为空：本桥不替用户决定连线（spec: 写画布内容的权限边界）。
      final canvasFile = File(p.join(workspace.path, '画布1.json'));
      await _writeAtomic(
        canvasFile,
        const JsonEncoder.withIndent('  ').convert({
          'toonflowCanvas': true,
          'nodes': nodes,
          'edges': <Map<String, dynamic>>[],
          'viewport': {'x': 0, 'y': 0, 'zoom': 1},
        }),
      );
      written.add('画布1.json');

      return ExportResult(
        ok: true,
        workspaceDir: workspace.path,
        writtenFiles: written,
        skippedNotes: notes,
      );
    } catch (e) {
      return ExportResult.failure('$e');
    }
  }

  // -------------------------------------------------------------------------
  // 导回
  // -------------------------------------------------------------------------

  /// 把 Toonflow 工作区里新产生的视频归集回工坊。
  ///
  /// **复制而非移动**：Toonflow 工作区的原文件保持不动，用户可能仍在
  /// Toonflow 内继续使用它。
  ///
  /// [since] 之前的文件不列——用户通常只要本次导出后新生成的成果。
  Future<List<String>> scanNewVideos({
    required String seriesId,
    DateTime? since,
  }) async {
    final assetsDir =
        Directory(p.join(workspaceDirFor(seriesId).path, 'assets'));
    if (!assetsDir.existsSync()) return const <String>[];

    final cutoff = since ?? DateTime.fromMillisecondsSinceEpoch(0);
    final result = <String>[];
    for (final entity in assetsDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.mp4' && ext != '.mov' && ext != '.webm') continue;
      if (entity.statSync().modified.isBefore(cutoff)) continue;
      result.add(entity.path);
    }
    result.sort((a, b) =>
        File(b).statSync().modified.compareTo(File(a).statSync().modified));
    return result;
  }

  /// 把选中的视频复制到目标集，并按分镜顺序写回剧集数据。
  ///
  /// [targetIsSegment] 决定落 `segments/` 还是 `clips/`——片段级产物进
  /// `segments/`（写 `StudioSegment.clipPath`），分镜级进 `clips/`（写
  /// `StudioShot.clipPath`）。
  ///
  /// **配对策略**（spec: 按分镜顺序写回剧集数据）：用户勾选的文件按 mtime
  /// 倒序交给本方法，这里反转成分镜顺序，依次填入「还没有 clipPath 的
  /// 片段/分镜」。用户若想指定对应关系，可以在工坊里手工改——本方法只做
  /// 确定性的顺序填充，不猜内容。
  ///
  /// **复制而非移动**：Toonflow 工作区的原文件保持不动，用户可能仍在
  /// Toonflow 内继续使用它。
  Future<ImportResult> importVideos({
    required String seriesId,
    required String episodeId,
    required List<String> sourcePaths,
    bool targetIsSegment = true,
  }) async {
    try {
      final episode = _manager.readEpisode(seriesId, episodeId);
      if (episode == null) {
        return const ImportResult(ok: false, error: '目标集已不存在');
      }

      final dir = targetIsSegment
          ? _manager.episodeSegmentsDir(seriesId, episodeId)
          : _manager.episodeClipsDir(seriesId, episodeId);
      if (!dir.existsSync()) await dir.create(recursive: true);

      // 扫描结果是「新的在前」，写回要按分镜顺序，所以反转。
      final ordered = sourcePaths.reversed.toList();

      final imported = <String>[];
      final assignments = <ImportAssignment>[];
      final unassigned = <String>[];

      if (targetIsSegment) {
        // 只填还没有成片的片段，避免覆盖用户已确认的成果。
        final pending = episode.segments
            .where((s) => s.clipPath == null || s.clipPath!.isEmpty)
            .toList();
        var cursor = 0;
        for (final src in ordered) {
          final name = await _copyInto(dir, src);
          if (name == null) continue;
          imported.add(name);
          if (cursor >= pending.length) {
            unassigned.add(name);
            continue;
          }
          final segment = pending[cursor++];
          assignments.add(ImportAssignment(
            segmentId: segment.id,
            fileName: name,
            shotNumbers: segment.shotNumbers,
          ));
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
        for (final src in ordered) {
          final name = await _copyInto(dir, src);
          if (name == null) continue;
          imported.add(name);
          if (cursor >= pending.length) {
            unassigned.add(name);
            continue;
          }
          final shot = pending[cursor++];
          assignments.add(ImportAssignment(
            segmentId: '',
            fileName: name,
            shotNumbers: <int>[shot.number],
          ));
        }
        if (assignments.isNotEmpty) {
          final byShot = <int, String>{
            for (final a in assignments) a.shotNumbers.first: a.fileName,
          };
          final updated = episode.shots.map((s) {
            final path = byShot[s.number];
            if (path == null) return s;
            // 分镜同样推到 done，理由同片段分支。
            return s.copyWith(clipPath: path, status: ShotGenerationStatus.done);
          }).toList();
          await _manager.saveEpisode(episode.copyWith(shots: updated));
        }
      }

      return ImportResult(
        ok: true,
        imported: imported,
        assignments: assignments,
        unassigned: unassigned,
      );
    } catch (e) {
      return ImportResult(ok: false, error: '$e');
    }
  }

  /// 把一个文件复制进 [dir]，返回新文件名；源不存在返回 null。
  Future<String?> _copyInto(Directory dir, String src) async {
    final file = File(src);
    if (!file.existsSync()) return null;
    // 毫秒时间戳保证同一次归集里多个文件不互相覆盖。
    final name = 'toonflow_${DateTime.now().millisecondsSinceEpoch}'
        '${p.extension(src)}';
    await file.copy(p.join(dir.path, name));
    return name;
  }

  // -------------------------------------------------------------------------
  // 内部：渲染
  // -------------------------------------------------------------------------

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
      buffer.writeln('### 镜头 ${shot.number}（${shot.shotSize.label} · '
          '${shot.durationSec.toStringAsFixed(1)}s）');
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

  // -------------------------------------------------------------------------
  // 内部：节点构造与文件
  // -------------------------------------------------------------------------

  /// 确定性节点 id（spec: 导出落盘结构的幂等要求）。
  ///
  /// 同一份内容重复导出得到同一个 id，覆盖而非堆积。Toonflow 的节点 id 同时
  /// 是 `assets/<nodeId>/` 的目录名，随机 id 会让重复导出留下孤儿素材目录。
  String _nodeId(
    String seriesId,
    String episodeId,
    String kind,
    String localId,
  ) {
    final digest = sha1
        .convert(utf8.encode('$seriesId:$episodeId:$kind:$localId'))
        .toString();
    return 'v8-$kind-${digest.substring(0, 12)}';
  }

  Map<String, dynamic> _textNode(String nodeId, String label) => {
    'id': nodeId,
    'type': 'remote-textNode',
    'position': {'x': 0, 'y': 0},
    'data': {
      'label': label,
      'textPath': 'assets/$nodeId/content.md',
    },
  };

  Map<String, dynamic> _imageNode(String nodeId, String label, String prompt) => {
    'id': nodeId,
    'type': 'remote-imageGenerationNode',
    'position': {'x': 0, 'y': 0},
    'data': {
      'label': label,
      'prompt': prompt,
    },
  };

  /// 把卡片引用的第一张参考图拷进 `assets/<nodeId>/`。
  Future<List<String>> _copyReference(
    Directory assetsDir,
    String nodeId,
    String cardDir,
    List<String> referenceImages,
  ) async {
    if (referenceImages.isEmpty) return const <String>[];
    final target = Directory(p.join(assetsDir.path, nodeId));
    if (!target.existsSync()) await target.create(recursive: true);

    final source =
        File(p.join(cardDir, referenceImages.first));
    if (!source.existsSync()) return const <String>[];
    final name = p.basename(source.path);
    await source.copy(p.join(target.path, name));
    return <String>[name];
  }

  Future<void> _writeTextNode(
    Directory assetsDir,
    String nodeId,
    String text,
  ) async {
    final dir = Directory(p.join(assetsDir.path, nodeId));
    if (!dir.existsSync()) await dir.create(recursive: true);
    await _writeAtomic(File(p.join(dir.path, 'content.md')), text);
  }

  /// 原子写：先 `.tmp` 再 rename（spec: 导出前确保目录存在 / 写文件用原子写）。
  Future<void> _writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (file.existsSync()) await file.delete();
    await tmp.rename(file.path);
  }
}
