import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../../services/ai_config_store.dart';
import '../../../../services/ai_logger.dart';
import '../../../../services/keychain_service.dart';
import '../models/studio_models.dart';
import 'novel_import_task_service.dart';
import 'studio_project_manager.dart';
import 'video_gen_adapter.dart';
import 'video_task_ledger.dart';

/// 云端视频任务的恢复调度。
///
/// 存在的理由：视频任务创建即计费，而进程会被杀死。重启后云端任务还在跑，
/// 内存队列里却什么都不剩——用户付了钱、看不到视频、也没有线索。这个类把
/// 台账里「云端仍在处理」的任务重新挂起轮询，取回后写回原产物路径。
///
/// **绝不重复创建**：恢复路径只查询、不提交。重复创建 = 第二次计费，那是比
/// 不恢复更糟的 bug。
///
/// 与 `StudioTaskQueue` 的关系：那个管本进程的调度与并发；这个只在启动后跑
/// 一次扫描，把"没主人"的任务认领过来。两者不共享状态。
class VideoTaskRecovery {
  VideoTaskRecovery._();
  static final VideoTaskRecovery instance = VideoTaskRecovery._();

  /// 正在轮询中的 localId 集合。防止同一任务被认领两次（启动扫描 + 用户手动
  /// 「继续等待」可能同时到达）。
  final Set<String> _active = <String>{};

  bool _started = false;

  /// 启动时扫描一次。重复调用是 no-op。
  ///
  /// 不抛异常：恢复失败只意味着那个任务要继续等，不该阻断工坊启动。
  Future<void> startOnce() async {
    if (_started) return;
    _started = true;
    try {
      await _scanAndResume();
    } catch (e) {
      debugPrint('[VideoTaskRecovery] 启动扫描失败: $e');
    }
  }

  /// 测试用：重置启动标记与活跃集合。
  void resetForTesting() {
    _started = false;
    _active.clear();
  }

  /// 当前正在恢复轮询的任务数（UI 可显示「正在取回 N 个任务」）。
  int get activeCount => _active.length;

  Future<void> _scanAndResume() async {
    final pending = await VideoTaskLedger.instance.pendingEntries();
    if (pending.isEmpty) return;
    debugPrint('[VideoTaskRecovery] 发现 ${pending.length} 个未完成的云端视频任务');

    for (final entry in pending) {
      if (_active.contains(entry.localId)) continue;
      // 小说导入任务不归这里管。它重启后由 NovelImportTaskService
      // .recoverInterrupted() 标记为中断（HTTP 请求随进程死亡而断，续不了），
      // 而这里会把 `_buildAdapter` 返回 null 当作「供应商配置丢了，保持等待」，
      // 让导入条目以「云端仍在处理」的姿态永远挂在下轮 pending 里。
      // 显式跳过，不依赖 null 分支的偶然正确。
      if (entry.adapterId == NovelImportTaskService.adapterId) continue;
      // 串行认领：并行恢复会让多个长轮询同时打供应商，且这里没有并发调度器。
      // 任务之间本来就互不依赖，串行的代价只是第二个任务晚点开始轮询。
      unawaited(_resumeOne(entry));
    }
  }

  /// 恢复单个任务。失败只记日志，不影响其他任务。
  Future<void> _resumeOne(VideoTaskLedgerEntry entry) async {
    if (!_active.add(entry.localId)) return;
    try {
      final adapter = await _buildAdapter(entry);
      if (adapter == null) {
        debugPrint(
          '[VideoTaskRecovery] 无法为 ${entry.localId} 重建适配器（供应商可能已删除配置），保持等待',
        );
        return;
      }
      final key = await adapter.readApiKey();
      if (key == null || key.isEmpty) {
        debugPrint('[VideoTaskRecovery] ${entry.localId} 的 API Key 不可用，保持等待');
        return;
      }

      await VideoTaskLedger.instance.update(
        entry.localId,
        status: VideoTaskLedgerStatus.polling,
      );

      // 直接调用适配器的轮询入口。恢复路径复用同一套逻辑，不复制第二份。
      final videoUrl = await adapter.resumePolling(
        entry: entry,
        onProgress: (_) {},
      );
      if (videoUrl == null || videoUrl.isEmpty) {
        // 又超时了。台账已置为 cloudProcessing，下次启动会再试——这是
        // 「无限次追加预算」的实现方式。
        debugPrint('[VideoTaskRecovery] ${entry.localId} 本轮仍未完成，留待下次');
        return;
      }

      final target = File(entry.targetPath);
      await adapter.downloadTo(videoUrl, target);
      await writeBack(entry, target);
      await VideoTaskLedger.instance.update(
        entry.localId,
        status: VideoTaskLedgerStatus.completed,
        lastRemoteStatus: 'completed',
        lastProgress: 100,
      );
      AiLogger.logWarning(
        '已恢复并取回云端视频任务：${entry.label}',
        providerName: 'Agnes',
      );
    } catch (e) {
      debugPrint('[VideoTaskRecovery] 恢复 ${entry.localId} 失败: $e');
      await VideoTaskLedger.instance.update(
        entry.localId,
        status: VideoTaskLedgerStatus.failed,
        error: e.toString(),
      );
    } finally {
      _active.remove(entry.localId);
    }
  }

