import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../services/app_paths.dart';
import '../../ai_video_studio/services/asset_library.dart';
import '../models/playground_models.dart';

/// 试炼场的存储层：轮次索引 + 每轮的自包含目录。
///
/// **为什么与 `VideoTaskLedger` 分开**：台账是账（记生命周期事件、按 7 天
/// 清理、与分镜看板的「云端任务」面板共用），快照是分析材料（长期保留、带
/// 参考图副本、要能回看"我当时喂了什么"）。混在一份里会让两边的清理策略与
/// 字段需求互相绑架。
///
/// 视频调用**仍然照常记台账**——那是账，双写而非二选一。
///
/// 写盘用「临时文件 + rename」原子替换，与 `AssetLibrary`、
/// `VideoTaskLedger` 同一套做法：索引损坏比索引丢失更糟。
class PlaygroundStore {
  PlaygroundStore._();
  static final PlaygroundStore instance = PlaygroundStore._();

  static const _uuid = Uuid();

  final List<PlaygroundTurn> _turns = <PlaygroundTurn>[];
  bool _loaded = false;

  final _draftController = StreamController<PlaygroundDraft?>.broadcast();
  Stream<PlaygroundDraft?> get draftStream => _draftController.stream;
  PlaygroundDraft? _currentDraft;

  PlaygroundDraft? get currentDraft => _currentDraft;

  /// 串行化所有写操作。并发写会让 rename 覆盖彼此的更新。
  Future<void> _writeChain = Future<void>.value();

  /// 保存调试草稿（内存 + 磁盘原子落盘），并广播给监听者。
  Future<void> saveDraft(PlaygroundDraft draft) async {
    _currentDraft = draft;
    _draftController.add(draft);
    try {
      final file = AppPaths.agnesPlaygroundDraftFile;
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(draft.toJson()), flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('[PlaygroundStore] saveDraft failed: $e');
    }
  }

