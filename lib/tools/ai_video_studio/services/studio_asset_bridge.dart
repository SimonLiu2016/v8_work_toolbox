/// 视频下载器 → AI 短视频工坊 的素材搬运。
///
/// spec 16.1 / 16.2 + `video-downloader` 的 delta spec：
/// - 有活跃剧集项目时，保存路径选项里多一项「保存至 <剧集名> 素材目录」；
/// - 选中后把文件**复制**（不移动）到当前集的 `frames/`，原下载目录不动。
///
/// 复制而非移动是 spec 明确要求的：用户选的下载目录是他自己的浏览习惯，
/// 工坊借用素材不该偷偷把文件搬走。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../models/studio_models.dart';
import 'studio_project_manager.dart';

/// 工坊侧的「当前剧集」记录，供下载器读取。
///
/// 不直接持有 `StudioSession`：下载器是另一个工具的页面，让它依赖工坊的 UI
/// 会话对象会把两个工具的编译期绑死。这里只共享落盘的状态。
class StudioActiveProjectStore {
  StudioActiveProjectStore._();
  static final StudioActiveProjectStore instance = StudioActiveProjectStore._();

  /// 记录当前活跃的剧集与集。
  Future<void> setActive({
    required String seriesId,
    required String seriesName,
    String? episodeId,
    String? episodeTitle,
  }) async {
    _active = (
      seriesId: seriesId,
      seriesName: seriesName,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
    );
  }

  /// 工坊退出或没有选中任何剧集时调用。
  void clearActive() {
    _active = null;
  }

  ({
    String seriesId,
    String seriesName,
    String? episodeId,
    String? episodeTitle,
  })? _active;

  bool get hasActiveProject => _active != null;

  ({String seriesId, String seriesName, String? episodeId, String? episodeTitle})?
  get active => _active;

  /// 下载器「保存至剧集素材目录」选项的显示文本。
  ///
  /// 返回空串表示不该显示这个选项（没有活跃剧集）。
  String get shortcutLabel {
    final a = _active;
    if (a == null) return '';
    return '保存至《${a.seriesName}》素材目录';
  }
}

/// 把下载完成的文件搬进工坊素材目录的结果。
class StudioAssetImportResult {
  /// 复制后的绝对路径；null 表示没有复制（不该导入或导入失败）。
  final String? targetPath;

  /// 失败原因；成功时为 null。
  final String? error;

  const StudioAssetImportResult({this.targetPath, this.error});

  bool get ok => targetPath != null;
}

abstract final class StudioAssetImporter {
  /// 把下载文件复制到当前集的 `frames/`。
  ///
  /// 保留原文件不动（spec: 复制而非移动）。文件名带时间戳，避免同一集里
  /// 两个同名文件互相覆盖——用户可能连着下载多集素材。
  static Future<StudioAssetImportResult> importDownloadedFile({
    required String downloadedFilePath,
  }) async {
    final active = StudioActiveProjectStore.instance.active;
    if (active == null) {
      return const StudioAssetImportResult(error: '没有活跃的 AI 短视频工坊项目');
    }
    final source = File(downloadedFilePath);
    if (!await source.exists()) {
      return const StudioAssetImportResult(error: '下载文件不存在');
    }

    final series = StudioProjectManager.instance.readSeries(active.seriesId);
    if (series == null) {
      return const StudioAssetImportResult(error: '剧集项目已不存在');
    }

    // 没有选中集时落到该剧第一帧可用的目录：下载器不该替用户决定建新集。
    var episodeId = active.episodeId;
    if (episodeId == null) {
      final episodes =
          await StudioProjectManager.instance.listEpisodes(active.seriesId);
      if (episodes.isEmpty) {
        return const StudioAssetImportResult(
          error: '该剧还没有集，请先在工坊里新建一集',
        );
      }
      episodeId = episodes.first.id;
    }

    final framesDir = StudioProjectManager.instance
        .episodeFramesDir(active.seriesId, episodeId);
    await framesDir.create(recursive: true);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final name =
        '${p.basenameWithoutExtension(source.path)}_$stamp'
        '${p.extension(source.path)}';
    final target = File(p.join(framesDir.path, name));
    try {
      await source.copy(target.path);
    } catch (e) {
      return StudioAssetImportResult(error: '复制失败: $e');
    }
    return StudioAssetImportResult(targetPath: target.path);
  }

  /// 供 UI 显示的目标目录绝对路径（复制前预览给用户看）。
  static Future<String?> previewTargetDir() async {
    final active = StudioActiveProjectStore.instance.active;
    if (active == null) return null;
    final episodeId = active.episodeId;
    if (episodeId == null) return null;
    return StudioProjectManager.instance
        .episodeFramesDir(active.seriesId, episodeId)
        .path;
  }
}

/// 数据层路径的便捷引用（供下载器 UI 显示）。
String studioGlobalLibraryPath() =>
    AppPaths.videoStudioGlobalLibDir.path;

/// 数据层路径的便捷引用。
String studioSeriesRootPath() => AppPaths.videoStudioSeriesDir.path;

/// 由类型 id 拿到中文标签（下载器选项旁的类型说明）。
String studioProductionTypeLabel(String typeId) =>
    StudioProductionType.fromId(typeId).label;
