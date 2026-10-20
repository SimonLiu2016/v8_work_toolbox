import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// 一个待写入画布的节点描述。
///
/// **V8 只决定「有哪些节点、各自是什么内容」**，不决定它们怎么落进画布——
/// 那是插件的职责（design D3）。
@immutable
class CanvasNodeSpec {
  const CanvasNodeSpec({
    required this.id,
    required this.kind,
    required this.title,
    this.markdown = '',
    this.prompt = '',
    this.negativePrompt = '',
    this.imageUrl = '',
    this.metadata = const <String, dynamic>{},
  });

  /// 确定性 id。由剧集/集/实体标识派生，使重复导出幂等（design D3）。
  final String id;

  /// `text` 或 `image`——对应无限画布的内置节点类型。
  final String kind;

  /// 节点标题（给人看的，用户可改，不影响配对）。
  final String title;

  /// 文本节点的内容（Markdown）。
  final String markdown;

  /// 图片节点的生图 Prompt。
  final String prompt;

  /// 图片节点的负向 Prompt。
  final String negativePrompt;

  /// 图片节点参考图的 URL。指向资产桥的 `/assets/*`，而不是 base64
  /// （design D2）。
  final String imageUrl;

  /// 结构化标识。归集时用它直接定位目标分镜/片段，不靠标题文本匹配
  /// （design D4）。
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'markdown': markdown,
    'prompt': prompt,
    'negativePrompt': negativePrompt,
    'imageUrl': imageUrl,
    'metadata': metadata,
  };

  factory CanvasNodeSpec.fromJson(Map<String, dynamic> json) {
    return CanvasNodeSpec(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'text',
      title: json['title'] as String? ?? '',
      markdown: json['markdown'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: json['negativePrompt'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// 一次导出的结果。
@immutable
class CanvasExportPayload {
  const CanvasExportPayload({
    required this.seriesId,
    required this.episodeId,
    required this.episodeIndex,
    required this.nodes,
    this.skippedNotes = const <String>[],
    this.layout = const CanvasLayoutHint(),
  });

  final String seriesId;
  final String episodeId;
  final int episodeIndex;
  final List<CanvasNodeSpec> nodes;

  /// 被跳过但用户该知道的事（如「角色 X 没有参考图」）。
  final List<String> skippedNotes;

  /// 排版建议。插件可以不完全遵循，但堆在一处会让用户第一眼看到一坨。
  final CanvasLayoutHint layout;

  Map<String, dynamic> toJson() => {
    'seriesId': seriesId,
    'episodeId': episodeId,
    'episodeIndex': episodeIndex,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'skippedNotes': skippedNotes,
    'layout': layout.toJson(),
  };


/// 从 JSON 还原 [CanvasExportPayload]（测试与诊断用）。
factory CanvasExportPayload.fromJson(Map<String, dynamic> json) {
  return CanvasExportPayload(
    seriesId: json['seriesId'] as String,
    episodeId: json['episodeId'] as String,
    episodeIndex: json['episodeIndex'] as int,
    nodes: ((json['nodes'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(CanvasNodeSpec.fromJson)
        .toList(),
    skippedNotes: ((json['skippedNotes'] as List?) ?? const [])
        .cast<String>()
        .toList(),
    layout: json['layout'] is Map<String, dynamic>
        ? CanvasLayoutHint.fromJson(json['layout'] as Map<String, dynamic>)
        : const CanvasLayoutHint(),
  );
}
}

/// 导出节点的排版建议（design D3）。
@immutable
class CanvasLayoutHint {
  const CanvasLayoutHint({this.columns = 3, this.gapX = 96, this.gapY = 160});

  final int columns;
  final int gapX;
  final int gapY;

  Map<String, dynamic> toJson() => {
    'columns': columns,
    'gapX': gapX,
    'gapY': gapY,
  };

  factory CanvasLayoutHint.fromJson(Map<String, dynamic> json) {
    return CanvasLayoutHint(
      columns: json['columns'] as int? ?? 3,
      gapX: json['gapX'] as int? ?? 96,
      gapY: json['gapY'] as int? ?? 160,
    );
  }
}

/// 一个待归集的视频。
///
/// [v8] 是节点自身携带的结构化标识（design D4）。
@immutable
class CanvasVideoEntry {
  const CanvasVideoEntry({
    required this.fileName,
    required this.bytes,
    required this.v8,
    this.mimeType = 'video/mp4',
  });

  final String fileName;
  final int bytes;

  /// 来自 `metadata.v8`：seriesId / episodeId / entityKind / entityId。
  final Map<String, dynamic> v8;

  final String mimeType;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'bytes': bytes,
    'v8': v8,
    'mimeType': mimeType,
  };
}

/// 一次归集中，一个视频与目标片段的对应关系。
@immutable
class CanvasImportAssignment {
  const CanvasImportAssignment({
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

  Map<String, dynamic> toJson() => {
    'segmentId': segmentId,
    'fileName': fileName,
    'shotNumbers': shotNumbers,
  };
}

/// 一次归集的结果。
@immutable
class CanvasImportResult {
  const CanvasImportResult({
    required this.ok,
    this.imported = const <String>[],
    this.assignments = const <CanvasImportAssignment>[],
    this.unassigned = const <String>[],
    this.error,
  });

  const CanvasImportResult.failure(String message)
    : ok = false,
      imported = const <String>[],
      assignments = const <CanvasImportAssignment>[],
      unassigned = const <String>[],
      error = message;

  final bool ok;

  /// 已复制到工坊的文件名（相对目标目录）。
  final List<String> imported;

  /// 与片段的对应关系，按分镜顺序（spec: 按分镜顺序写回剧集数据）。
  final List<CanvasImportAssignment> assignments;

  /// 复制成功但没有对应片段可写入的文件名。
  ///
  /// 视频比片段多、或节点不携带本工具元数据时才会有。不静默丢弃——用户得知道
  /// 这几个文件还在画布里。
  final List<String> unassigned;

  final String? error;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'imported': imported,
    'assignments': assignments.map((a) => a.toJson()).toList(),
    'unassigned': unassigned,
    if (error != null) 'error': error,
  };
}

/// 确定性节点 id（spec: 导出节点的可辨识性）。
///
/// 同一份内容重复导出得到同一个 id，覆盖而非堆积。随机 id 会让重复导出在
/// 画布上留下第二套节点。
String canvasNodeId(
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

/// 一个待归集的暂存视频。
///
/// 与 [CanvasVideoEntry] 的区别：这是「已经从画布收到但还没决定落点」的形态，
/// 由工具页的归集动作消费。
@immutable
class StagedVideoInput {
  const StagedVideoInput({
    required this.fileName,
    required this.seriesId,
    required this.episodeId,
    required this.bytes,
    required this.targetIsSegment,
  });

  final String fileName;
  final String seriesId;
  final String episodeId;
  final int bytes;
  final bool targetIsSegment;
}