  /// 按台账条目重建适配器。
  ///
  /// 型号与地址从台账取——那是任务创建时的真实值，比当前槽位配置更可靠
  /// （用户可能已经换了默认模型，但那个云端任务还是老型号）。
  Future<AgnesVideoAdapter?> _buildAdapter(VideoTaskLedgerEntry entry) async {
    if (!entry.adapterId.startsWith('agnes')) return null;
    final store = AiConfigStore.instance;
    final providers = store.providers;
    AiProviderConfig? provider;
    for (final p in providers) {
      if (p.id == entry.providerId) {
        provider = p;
        break;
      }
    }
    // 供应商配置可能已被删除。退回按型号能力推断 baseUrl——Agnes 的地址是
    // 公开常量，不需要供应商配置也能查。
    final baseUrl = provider?.baseUrl ?? 'https://api.agnes-ai.cn/v1';
    // API Key 只在 Keychain 里（配置存的是 key id，不存密钥本身）。
    final apiKey = provider == null
        ? null
        : await KeychainService.instance.readSecret(provider.keychainKeyId);
    if (apiKey == null || apiKey.isEmpty) return null;

    return AgnesVideoAdapter(
      baseUrl: baseUrl,
      model: entry.model,
      apiKey: apiKey,
      providerId: entry.providerId,
    );
  }

  /// 把取回的视频写回剧集结构。
  ///
  /// 与 `SegmentVideoGenTask` 的写回保持同一条路径（`saveEpisode`）——不走
  /// 第二条写回逻辑，否则两边的状态字段会漂移。
  Future<void> writeBack(VideoTaskLedgerEntry entry, File video) async {
    if (entry.seriesId.isEmpty || entry.episodeId.isEmpty) return;
    final manager = StudioProjectManager.instance;
    final episode = manager.readEpisode(entry.seriesId, entry.episodeId);
    if (episode == null) return;

    if (entry.segmentId.isNotEmpty) {
      final idx = episode.segments.indexWhere((s) => s.id == entry.segmentId);
      if (idx < 0) return;
      final updated = episode.segments.toList();
      updated[idx] = updated[idx].copyWith(
        clipPath: video.uri.pathSegments.last,
        status: SegmentStatus.done,
      );
      await manager.saveEpisode(episode.copyWith(segments: updated));
      return;
    }

    if (entry.shotNumber != null) {
      final idx = episode.shots.indexWhere((s) => s.number == entry.shotNumber);
      if (idx < 0) return;
      final updated = episode.shots.toList();
      updated[idx] = updated[idx].copyWith(
        clipPath: video.uri.pathSegments.last,
        status: ShotGenerationStatus.done,
      );
      await manager.saveEpisode(episode.copyWith(shots: updated));
    }
  }

  /// 用户手动「继续等待」一个 cloudProcessing 任务。
  ///
  /// 与启动扫描的区别：这个是用户显式触发的，可以并行多个（用户知道自己要
  /// 什么）；启动扫描是保守的串行。
  Future<bool> resumeManually(String localId) async {
    final entry = await VideoTaskLedger.instance.findByLocalId(localId);
    if (entry == null) return false;
    if (!entry.status.isActive) return false;
    if (_active.contains(localId)) return false;
    unawaited(_resumeOne(entry));
    return true;
  }

  /// 放弃本地等待。**不影响云端**——Agnes 没有取消端点，任务仍在计费。
  ///
  /// UI 必须明说这一点，否则用户会以为点「放弃」就停止扣费。
  Future<void> abandon(String localId) async {
    await VideoTaskLedger.instance.update(
      localId,
      status: VideoTaskLedgerStatus.abandoned,
    );
  }

  /// 清理超过 [olderThan] 的已终结条目。
  Future<int> pruneOld(Duration olderThan) =>
      VideoTaskLedger.instance.prune(olderThan);

  /// 默认清理窗口：一周。终结任务的 video_id 在控制台还能查，但本地留着意义
  /// 不大；一周足够用户回来看一眼「上周那个失败是为什么」。
  static Duration get defaultPruneWindow => const Duration(days: 7);
}
