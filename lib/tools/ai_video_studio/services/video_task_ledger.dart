import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import '../../../../services/app_paths.dart';

/// 云端视频异步任务的状态。
///
/// 与 UI 队列的 [StudioTaskStatus] 不是一回事：那个是**内存调度快照**，
/// 这个是**跨重启的持久事实**。区分它们是本文件存在的理由——云端任务
/// 在进程消失后依然在跑、在计费，内存队列表达不了这件事。
enum VideoTaskLedgerStatus {
  /// 已创建，正在本地轮询。
  polling('polling', '等待中'),

  /// 本地轮询预算耗尽，但云端状态仍是排队中或处理中。
  ///
  /// **刻意不是 failed**：云端任务一旦创建即计费，把它记成失败会让用户
  /// 以为「没花钱也没产出」，而事实是钱花了、视频还在云端。这个状态告诉
  /// 用户「东西还在，去取」。
  cloudProcessing('cloudProcessing', '云端仍在处理'),

  /// 已完成并落盘。
  completed('completed', '已完成'),

  /// 云端明确返回失败，或本地下载/写入失败。
  failed('failed', '失败'),

  /// 用户主动放弃本地等待。**不影响云端**——Agnes 没有取消端点。
  abandoned('abandoned', '已放弃');

  final String id;
  final String label;

  const VideoTaskLedgerStatus(this.id, this.label);

  static VideoTaskLedgerStatus? fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 是否还需要本地继续轮询。
  bool get isActive => this == polling || this == cloudProcessing;
}

/// 台账里的一个云端视频任务。
///
/// 供应商中立：[remoteTaskId] 存各家用于查询的那个标识——Agnes 的创建响应
/// 同时返回 `id` / `task_id` / `video_id`，**查询要用 `video_id`**，所以
/// Agnes 路径下这个字段存的是 video_id。供应商特有的额外字段进 [extra]，
/// 不加供应商专属列——否则第二个供应商接入时又要改表结构。
class VideoTaskLedgerEntry {
  /// 本地生成的稳定 id（不等于云端 id）。
  final String localId;

  /// 供应商标识（配置里的 provider id；无配置时为适配器 id）。
  final String providerId;

  /// 适配器标识，如 `agnes-video-2.5-flash`。
  final String adapterId;

  /// 模型 id。
  final String model;

  /// 云端任务标识。Agnes 存 `video_id`。
  final String remoteTaskId;

  final VideoTaskLedgerStatus status;

  /// 云端最后一次回报的状态原文（queued / in_progress / completed / failed）。
  /// 与 [status] 分开存：本地语义与云端措辞不是一对一，排查时两边都要看。
  final String? lastRemoteStatus;

  /// 云端进度 0–100。未知时为 null——**不编造**。
  final int? lastProgress;

  /// 关联上下文。片段级与分镜级共用一组可空字段，命中哪个填哪个。
  final String seriesId;
  final String episodeId;
  final String segmentId;
  final int? shotNumber;

  /// 人类可读的任务描述（如「片段 3 视频」），用于 UI 列表。
  final String label;

  /// 生成提示词摘要。图片调用也记这个——它没有任务 ID，提示词是用户
  /// 回望"我当时让它画什么"的唯一线索。
  final String? prompt;

  /// 目标产物路径（.mp4）。恢复后写回这里。
  final String targetPath;

  final DateTime createdAt;
  DateTime updatedAt;

  /// 云端阶段推断：是否已见过 in_progress。
  /// 用于排队预算 → 生成预算的切换判定，重启后仍需有效，故持久化。
  bool sawInProgress;

  /// 已消耗的本地轮询时长（毫秒）。跨重启累加，用于两段预算判定。
  int elapsedPollMs;

  /// 任务发起时的全量请求快照（模型、提示词、时长、比例、参考图等），
  /// 用于跨进程留痕与一键转到 Agnes 试炼场调试。
  final Map<String, dynamic>? requestSnapshot;

  String? error;

  VideoTaskLedgerEntry({
    required this.localId,
    required this.providerId,
    required this.adapterId,
    required this.model,
    required this.remoteTaskId,
    required this.status,
    required this.seriesId,
    required this.episodeId,
    required this.segmentId,
    required this.shotNumber,
    required this.label,
    required this.targetPath,
    required this.createdAt,
    required this.updatedAt,
    this.prompt,
    this.lastRemoteStatus,
    this.lastProgress,
    this.sawInProgress = false,
    this.elapsedPollMs = 0,
    this.requestSnapshot,
    this.error,
  });