  /// 消费并清除待载入草稿。
  Future<PlaygroundDraft?> consumeDraft() async {
    if (_currentDraft != null) {
      final draft = _currentDraft;
      _currentDraft = null;
      unawaited(_clearDraftFile());
      return draft;
    }
    final file = AppPaths.agnesPlaygroundDraftFile;
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final draft = PlaygroundDraft.fromJson(decoded);
        unawaited(_clearDraftFile());
        return draft;
      } else if (decoded is Map) {
        final draft = PlaygroundDraft.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
        unawaited(_clearDraftFile());
        return draft;
      }
    } catch (e) {
      debugPrint('[PlaygroundStore] consumeDraft failed: $e');
    }
    return null;
  }

  Future<void> _clearDraftFile() async {
    try {
      final file = AppPaths.agnesPlaygroundDraftFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 当前全部轮次（新的在前）。
  List<PlaygroundTurn> get turns {
    final list = _turns.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  /// 从磁盘加载。重复调用只读一次。
  ///
  /// 文件不存在 → 空库（正常，首次运行）。
  /// 文件损坏 → 空库 + 日志，**MUST NOT 抛异常**——与资产库同一契约。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final file = AppPaths.agnesPlaygroundIndexFile;
    if (!await file.exists()) {
      _loaded = true;
      return;
    }
    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is List) {
        _turns.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final t = PlaygroundTurn.fromJson(item);
            if (t != null) _turns.add(t);
          } else if (item is Map) {
            final t = PlaygroundTurn.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (t != null) _turns.add(t);
          }
        }
      }
    } catch (e) {
      debugPrint('[PlaygroundStore] 索引文件损坏，以空库启动: $e');
      _turns.clear();
    }
    _loaded = true;
  }

  /// 测试用：重置加载状态与内存数据。
  void resetForTesting() {
    _turns.clear();
    _loaded = false;
  }

  Future<void> _persist() {
    _writeChain = _writeChain.then((_) async {
      try {
        final file = AppPaths.agnesPlaygroundIndexFile;
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(
          jsonEncode(_turns.map((t) => t.toJson()).toList()),
          flush: true,
        );
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path);
      } catch (e) {
        debugPrint('[PlaygroundStore] 写入失败: $e');
      }
    });
    return _writeChain;
  }

  /// 生成本轮 id。时间戳前缀让目录按创建顺序可排，对排查有用。
  String _freshTurnId() =>
      'turn_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  /// 轮次目录。
  Directory turnDir(String turnId) => AppPaths.agnesPlaygroundTurnDir(turnId);

  /// 参考图副本所在目录。
  Directory mediaDir(String turnId) => Directory(p.join(turnDir(turnId).path, 'media'));

  /// 产物所在目录。
  Directory outputDir(String turnId) =>
      Directory(p.join(turnDir(turnId).path, 'output'));

  /// 把一份草稿落成自包含快照。
  ///
  /// 顺序刻意如此：先建目录、复制媒体、执行调用、再写产物与索引。任何一步
  /// 失败都要留下一个带错误信息的轮次——失败的那次同样回答了"我发了什么"。
  Future<PlaygroundTurn> record({
    required PlaygroundChannel channel,
    required String providerId,
    required String providerName,
    required String model,
    required String prompt,
    required Map<String, String> params,
    required List<({File file, PlaygroundMediaRole role})> media,
    required Future<PlaygroundCallOutcome> Function(
      Directory outputTarget,
    ) invoke,
  }) async {
    await ensureLoaded();
    final id = _freshTurnId();
    final stopwatch = Stopwatch()..start();

    // 1. 建目录 + 复制媒体副本
    final mDir = mediaDir(id);
    final oDir = outputDir(id);
    await mDir.create(recursive: true);
    await oDir.create(recursive: true);

    final copiedMedia = <PlaygroundMedia>[];
    for (final m in media) {
      try {
        if (!await m.file.exists()) continue;
        // 副本名带序号：同一文件被同时设为首帧与参考图时不会互相覆盖。
        final target = File(
          p.join(mDir.path, '${copiedMedia.length}_${p.basename(m.file.path)}'),
        );
        await m.file.copy(target.path);
        copiedMedia.add(
          await _describeMedia(target, m.file, m.role),
        );
      } catch (e) {
        debugPrint('[PlaygroundStore] 复制媒体失败: ${m.file.path} ($e)');
      }
    }

    // 2. 执行调用
    PlaygroundCallOutcome outcome;
    try {
      outcome = await invoke(oDir);
    } catch (e) {
      outcome = PlaygroundCallOutcome.failure(e.toString());
    }
    stopwatch.stop();

    // 3. 汇总成轮次
    final turn = PlaygroundTurn(
      id: id,
      channel: channel,
      providerId: providerId,
      providerName: providerName,
      model: model,
      prompt: prompt,
      params: params,
      media: copiedMedia,
      outputFileName: outcome.outputFileName,
      outputBytes: outcome.outputBytes,
      remoteTaskId: outcome.remoteTaskId,
      status: outcome.status,
      error: outcome.error,
      durationMs: stopwatch.elapsedMilliseconds,
      createdAt: DateTime.now(),
    );

    _turns.add(turn);
    await _persist();
    return turn;
  }

  /// 读出媒体副本的尺寸与字节数。
  ///
  /// 尺寸读不到就留 null——**不编造**。缩略图渲染侧对 null 显示"尺寸未知"，
  /// 比显示一个猜的值诚实。
  Future<PlaygroundMedia> _describeMedia(
    File copy,
    File original,
    PlaygroundMediaRole role,
  ) async {
    int? width;
    int? height;
    try {
      final bytes = await copy.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        width = decoded.width;
        height = decoded.height;
      }
    } catch (_) {}
    return PlaygroundMedia(
      fileName: p.basename(copy.path),
      originalName: p.basename(original.path),
      role: role,
      width: width,
      height: height,
      bytes: await copy.length(),
    );
  }

  /// 媒体副本的完整路径。
  File mediaFile(PlaygroundTurn turn, PlaygroundMedia media) =>
      File(p.join(mediaDir(turn.id).path, media.fileName));

  /// 产物的完整路径。产物不存在时返回 null。
  File? outputFile(PlaygroundTurn turn) {
    final name = turn.outputFileName;
    if (name == null || name.isEmpty) return null;
    final file = File(p.join(outputDir(turn.id).path, name));
    return file.existsSync() ? file : null;
  }

  /// 更新一轮的可变字段（状态、产物、错误）。
  ///
  /// 用于「继续等待」成功后把云端处理中的轮次改成已完成——那一轮已经落过盘
  /// 了，只是结论要改。不可变字段（提示词、媒体、参数）刻意不可更新：它们
  /// 记录的是"当时发了什么"，改了就失去意义。
  Future<void> updateTurn(
    String turnId, {
    PlaygroundTurnStatus? status,
    String? outputFileName,
    int? outputBytes,
    String? remoteTaskId,
    String? error,
  }) async {
    await ensureLoaded();
    final idx = _turns.indexWhere((t) => t.id == turnId);
    if (idx < 0) return;
    final old = _turns[idx];
    _turns[idx] = PlaygroundTurn(
      id: old.id,
      channel: old.channel,
      providerId: old.providerId,
      providerName: old.providerName,
      model: old.model,
      prompt: old.prompt,
      params: old.params,
      media: old.media,
      outputFileName: outputFileName ?? old.outputFileName,
      outputBytes: outputBytes ?? old.outputBytes,
      remoteTaskId: remoteTaskId ?? old.remoteTaskId,
      status: status ?? old.status,
      error: error,
      durationMs: old.durationMs,
      createdAt: old.createdAt,
    );
    await _persist();
  }

  /// 删除一轮（含其目录）。
  ///
  /// **不影响台账与资产库**：那边有自己的生命周期。若这一轮的产物已被收进
  /// 资产库，删轮次不会删资产——资产库持有的是副本。
  Future<void> remove(String turnId) async {
    await ensureLoaded();
    _turns.removeWhere((t) => t.id == turnId);
    await _persist();
    try {
      final dir = turnDir(turnId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[PlaygroundStore] 删除轮次目录失败: $e');
    }
  }

  /// 把一轮的产物收进资产库。**复制，不移动**——与工坊一致。
  Future<StudioAsset?> collectToAssetLibrary(PlaygroundTurn turn) async {
    final file = outputFile(turn);
    if (file == null) return null;
    return AssetLibrary.instance.addAsset(
      file,
      kind: turn.channel == PlaygroundChannel.video
          ? AssetKind.clip
          : AssetKind.image,
      source: AssetSource.remote,
      providerId: turn.providerId.isNotEmpty ? turn.providerId : turn.providerName,
      model: turn.model,
      prompt: turn.prompt,
      // 指向本轮快照 id，而不是台账 localId——从资产反查时要落到"我当时
      // 喂了什么"，那只有快照答得上来。
      sourceCallId: turn.id,
      originPath: file.path,
      durationSec: turn.channel == PlaygroundChannel.video
          ? int.tryParse(turn.params['seconds'] ?? '')?.toDouble()
          : null,
      tags: const ['试炼场'],
    );
  }

  /// 清理超过 [olderThan] 的已终结轮次。
  ///
  /// 返回清理数量。仍在云端处理的轮次**不清理**——它还有取回的价值。
  Future<int> pruneOld(Duration olderThan) async {
    await ensureLoaded();
    final cutoff = DateTime.now().subtract(olderThan);
    final doomed = _turns
        .where((t) =>
            t.status != PlaygroundTurnStatus.cloudProcessing &&
            t.createdAt.isBefore(cutoff))
        .toList();
    for (final t in doomed) {
      await remove(t.id);
    }
    return doomed.length;
  }

  /// 一个不碰撞的短 id（供台账 localId 之类场合）。
  static String freshShortId() =>
      _uuid.v4().replaceAll('-', '').substring(0, 8);
}

/// 一次调用的结果（成功或失败都算结果）。
class PlaygroundCallOutcome {
  final PlaygroundTurnStatus status;
  final String? outputFileName;
  final int? outputBytes;
  final String remoteTaskId;
  final String? error;

  const PlaygroundCallOutcome({
    required this.status,
    this.outputFileName,
    this.outputBytes,
    this.remoteTaskId = '',
    this.error,
  });

  /// 构造一个失败结果。**不用 factory const**：调用方传进来的 `error` 来自
  /// `e.toString()`，那是运行期值；写成 `const PlaygroundCallOutcome.failure(...)`
  /// 会在类没有 const 构造时直接编译失败。
  static PlaygroundCallOutcome failure(String error) =>
      PlaygroundCallOutcome(
        status: PlaygroundTurnStatus.failed,
        error: error,
      );
}
