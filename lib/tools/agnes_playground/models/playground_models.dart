import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../ai_video_studio/services/video_task_ledger.dart';

/// 试炼场的三个调用通道。
///
/// 分开而不是共用一个"请求"类型：三者的输入形状、产物形态与参数面板都不同
/// （文本没有媒体、图像没有时长、视频有三种模式）。合成一个类型会让每个
/// 消费方都去判"这个字段对本通道有没有意义"。
enum PlaygroundChannel {
  text('text', '文本', 'agnes-2.5-flash'),
  image('image', '图像', 'agnes-image-2.5-flash'),
  video('video', '视频', 'agnes-video-2.5-flash');

  final String id;
  final String label;

  /// 该通道的默认型号。用户在面板里可改。
  final String defaultModel;

  const PlaygroundChannel(this.id, this.label, this.defaultModel);

  static PlaygroundChannel? fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// 参考图在一轮调用里扮演的角色。
///
/// 与 [PlaygroundChannel.video] 的三种生成模式对应：首帧与尾帧走 keyframe
/// 模式（两者至少一个），普通参考图走 reference 模式（可与音频参考混用，
/// 但本版本不暴露音频输入）。
enum PlaygroundMediaRole {
  /// 首帧。
  firstFrame('first_frame', '首帧'),

  /// 尾帧。
  lastFrame('last_frame', '尾帧'),

  /// 普通参考图（reference 模式，提示词里以 `<Picture N>` 指代）。
  reference('reference', '参考图');

  final String id;
  final String label;

  const PlaygroundMediaRole(this.id, this.label);

  static PlaygroundMediaRole? fromId(String? id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// 一轮调用的终态。
enum PlaygroundTurnStatus {
  /// 已完成并拿到产物。
  completed('completed', '已完成'),

  /// 失败。错误信息在 [PlaygroundTurn.error]。
  failed('failed', '失败'),

  /// 视频任务创建成功但本地等待预算耗尽，云端仍在处理。
  ///
  /// 与工坊的 `cloudProcessing` 同义——任务创建即计费，此时判失败会让用户
  /// 以为没花钱也没产出。
  cloudProcessing('cloud_processing', '云端处理中');

  final String id;
  final String label;

  const PlaygroundTurnStatus(this.id, this.label);

  static PlaygroundTurnStatus fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return PlaygroundTurnStatus.failed;
  }
}

/// 一轮调用引用的媒体（参考图副本）。
///
/// **只存副本路径，不存原路径**：用户会把参考图删掉或移走，快照必须还能
/// 回看"我当时喂了什么"。与资产库"复制而非移动"是同一条理由。
class PlaygroundMedia {
  /// 副本文件名（相对该轮次的 `media/` 目录）。
  final String fileName;

  /// 原始文件名——只作展示，不用于读取。
  final String originalName;

  final PlaygroundMediaRole role;

  /// 图片宽高。读不到时（副本损坏、非图片）为 null，**不编造**。
  final int? width;
  final int? height;

  /// 副本字节数。脱敏请求体视图用它展示"这张图占了多大"。
  final int bytes;