  VideoTaskLedgerEntry copyWith({
    VideoTaskLedgerStatus? status,
    String? lastRemoteStatus,
    int? lastProgress,
    DateTime? updatedAt,
    bool? sawInProgress,
    int? elapsedPollMs,
    Map<String, dynamic>? requestSnapshot,
    String? error,
  }) {
    return VideoTaskLedgerEntry(
      localId: localId,
      providerId: providerId,
      adapterId: adapterId,
      model: model,
      remoteTaskId: remoteTaskId,
      status: status ?? this.status,
      seriesId: seriesId,
      episodeId: episodeId,
      segmentId: segmentId,
      shotNumber: shotNumber,
      label: label,
      prompt: prompt,
      targetPath: targetPath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRemoteStatus: lastRemoteStatus ?? this.lastRemoteStatus,
      lastProgress: lastProgress ?? this.lastProgress,
      sawInProgress: sawInProgress ?? this.sawInProgress,
      elapsedPollMs: elapsedPollMs ?? this.elapsedPollMs,
      requestSnapshot: requestSnapshot ?? this.requestSnapshot,
      error: error ?? this.error,
    );
  }

  /// 真实脱敏后的 HTTP 请求体（由适配器发往云端时记录）。
  Map<String, dynamic>? get rawPayload {
    final raw = requestSnapshot?['rawPayload'];
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// 格式化后的脱敏 HTTP JSON 文本（便于直接展示或复制）。
  String? get formattedRawPayloadJson {
    final payload = rawPayload;
    if (payload != null) {
      try {
        return const JsonEncoder.withIndent('  ').convert(payload);
      } catch (_) {}
    }
    return null;
  }

  String? get firstFramePath => requestSnapshot?['firstFramePath'] as String?;
  String? get lastFramePath => requestSnapshot?['lastFramePath'] as String?;
  List<String> get referencePaths {
    final refs = requestSnapshot?['referencePaths'];
    if (refs is List) {
      return refs.whereType<String>().toList();
    }
    return const [];
  }

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'providerId': providerId,
    'adapterId': adapterId,
    'model': model,
    'remoteTaskId': remoteTaskId,
    'status': status.id,
    'lastRemoteStatus': lastRemoteStatus,
    'lastProgress': lastProgress,
    'seriesId': seriesId,
    'episodeId': episodeId,
    'segmentId': segmentId,
    'shotNumber': shotNumber,
    'label': label,
    'prompt': prompt,
    'targetPath': targetPath,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'sawInProgress': sawInProgress,
    'elapsedPollMs': elapsedPollMs,
    if (requestSnapshot != null) 'requestSnapshot': requestSnapshot,
    'error': error,
  };

  static VideoTaskLedgerEntry? fromJson(Map<String, dynamic> json) {
    try {
      // localId 才是必需字段——remoteTaskId 可以为空（同步图像调用没有
      // 任务 ID）。曾经这里判 remoteTaskId 非空，结果所有图片调用记录
      // 落盘后重新加载时全部被丢弃：写进去了，读不出来。
      final localId = json['localId'] as String?;
      if (localId == null || localId.isEmpty) return null;
      final remoteTaskId = json['remoteTaskId'] as String? ?? '';
      final createdAtMs = json['createdAt'] as int?;
      final updatedAtMs = json['updatedAt'] as int?;
      final created =
          DateTime.fromMillisecondsSinceEpoch(createdAtMs ?? 0, isUtc: true);
      return VideoTaskLedgerEntry(
        localId: localId,
        providerId: json['providerId'] as String? ?? '',
        adapterId: json['adapterId'] as String? ?? '',
        model: json['model'] as String? ?? '',
        remoteTaskId: remoteTaskId,
        status:
            VideoTaskLedgerStatus.fromId(json['status'] as String?) ??
            VideoTaskLedgerStatus.polling,
        lastRemoteStatus: json['lastRemoteStatus'] as String?,
        lastProgress: (json['lastProgress'] as num?)?.toInt(),
        seriesId: json['seriesId'] as String? ?? '',
        episodeId: json['episodeId'] as String? ?? '',
        segmentId: json['segmentId'] as String? ?? '',
        shotNumber: (json['shotNumber'] as num?)?.toInt(),
        label: json['label'] as String? ?? '',
        prompt: json['prompt'] as String?,
        targetPath: json['targetPath'] as String? ?? '',
        createdAt: created,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          updatedAtMs ?? createdAtMs ?? 0,
          isUtc: true,
        ),
        sawInProgress: json['sawInProgress'] as bool? ?? false,
        elapsedPollMs: json['elapsedPollMs'] as int? ?? 0,
        requestSnapshot: json['requestSnapshot'] is Map
            ? (json['requestSnapshot'] as Map).map((k, v) => MapEntry(k.toString(), v))
            : null,
        error: json['error'] as String?,
      );
    } catch (e) {
      debugPrint('[VideoTaskLedger] 解析条目失败，跳过: $e');
      return null;
    }
  }
}

/// 云端视频任务台账。
///
/// **为什么需要它**：视频生成是异步的，且任务创建即计费。进程被杀死、应用
/// 重启、轮询超时——这三种情况下云端任务都还在跑，而内存队列里什么都不剩。
/// 结果是用户付了钱却拿不到视频，也没有线索可查。台账把「云端有个任务在跑」
/// 这件事变成磁盘上的事实。
///
/// 与 `StudioTaskQueue` 的分工：那个管**本进程内**的调度、并发、取消与进度
/// 快照；这个只管**跨进程**的生命周期事件。进度快照不进台账——FFmpeg 每秒
/// 回调十几次，全量落盘会拖死 IO；台账只在状态跃迁时写，一个任务整个生命
/// 周期最多十几次写盘。
///
/// 写盘用「临时文件 + rename」原子替换，与 `NovelChapterStorage` 同一套做法：
/// 台账损坏比台账丢失更糟——丢失至少是空的，损坏会让启动路径抛异常。
class VideoTaskLedger {
  VideoTaskLedger._();
  static final VideoTaskLedger instance = VideoTaskLedger._();

  final List<VideoTaskLedgerEntry> _entries = <VideoTaskLedgerEntry>[];

  /// 串行化所有写操作。并发写会让 rename 覆盖彼此的更新。
  Future<void> _writeChain = Future<void>.value();

  bool _loaded = false;

  /// 当前全部条目（只读视图）。
  List<VideoTaskLedgerEntry> get entries =>
      List<VideoTaskLedgerEntry>.unmodifiable(_entries);