  const PlaygroundMedia({
    required this.fileName,
    required this.originalName,
    required this.role,
    this.width,
    this.height,
    required this.bytes,
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'originalName': originalName,
        'role': role.id,
        'width': width,
        'height': height,
        'bytes': bytes,
      };

  static PlaygroundMedia? fromJson(Map<String, dynamic> json) {
    try {
      final fileName = json['fileName'] as String?;
      final role = PlaygroundMediaRole.fromId(json['role'] as String?);
      if (fileName == null || fileName.isEmpty || role == null) return null;
      return PlaygroundMedia(
        fileName: fileName,
        originalName: json['originalName'] as String? ?? fileName,
        role: role,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[PlaygroundMedia] 解析失败，跳过: $e');
      return null;
    }
  }
}

/// 一轮调用的请求快照。
///
/// 这是试炼场的核心数据结构——**它记的是"喂了什么"，不只是"出了什么"**。
/// 现有调用台账（`VideoTaskLedger`）记 `model / prompt / outputPath`，没有
/// 参考图、尺寸档位、画幅比例、生成模式与种子，所以事后依然无法归因。
class PlaygroundTurn {
  /// 本地稳定 id（`turn_<microseconds>`）。
  final String id;

  final PlaygroundChannel channel;

  /// 供应商标识（配置里的 provider id）。
  final String providerId;

  /// 供应商显示名。快照要自包含——供应商后来被删名也要能显示。
  final String providerName;

  final String model;

  /// 提交的提示词**逐字原文**。不做任何组装或替换。
  final String prompt;

  /// 吸附后的实际参数。键为参数名，值为提交值（如 `{'seconds': '5',
  /// 'size': '720P', 'aspect_ratio': '9:16'}`）。
  ///
  /// 存吸附后的而不是请求时的：用户想知道"我以为传了 2K，实际发了什么"。
  final Map<String, String> params;

  /// 参考图副本。文本通道为空。
  final List<PlaygroundMedia> media;

  /// 产物文件名（相对该轮次的 `output/` 目录）。失败时为 null。
  final String? outputFileName;

  /// 产物字节数。
  final int? outputBytes;

  /// 云端任务标识。视频任务有；同步的图像/文本调用为空串（不伪造）。
  final String remoteTaskId;

  final PlaygroundTurnStatus status;

  /// 人类可读的失败原因。
  final String? error;

  /// 调用耗时（毫秒）。视频任务是"创建 + 轮询 + 下载"的总时长。
  final int durationMs;

  final DateTime createdAt;

  const PlaygroundTurn({
    required this.id,
    required this.channel,
    required this.providerId,
    required this.providerName,
    required this.model,
    required this.prompt,
    this.params = const {},
    this.media = const [],
    this.outputFileName,
    this.outputBytes,
    this.remoteTaskId = '',
    required this.status,
    this.error,
    required this.durationMs,
    required this.createdAt,
  });

  /// 脱敏请求体视图。
  ///
  /// **这是回答"我到底发了什么"的那一行**：图片字段不展开 base64，而是换成
  /// `<first_frame: 720×1280 JPEG 87KB>` 这种一行摘要。展开 87KB 的编码数据
  /// 对排查没有任何帮助，只会把真正的字段挤出屏幕。
  String renderRedactedRequest() {
    final buffer = StringBuffer();
    buffer.writeln('POST /v1/${channel == PlaygroundChannel.video ? 'videos' : 'images/generations'}');
    buffer.writeln('model: $model');
    buffer.writeln('prompt: $prompt');
    for (final entry in params.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    for (final m in media) {
      final dims = (m.width != null && m.height != null)
          ? '${m.width}×${m.height}'
          : '尺寸未知';
      final fieldName = switch (m.role) {
        PlaygroundMediaRole.firstFrame => 'first_frame',
        PlaygroundMediaRole.lastFrame => 'last_frame',
        PlaygroundMediaRole.reference => 'images[]',
      };
      buffer.writeln('$fieldName: <${m.originalName} · $dims · ${_formatBytes(m.bytes)}>');
    }
    return buffer.toString().trimRight();
  }

  /// 真实脱敏后的完整 HTTP JSON 文本（便于直接复制给外部或复现排查）。
  String renderRedactedJson() {
    final body = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      ...params,
    };
    for (final m in media) {
      final dims = (m.width != null && m.height != null)
          ? '${m.width}×${m.height}'
          : '尺寸未知';
      final summary = '<${m.originalName} · $dims · ${_formatBytes(m.bytes)} · base64>';
      switch (m.role) {
        case PlaygroundMediaRole.firstFrame:
          body['first_frame'] = summary;
          break;
        case PlaygroundMediaRole.lastFrame:
          body['last_frame'] = summary;
          break;
        case PlaygroundMediaRole.reference:
          final list = (body['images'] as List<dynamic>? ?? <dynamic>[]);
          list.add(summary);
          body['images'] = list;
          break;
      }
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(body);
    } catch (_) {
      return '{}';
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0B';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel': channel.id,
        'providerId': providerId,
        'providerName': providerName,
        'model': model,
        'prompt': prompt,
        'params': params,
        'media': media.map((m) => m.toJson()).toList(),
        'outputFileName': outputFileName,
        'outputBytes': outputBytes,
        'remoteTaskId': remoteTaskId,
        'status': status.id,
        'error': error,
        'durationMs': durationMs,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static PlaygroundTurn? fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'] as String?;
      final channel = PlaygroundChannel.fromId(json['channel'] as String?);
      if (id == null || id.isEmpty || channel == null) return null;
      final createdAtMs = json['createdAt'] as int?;
      return PlaygroundTurn(
        id: id,
        channel: channel,
        providerId: json['providerId'] as String? ?? '',
        providerName: json['providerName'] as String? ?? '',
        model: json['model'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        params: (json['params'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const {},
        media: ((json['media'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => PlaygroundMedia.fromJson(m.map((k, v) => MapEntry(k.toString(), v))))
            .whereType<PlaygroundMedia>()
            .toList(),
        outputFileName: json['outputFileName'] as String?,
        outputBytes: (json['outputBytes'] as num?)?.toInt(),
        remoteTaskId: json['remoteTaskId'] as String? ?? '',
        status: PlaygroundTurnStatus.fromId(json['status'] as String?),
        error: json['error'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs ?? 0),
      );
    } catch (e) {
      debugPrint('[PlaygroundTurn] 解析失败，跳过: $e');
      return null;
    }
  }
}

/// 待提交的一轮调用参数（UI 侧的输入形状）。
class PlaygroundDraft {
  final PlaygroundChannel channel;
  String providerId;
  String model;
  String prompt;

  /// 待添加的媒体：原文件路径 + 角色。
  final List<({File file, PlaygroundMediaRole role})> media;

  /// 视频参数。图像通道不用。
  int durationSec;
  String sizeTier;
  String ratio;
  String mode; // auto | text | keyframe | reference
  String seed;

  /// 真实脱敏后的完整 HTTP 请求体快照（从台账导入或现场构造）。
  Map<String, dynamic>? rawPayload;

  PlaygroundDraft({
    required this.channel,
    this.providerId = '',
    String? model,
    this.prompt = '',
    List<({File file, PlaygroundMediaRole role})>? media,
    this.durationSec = 5,
    this.sizeTier = '',
    this.ratio = '',
    this.mode = 'auto',
    this.seed = '',
    this.rawPayload,
  })  : model = model ?? channel.defaultModel,
        media = media ?? <({File file, PlaygroundMediaRole role})>[];

  PlaygroundDraft copyWith({
    String? providerId,
    String? model,
    String? prompt,
    int? durationSec,
    String? sizeTier,
    String? ratio,
    String? mode,
    String? seed,
    Map<String, dynamic>? rawPayload,
  }) {
    return PlaygroundDraft(
      channel: channel,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      prompt: prompt ?? this.prompt,
      media: media,
      durationSec: durationSec ?? this.durationSec,
      sizeTier: sizeTier ?? this.sizeTier,
      ratio: ratio ?? this.ratio,
      mode: mode ?? this.mode,
      seed: seed ?? this.seed,
      rawPayload: rawPayload ?? this.rawPayload,
    );
  }

  Map<String, dynamic> toJson() => {
    'channel': channel.id,
    'providerId': providerId,
    'model': model,
    'prompt': prompt,
    'durationSec': durationSec,
    'sizeTier': sizeTier,
    'ratio': ratio,
    'mode': mode,
    'seed': seed,
    if (rawPayload != null) 'rawPayload': rawPayload,
    'media': media.map((m) => {
      'path': m.file.path,
      'role': m.role.id,
    }).toList(),
  };

  static PlaygroundDraft? fromJson(Map<String, dynamic> json) {
    try {
      final channel = PlaygroundChannel.fromId(json['channel'] as String?) ??
          PlaygroundChannel.video;
      final rawMedia = json['media'];
      final mediaList = <({File file, PlaygroundMediaRole role})>[];
      if (rawMedia is List) {
        for (final item in rawMedia) {
          if (item is Map) {
            final path = item['path'] as String?;
            final roleId = item['role'] as String?;
            if (path != null && path.isNotEmpty) {
              final file = File(path);
              final role = PlaygroundMediaRole.fromId(roleId) ??
                  PlaygroundMediaRole.reference;
              mediaList.add((file: file, role: role));
            }
          }
        }
      }
      return PlaygroundDraft(
        channel: channel,
        providerId: json['providerId'] as String? ?? '',
        model: json['model'] as String?,
        prompt: json['prompt'] as String? ?? '',
        media: mediaList,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 5,
        sizeTier: json['sizeTier'] as String? ?? '',
        ratio: json['ratio'] as String? ?? '',
        mode: json['mode'] as String? ?? 'auto',
        seed: json['seed']?.toString() ?? '',
        rawPayload: json['rawPayload'] is Map
            ? (json['rawPayload'] as Map).map((k, v) => MapEntry(k.toString(), v))
            : null,
      );
    } catch (e) {
      debugPrint('[PlaygroundDraft] fromJson failed: $e');
      return null;
    }
  }

  static PlaygroundDraft fromLedgerEntry(VideoTaskLedgerEntry entry) {
    final snapshot = entry.requestSnapshot ?? const {};
    final channelId = snapshot['channel'] as String?;
    final channel = PlaygroundChannel.fromId(channelId) ??
        (entry.adapterId == 'image-adapter'
            ? PlaygroundChannel.image
            : PlaygroundChannel.video);

    final mediaList = <({File file, PlaygroundMediaRole role})>[];

    // 1. 首帧：优先读取显式记录的 firstFramePath
    final firstFramePath = snapshot['firstFramePath'] as String? ?? entry.firstFramePath;
    if (firstFramePath != null && firstFramePath.isNotEmpty) {
      final f = File(firstFramePath);
      if (f.existsSync()) {
        mediaList.add((file: f, role: PlaygroundMediaRole.firstFrame));
      }
    }

    // 2. 尾帧：优先读取显式记录的 lastFramePath
    final lastFramePath = snapshot['lastFramePath'] as String? ?? entry.lastFramePath;
    if (lastFramePath != null && lastFramePath.isNotEmpty) {
      final f = File(lastFramePath);
      if (f.existsSync()) {
        mediaList.add((file: f, role: PlaygroundMediaRole.lastFrame));
      }
    }

    // 3. 参考素材：读取 referencePaths，并剔除已被识别为首尾帧的文件
    final refPaths = snapshot['referencePaths'];
    if (refPaths is List) {
      for (final p in refPaths) {
        if (p is String && p.isNotEmpty) {
          if (p == firstFramePath || p == lastFramePath) continue;
          final f = File(p);
          if (f.existsSync()) {
            mediaList.add((file: f, role: PlaygroundMediaRole.reference));
          }
        }
      }
    }

    // 4. 老版本快照容错：若未独立记录首尾帧路径，但模式为 keyframe，
    // 将原 referencePaths 中的素材分别还原为首帧和尾帧，避免误判为参考图触发模式互斥拦截
    final modeStr = (snapshot['mode'] as String? ?? 'auto').toLowerCase();
    if (firstFramePath == null && lastFramePath == null && modeStr == 'keyframe' && mediaList.isNotEmpty) {
      final oldList = List.of(mediaList);
      mediaList.clear();
      final first = oldList.removeAt(0);
      mediaList.add((file: first.file, role: PlaygroundMediaRole.firstFrame));
      if (oldList.isNotEmpty) {
        final last = oldList.removeAt(0);
        mediaList.add((file: last.file, role: PlaygroundMediaRole.lastFrame));
      }
      for (final rem in oldList) {
        mediaList.add(rem);
      }
    }

    // 5. 键名双向对齐读取
    final duration = (snapshot['durationSec'] as num?)?.toInt() ??
        (snapshot['durationSeconds'] as num?)?.toInt() ??
        5;
    final sizeTier = (snapshot['sizeTier'] ?? snapshot['resolution'] ?? '').toString();
    final ratio = (snapshot['ratio'] ?? snapshot['aspectRatio'] ?? '').toString();
    final mode = snapshot['mode'] as String? ?? 'auto';
    final seed = snapshot['seed']?.toString() ?? '';

    return PlaygroundDraft(
      channel: channel,
      providerId: snapshot['providerId'] as String? ?? entry.providerId,
      model: snapshot['model'] as String? ?? entry.model,
      prompt: snapshot['prompt'] as String? ?? entry.prompt ?? '',
      media: mediaList,
      durationSec: duration,
      sizeTier: sizeTier,
      ratio: ratio,
      mode: mode,
      seed: seed,
      rawPayload: entry.rawPayload,
    );
  }

  /// 格式化后的真实脱敏 HTTP JSON。
  /// 若草稿未携带外部 rawPayload，则按当前草稿字段现场构造一份标准 Agnes 请求体脱敏 JSON。
  String get formattedRawPayloadJson {
    if (rawPayload != null) {
      try {
        return const JsonEncoder.withIndent('  ').convert(rawPayload);
      } catch (_) {}
    }
    final mockBody = <String, dynamic>{
      'model': model,
      'prompt': prompt.trim(),
      if (channel == PlaygroundChannel.video) ...{
        'mode': mode,
        'seconds': durationSec.toString(),
        if (sizeTier.trim().isNotEmpty) 'size': sizeTier.trim(),
        if (ratio.trim().isNotEmpty) 'aspect_ratio': ratio.trim(),
        if (seed.trim().isNotEmpty) 'seed': int.tryParse(seed) ?? seed,
      },
    };
    for (final m in media) {
      final name = m.file.uri.pathSegments.isNotEmpty ? m.file.uri.pathSegments.last : 'image.png';
      switch (m.role) {
        case PlaygroundMediaRole.firstFrame:
          mockBody['first_frame'] = '<$name · base64>';
          break;
        case PlaygroundMediaRole.lastFrame:
          mockBody['last_frame'] = '<$name · base64>';
          break;
        case PlaygroundMediaRole.reference:
          final list = (mockBody['images'] as List<dynamic>? ?? <dynamic>[]);
          list.add('<$name · base64>');
          mockBody['images'] = list;
          break;
      }
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(mockBody);
    } catch (_) {
      return '{}';
    }
  }

  /// 脱敏请求体预览（提交前就能看）。
  ///
  /// 与 [PlaygroundTurn.renderRedactedRequest] 同一套措辞，让用户在提交前
  /// 看到的和提交后留档的一致。
  String renderRedactedRequest() {
    final buffer = StringBuffer();
    buffer.writeln('model: $model');
    buffer.writeln('prompt: ${prompt.trim().isEmpty ? '(空)' : prompt.trim()}');
    if (channel == PlaygroundChannel.video) {
      buffer.writeln('mode: $mode');
      buffer.writeln('seconds: $durationSec');
      if (sizeTier.trim().isNotEmpty) buffer.writeln('size: $sizeTier');
      if (ratio.trim().isNotEmpty) buffer.writeln('aspect_ratio: $ratio');
      if (seed.trim().isNotEmpty) buffer.writeln('seed: $seed');
    }
    for (final m in media) {
      final fieldName = switch (m.role) {
        PlaygroundMediaRole.firstFrame => 'first_frame',
        PlaygroundMediaRole.lastFrame => 'last_frame',
        PlaygroundMediaRole.reference => 'images[]',
      };
      buffer.writeln(
        '$fieldName: <${m.file.uri.pathSegments.last} · 待上传>',
      );
    }
    return buffer.toString().trimRight();
  }
}

/// JSON 编解码的小工具，供 store 使用。
Object? tryDecodeJson(String source) {
  try {
    return jsonDecode(source);
  } catch (_) {
    return null;
  }
}