  /// 从磁盘加载。重复调用只读一次。
  ///
  /// 文件不存在 → 空台账（正常，首次运行）。
  /// 文件损坏 → 空台账 + 日志，**MUST NOT 抛异常**：启动路径不能被一个坏
  /// 数据文件阻断，那会让整个应用起不来。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final file = AppPaths.videoTaskLedgerFile;
    if (!await file.exists()) {
      _loaded = true;
      return;
    }
    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is List) {
        _entries.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final entry = VideoTaskLedgerEntry.fromJson(item);
            if (entry != null) _entries.add(entry);
          } else if (item is Map) {
            final entry = VideoTaskLedgerEntry.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (entry != null) _entries.add(entry);
          }
        }
      }
    } catch (e) {
      debugPrint('[VideoTaskLedger] 台账文件损坏，以空台账启动: $e');
      _entries.clear();
    }
    _loaded = true;
  }

  /// 落盘。串行执行，失败不抛出（调用方无法从「写台账失败」中有意义地恢复，
  /// 但也不能因此中断生成流程——日志已经足够定位）。
  Future<void> _persist() {
    _writeChain = _writeChain.then((_) async {
      try {
        final file = AppPaths.videoTaskLedgerFile;
        final dir = AppPaths.videoTaskLedgerDir;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(
          jsonEncode(_entries.map((e) => e.toJson()).toList()),
          flush: true,
        );
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path);
      } catch (e) {
        debugPrint('[VideoTaskLedger] 写入失败: $e');
      }
    });
    return _writeChain;
  }

  /// 登记一个刚创建的云端任务。
  ///
  /// **必须在开始轮询之前调用**——先落盘再轮询是 spec 的要求，也是唯一能
  /// 保证「轮询途中被杀也留得下线索」的顺序。
  /// 登记一次远端调用。
  ///
  /// [remoteTaskId] **可为空串**——同步接口（如多数图像生成）不返回任务
  /// 标识，此时记的是"这次调用发生过"，不是"有个任务在跑"。MUST NOT 为了
  /// 填满字段而伪造 ID。
  ///
  /// [localId] 由调用方给：视频任务用 `'${adapterId}_$remoteTaskId'`（稳定
  /// 可复现，恢复路径能算出同一个值），图片调用传 UUID。**去重键是 localId
  /// 而不是 remoteTaskId**——空 remoteTaskId 会让所有图片调用互判重复，
  /// 只留得下最后一条（这个坑踩过一次）。
  Future<VideoTaskLedgerEntry> record({
    required String providerId,
    required String adapterId,
    required String model,
    required String remoteTaskId,
    required String seriesId,
    required String episodeId,
    required String segmentId,
    required int? shotNumber,
    required String label,
    required String targetPath,
    String? localId,
    String? prompt,
    Map<String, dynamic>? requestSnapshot,
  }) async {
    await ensureLoaded();
    final now = DateTime.now().toUtc();
    final entry = VideoTaskLedgerEntry(
      localId: localId ?? '${adapterId}_$remoteTaskId',
      providerId: providerId,
      adapterId: adapterId,
      model: model,
      remoteTaskId: remoteTaskId,
      status: VideoTaskLedgerStatus.polling,
      seriesId: seriesId,
      episodeId: episodeId,
      segmentId: segmentId,
      shotNumber: shotNumber,
      label: label,
      targetPath: targetPath,
      prompt: prompt,
      requestSnapshot: requestSnapshot,
      createdAt: now,
      updatedAt: now,
    );
    // 同一 localId 不重复登记：恢复路径与正常路径可能同时到达，
    // 重复条目会让轮询起两份。
    _entries.removeWhere((e) => e.localId == entry.localId);
    _entries.add(entry);
    await _persist();
    return entry;
  }

  /// 更新条目状态。返回更新后的条目（找不到返回 null）。
  Future<VideoTaskLedgerEntry?> update(
    String localId, {
    VideoTaskLedgerStatus? status,
    String? lastRemoteStatus,
    int? lastProgress,
    bool? sawInProgress,
    int? elapsedPollMs,
    String? error,
  }) async {
    await ensureLoaded();
    final idx = _entries.indexWhere((e) => e.localId == localId);
    if (idx < 0) return null;
    final updated = _entries[idx].copyWith(
      status: status,
      lastRemoteStatus: lastRemoteStatus,
      lastProgress: lastProgress,
      updatedAt: DateTime.now().toUtc(),
      sawInProgress: sawInProgress,
      elapsedPollMs: elapsedPollMs,
      error: error,
    );
    _entries[idx] = updated;
    await _persist();
    return updated;
  }

  /// 按云端任务标识查找。
  /// 按云端任务标识查找。空标识直接返回 null。
  ///
  /// 不能拿空串去匹配：图片调用的 remoteTaskId 全是空串，一次空查询会把
  /// 第一条图片记录当成命中返回。
  Future<VideoTaskLedgerEntry?> findByRemoteId(String remoteTaskId) async {
    if (remoteTaskId.isEmpty) return null;
    await ensureLoaded();
    for (final e in _entries) {
      if (e.remoteTaskId == remoteTaskId) return e;
    }
    return null;
  }

  /// 按本地 id 查找。
  Future<VideoTaskLedgerEntry?> findByLocalId(String localId) async {
    await ensureLoaded();
    for (final e in _entries) {
      if (e.localId == localId) return e;
    }
    return null;
  }

  /// 全部仍需本地处理的任务（polling / cloudProcessing）。
  ///
  /// 恢复入口用它决定要挂起哪些轮询。已 polling 的条目由调用方判断是否已有
  /// 活跃轮询者——本类只提供事实，不持锁。
  /// 按产物路径反查调用记录。
  ///
  /// 图片调用没有 remoteTaskId，路径是它唯一能对上的线索——「收进资产库」
  /// 要拿 `localId` 当来源调用 id，只能这样反查。
  Future<VideoTaskLedgerEntry?> findByTargetPath(String targetPath) async {
    await ensureLoaded();
    final needle = targetPath.trim();
    if (needle.isEmpty) return null;
    for (final e in _entries) {
      if (e.targetPath == needle) return e;
    }
    return null;
  }

  Future<List<VideoTaskLedgerEntry>> pendingEntries() async {
    await ensureLoaded();
    return _entries.where((e) => e.status.isActive).toList();
  }

  /// 全部条目（含已完成/失败/放弃），按创建时间倒序。
  Future<List<VideoTaskLedgerEntry>> allEntries() async {
    await ensureLoaded();
    final list = _entries.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 删除条目。仅在产物已确认落盘后调用——台账是唯一的云端线索，
  /// 删早了就连「去哪取」都没了。
  Future<void> remove(String localId) async {
    await ensureLoaded();
    _entries.removeWhere((e) => e.localId == localId);
    await _persist();
  }

  /// 清理已终结且早于 [olderThan] 的条目，返回清理条数。
  ///
  /// 只清理 completed / failed / abandoned——active 的一个都不碰。
  /// 清理已终结的过期条目，返回清理条数。
  ///
  /// **按终结性质区别对待**（2026-10-13 实测依据）：已完成任务的云端 URL
  /// 长期有效（`expires_at` 为 null，十分钟前完成的任务仍可下载），所以
  /// 它的记录仍有取回价值——**永久保留，不清理**。失败与放弃的任务没有
  /// 可取回产物，按 [olderThan] 窗口清理。
  ///
  /// 仍在处理中的任务一个都不碰。
  Future<int> prune(Duration olderThan) async {
    await ensureLoaded();
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final before = _entries.length;
    _entries.removeWhere(
      (e) =>
          !e.status.isActive &&
          (e.status == VideoTaskLedgerStatus.failed ||
              e.status == VideoTaskLedgerStatus.abandoned) &&
          e.updatedAt.isBefore(cutoff),
    );
    final removed = before - _entries.length;
    if (removed > 0) await _persist();
    return removed;
  }

  /// 只清理已完成且早于 [olderThan] 的条目。
  ///
  /// 单独一个方法而不是给 [prune] 加开关：默认路径永不清理已完成条目，
  /// 这个方法是给"我确认不需要那些老产物了"的显式动作用的。
  Future<int> pruneCompleted(Duration olderThan) async {
    await ensureLoaded();
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final before = _entries.length;
    _entries.removeWhere(
      (e) =>
          e.status == VideoTaskLedgerStatus.completed &&
          e.updatedAt.isBefore(cutoff),
    );
    final removed = before - _entries.length;
    if (removed > 0) await _persist();
    return removed;
  }

  /// 测试用：把某个条目的 updatedAt 改老，用于验证 prune 的时间窗口。
  Future<void> backdateForTesting(String localId, Duration age) async {
    await ensureLoaded();
    final idx = _entries.indexWhere((e) => e.localId == localId);
    if (idx < 0) return;
    final old = _entries[idx];
    _entries[idx] = VideoTaskLedgerEntry(
      localId: old.localId,
      providerId: old.providerId,
      adapterId: old.adapterId,
      model: old.model,
      remoteTaskId: old.remoteTaskId,
      status: old.status,
      seriesId: old.seriesId,
      episodeId: old.episodeId,
      segmentId: old.segmentId,
      shotNumber: old.shotNumber,
      label: old.label,
      targetPath: old.targetPath,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().toUtc().subtract(age),
      lastRemoteStatus: old.lastRemoteStatus,
      lastProgress: old.lastProgress,
      sawInProgress: old.sawInProgress,
      elapsedPollMs: old.elapsedPollMs,
      error: old.error,
    );
    await _persist();
  }

  /// 测试用：清空内存与磁盘状态。
  void resetForTesting() {
    _entries.clear();
    _loaded = false;
  }

  /// 测试用：直接注入条目，跳过文件系统。
  void injectForTesting(VideoTaskLedgerEntry entry) {
    _entries.removeWhere((e) => e.localId == entry.localId);
    _entries.add(entry);
    _loaded = true;
  }

  /// 由 targetPath 反推所属上下文是否匹配（用于恢复时定位）。
  static bool contextMatches(
    VideoTaskLedgerEntry entry, {
    String? seriesId,
    String? episodeId,
    String? segmentId,
    int? shotNumber,
  }) {
    if (seriesId != null && entry.seriesId != seriesId) return false;
    if (episodeId != null && entry.episodeId != episodeId) return false;
    if (segmentId != null && entry.segmentId != segmentId) return false;
    if (shotNumber != null && entry.shotNumber != shotNumber) return false;
    return true;
  }

  /// 台账文件路径的展示用相对名（日志用）。
  static String describePath() => p.basename(AppPaths.videoTaskLedgerFile.path);
}
