/// AI 短视频工坊的项目/资产数据层。
///
/// 目录结构（spec: 本地文件目录结构）：
/// ```
/// AppSupportDir/video_studio/
/// ├── global_library/bgm/*.mp3     # 跨剧通用 BGM
/// ├── global_library/sfx/*.wav     # 跨剧通用音效
/// └── series_library/<series-id>/
///     ├── series_profile.json
///     ├── characters/<char-id>/config.json
///     ├── common_scenes/<scene-id>/config.json
///     └── episodes/<ep-id>/
///         ├── storyboard.json
///         ├── audio/  frames/  clips/  segments/  exports/
/// ```
///
/// `clips/` 放分镜级视频产物，`segments/` 放片段级产物（spec: 片段媒体存放与
/// 交付兼容）。合成交付按分镜顺序消费两者，见 `DeliveryPanel._readyClips`。
///
/// 所有 JSON 写入口都走 [_writeJsonAtomic]：先写 `.tmp` 再 rename。这是
/// design.md D4 的数据一致性承诺——断电或崩溃时用户拿到的是旧文件，而不是
/// 一个损坏的中间态 JSON。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/painting.dart' show FileImage, PaintingBinding;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../services/app_paths.dart';
import '../models/studio_models.dart';
import 'ai_constraint_engine.dart';
import 'image_gen_adapter.dart';
import 'prompt_assembler.dart';
import 'studio_preset_store.dart';

/// 创建资产卡时的默认 id 生成器（测试可注入固定值）。
typedef IdGenerator = String Function();

class StudioProjectManager {
  StudioProjectManager._();
  static final StudioProjectManager instance = StudioProjectManager._();

  static const IdGenerator _defaultIdGen = _uuidV4;

  /// 允许测试注入确定性 id；默认 uuid v4。
  @visibleForTesting
  static IdGenerator idGenerator = _defaultIdGen;

  static String _uuidV4() => const Uuid().v4();

  final Map<String, Directory> _ensuredDirs = {};

  /// 针对每一集的异步写入链，确保并发 saveEpisode 串行化，防止写覆盖。
  final Map<String, Future<void>> _writeChains = {};

  // ---------------------------------------------------------------------------
  // 目录解析
  // ---------------------------------------------------------------------------

  /// 单部剧的 IP 主库目录。
  Directory seriesDir(String seriesId) =>
      Directory(p.join(AppPaths.videoStudioSeriesDir.path, seriesId));

  Directory episodesDir(String seriesId) =>
      Directory(p.join(seriesDir(seriesId).path, 'episodes'));

  Directory episodeDir(String seriesId, String episodeId) =>
      Directory(p.join(episodesDir(seriesId).path, episodeId));

  Directory episodeAudioDir(String seriesId, String episodeId) =>
      Directory(p.join(episodeDir(seriesId, episodeId).path, 'audio'));

  Directory episodeFramesDir(String seriesId, String episodeId) =>
      Directory(p.join(episodeDir(seriesId, episodeId).path, 'frames'));

  Directory episodeClipsDir(String seriesId, String episodeId) =>
      Directory(p.join(episodeDir(seriesId, episodeId).path, 'clips'));

  /// 片段级视频产物目录（spec: 片段媒体存放与交付兼容）。
  ///
  /// 与 `clips/` 分开：`clips/` 放分镜级产物，`segments/` 放片段级产物。合成时
  /// 按分镜顺序优先取分镜级、缺失时取所属片段级，两个目录都可能被消费。
  Directory episodeSegmentsDir(String seriesId, String episodeId) =>
      Directory(p.join(episodeDir(seriesId, episodeId).path, 'segments'));

  Directory episodeExportsDir(String seriesId, String episodeId) =>
      Directory(p.join(episodeDir(seriesId, episodeId).path, 'exports'));

  Directory charactersDir(String seriesId) =>
      Directory(p.join(seriesDir(seriesId).path, 'characters'));

  Directory characterDir(String seriesId, String characterId) =>
      Directory(p.join(charactersDir(seriesId).path, characterId));

  Directory scenesDir(String seriesId) =>
      Directory(p.join(seriesDir(seriesId).path, 'common_scenes'));

  Directory sceneDir(String seriesId, String sceneId) =>
      Directory(p.join(scenesDir(seriesId).path, sceneId));

  Directory scenePanoramasDir(String seriesId, String sceneId) =>
      Directory(p.join(sceneDir(seriesId, sceneId).path, 'panoramas'));

  Directory ideasDir(String seriesId) =>
      Directory(p.join(seriesDir(seriesId).path, 'ideas'));

  File seriesProfileFile(String seriesId) =>
      File(p.join(seriesDir(seriesId).path, 'series_profile.json'));

  File episodeStoryboardFile(String seriesId, String episodeId) =>
      File(p.join(episodeDir(seriesId, episodeId).path, 'storyboard.json'));

  // ---------------------------------------------------------------------------
  // 目录准备
  // ---------------------------------------------------------------------------

  Future<void> ensureBaseStructure() async {
    await _ensureDir(AppPaths.videoStudioDir);
    await _ensureDir(AppPaths.videoStudioGlobalLibDir);
    await _ensureDir(
      Directory(p.join(AppPaths.videoStudioGlobalLibDir.path, 'bgm')),
    );
    await _ensureDir(
      Directory(p.join(AppPaths.videoStudioGlobalLibDir.path, 'sfx')),
    );
    await _ensureDir(AppPaths.videoStudioSeriesDir);
  }

  Future<void> _ensureSeriesDirs(String seriesId) async {
    await _ensureDir(seriesDir(seriesId));
    await _ensureDir(charactersDir(seriesId));
    await _ensureDir(scenesDir(seriesId));
    await _ensureDir(ideasDir(seriesId));
    await _ensureDir(episodesDir(seriesId));
  }

  Future<void> _ensureEpisodeDirs(String seriesId, String episodeId) async {
    await _ensureDir(episodeDir(seriesId, episodeId));
    await _ensureDir(episodeAudioDir(seriesId, episodeId));
    await _ensureDir(episodeFramesDir(seriesId, episodeId));
    await _ensureDir(episodeClipsDir(seriesId, episodeId));
    await _ensureDir(episodeSegmentsDir(seriesId, episodeId));
    await _ensureDir(episodeExportsDir(seriesId, episodeId));
  }

  Future<void> _ensureDir(Directory dir) async {
    final known = _ensuredDirs.containsKey(dir.path);
    if (known || dir.existsSync()) {
      _ensuredDirs[dir.path] = dir;
      return;
    }
    await dir.create(recursive: true);
    _ensuredDirs[dir.path] = dir;
  }

  // ---------------------------------------------------------------------------
  // 剧集项目 CRUD
  // ---------------------------------------------------------------------------

  /// 新建剧集项目，按 spec 自动建好整棵目录树并写下默认 `series_profile.json`。
  Future<StudioSeries> createSeries({
    required String name,
    StudioProductionType productionType = StudioProductionType.drama,
    String worldview = '',
    String styleTokens = '',
    String defaultVoiceId = '',
  }) async {
    await ensureBaseStructure();
    final now = DateTime.now();
    final resolvedStyle = styleTokens.trim().isNotEmpty
        ? styleTokens.trim()
        : productionType.defaultPositiveStyle;
    final series = StudioSeries(
      id: idGenerator(),
      name: name.trim().isEmpty ? '未命名剧集' : name.trim(),
      productionType: productionType,
      worldview: worldview,
      styleTokens: resolvedStyle,
      defaultVoiceId: defaultVoiceId,
      createdAt: now,
      updatedAt: now,
    );
    await _ensureSeriesDirs(series.id);
    await saveSeries(series);
    return series;
  }

  Future<void> saveSeries(StudioSeries series) async {
    await _ensureSeriesDirs(series.id);
    final updated = series.copyWith(updatedAt: DateTime.now());
    await _writeJsonAtomic(seriesProfileFile(series.id), updated.toJson());
  }

  StudioSeries? readSeries(String seriesId) {
    return _readJson(seriesProfileFile(seriesId), StudioSeries.fromJson);
  }

  Future<List<StudioSeries>> listSeries() async {
    await ensureBaseStructure();
    final root = AppPaths.videoStudioSeriesDir;
    if (!root.existsSync()) return const [];
    final result = <StudioSeries>[];
    for (final entry in root.listSync().whereType<Directory>()) {
      final series = _readJson(
        File(p.join(entry.path, 'series_profile.json')),
        StudioSeries.fromJson,
      );
      if (series != null) result.add(series);
    }
    // 最近修改的排前面，用户通常想接着改上一部。
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  /// 删除剧集项目及其全部素材。不可撤销，UI 层必须先确认。
  Future<void> deleteSeries(String seriesId) async {
    final dir = seriesDir(seriesId);
    _forgetDirsUnder(dir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // 单集 CRUD
  // ---------------------------------------------------------------------------

  /// 新建一集。会把上一集的摘要与末尾钩子带进 [memoryContext]，供调用方
  /// 注入 AI 上下文（spec: 跨集剧情记忆传递）。
  Future<({StudioEpisode episode, String memoryContext})> createEpisode({
    required String seriesId,
    String title = '',
    String synopsis = '',
  }) async {
    final series = readSeries(seriesId);
    if (series == null) {
      throw StateError('剧集项目不存在: $seriesId');
    }
    final existing = await listEpisodes(seriesId);
    final index = existing.length + 1;
    final now = DateTime.now();
    final episode = StudioEpisode(
      id: idGenerator(),
      seriesId: seriesId,
      index: index,
      title: title.trim().isEmpty ? '第 $index 集' : title.trim(),
      synopsis: synopsis,
      createdAt: now,
      updatedAt: now,
    );
    await _ensureEpisodeDirs(seriesId, episode.id);
    await saveEpisode(episode);
    return (
      episode: episode,
      memoryContext: buildMemoryContext(series, excludeEpisodeId: episode.id),
    );
  }

  Future<void> saveEpisode(StudioEpisode episode) async {
    final key = '${episode.seriesId}:${episode.id}';
    final previous = _writeChains[key] ?? Future<void>.value();
    final current = previous.catchError((_) {}).then((_) async {
      await _ensureEpisodeDirs(episode.seriesId, episode.id);
      final updated = episode.copyWith(updatedAt: DateTime.now());
      await _writeJsonAtomic(
        episodeStoryboardFile(episode.seriesId, episode.id),
        updated.toJson(),
      );
    });
    _writeChains[key] = current;
    await current;
    if (identical(_writeChains[key], current)) {
      _writeChains.remove(key);
    }
  }

  /// 原子更新剧集中的单个分镜（在写锁链路中重读最新 JSON、仅定位更新单个分镜并落盘）。
  ///
  /// 杜绝并发异步生图/生视频任务使用启动时获取的旧快照覆盖回写造成的其他分镜成果丢失。
  Future<StudioShot?> updateShot(
    String seriesId,
    String episodeId,
    int shotNumber,
    StudioShot Function(StudioShot current) update,
  ) async {
    final key = '$seriesId:$episodeId';
    final previous = _writeChains[key] ?? Future<void>.value();
    StudioShot? updatedShotResult;

    final current = previous.catchError((_) {}).then((_) async {
      await _ensureEpisodeDirs(seriesId, episodeId);
      final file = episodeStoryboardFile(seriesId, episodeId);
      final latest = _readJson(file, StudioEpisode.fromJson);
      if (latest == null) {
        throw StateError('找不到分镜所属的集数据：$episodeId');
      }
      final shotIndex = latest.shots.indexWhere((s) => s.number == shotNumber);
      if (shotIndex < 0) {
        throw StateError('该集没有镜号为 $shotNumber 的分镜');
      }

      final currentShot = latest.shots[shotIndex];
      final newShot = update(currentShot);
      updatedShotResult = newShot;

      final updatedShots = latest.shots.toList();
      updatedShots[shotIndex] = newShot;

      final updatedEpisode = latest.copyWith(
        shots: updatedShots,
        updatedAt: DateTime.now(),
      );

      await _writeJsonAtomic(file, updatedEpisode.toJson());
    });

    _writeChains[key] = current;
    await current;
    if (identical(_writeChains[key], current)) {
      _writeChains.remove(key);
    }
    return updatedShotResult;
  }

  /// 读一集。旧版数据在这里自动补齐片段分组（design 决策 2）。
  /// 并自动自愈检查磁盘上已存在但元数据被并发抹除的历史成片（spec: 历史成片自愈重连），
  /// 同时自愈分镜与场次的场景卡关联关系。
  StudioEpisode? readEpisode(String seriesId, String episodeId) {
    final ep = _readJson(
      episodeStoryboardFile(seriesId, episodeId),
      StudioEpisode.fromJson,
    )?.migrateSegmentsIfNeeded();
    if (ep == null) return null;
    final mediaHealed = _healEpisodeMediaIfNeeded(seriesId, ep);
    return _healEpisodeSceneBindingsSync(seriesId, mediaHealed);
  }

  /// 磁盘成片自愈重连检查：当磁盘物理文件存在且有效、但 JSON 中 clipPath 丢失时，
  /// 自动恢复 clipPath 与完成状态并静默保存，杜绝并发覆盖造成的历史成果丢失。
  StudioEpisode _healEpisodeMediaIfNeeded(String seriesId, StudioEpisode ep) {
    var hasChanges = false;
    final healedSegments = <StudioSegment>[];
    final segDir = episodeSegmentsDir(seriesId, ep.id);

    for (final seg in ep.segments) {
      if (seg.clipPath == null || seg.clipPath!.isEmpty || seg.status != SegmentStatus.done) {
        final candidateFile = File(p.join(segDir.path, '${seg.id}.mp4'));
        if (candidateFile.existsSync()) {
          int len = 0;
          try {
            len = candidateFile.lengthSync();
          } catch (_) {}
          if (len > 1024) {
            healedSegments.add(seg.copyWith(
              clipPath: '${seg.id}.mp4',
              status: SegmentStatus.done,
            ));
            hasChanges = true;
            continue;
          }
        }
      }
      healedSegments.add(seg);
    }

    final healedShots = <StudioShot>[];
    final clipDir = episodeClipsDir(seriesId, ep.id);
    final frameDir = episodeFramesDir(seriesId, ep.id);

    for (final shot in ep.shots) {
      var shotUpdated = shot;
      if (shot.clipPath == null || shot.clipPath!.isEmpty || shot.status != ShotGenerationStatus.done) {
        final candidateClips = [
          File(p.join(clipDir.path, 'shot_${shot.number}.mp4')),
          File(p.join(clipDir.path, '${shot.number}.mp4')),
        ];
        for (final candidateClip in candidateClips) {
          if (candidateClip.existsSync()) {
            int len = 0;
            try {
              len = candidateClip.lengthSync();
            } catch (_) {}
            if (len > 1024) {
              shotUpdated = shotUpdated.copyWith(
                clipPath: p.basename(candidateClip.path),
                status: ShotGenerationStatus.done,
              );
              hasChanges = true;
              break;
            }
          }
        }
      }
      if (shotUpdated.framePath == null || shotUpdated.framePath!.isEmpty) {
        final candidateFrames = [
          File(p.join(frameDir.path, 'shot_${shot.number}.png')),
          File(p.join(frameDir.path, '${shot.number}.png')),
        ];
        for (final candidateFrame in candidateFrames) {
          if (candidateFrame.existsSync()) {
            int len = 0;
            try {
              len = candidateFrame.lengthSync();
            } catch (_) {}
            if (len > 1024) {
              shotUpdated = shotUpdated.copyWith(
                framePath: p.basename(candidateFrame.path),
                status: ShotGenerationStatus.done,
              );
              hasChanges = true;
              break;
            }
          }
        }
      }
      healedShots.add(shotUpdated);
    }

    if (!hasChanges) return ep;

    final healedEp = ep.copyWith(
      segments: healedSegments,
      shots: healedShots,
    );
    unawaited(saveEpisode(healedEp));
    return healedEp;
  }

  /// 自动自愈剧集分镜与场次的场景卡绑定关系。
  /// 若分镜引用的 sceneId 是遗留的 'SC001' 等场次 ID，或与已注册场景卡失联，
  /// 自动根据所属 DramaScene 或分词打分恢复为真实的 SceneCard.id，杜绝前端出现"无关联场景"。
  StudioEpisode _healEpisodeSceneBindingsSync(String seriesId, StudioEpisode ep) {
    if (ep.shots.isEmpty && ep.scenes.isEmpty) return ep;
    final dir = scenesDir(seriesId);
    if (!dir.existsSync()) return ep;

    final cards = <SceneCard>[];
    for (final entry in dir.listSync().whereType<Directory>()) {
      final card = _readJson(
        File(p.join(entry.path, 'config.json')),
        SceneCard.fromJson,
      );
      if (card != null) cards.add(card);
    }
    if (cards.isEmpty) return ep;

    final validCardIds = cards.map((c) => c.id).toSet();
    var hasChanges = false;

    // 1. 先检查与修复 DramaScene.sceneCardId
    final updatedScenes = <DramaScene>[];
    for (final scene in ep.scenes) {
      if (scene.sceneCardId.isNotEmpty && validCardIds.contains(scene.sceneCardId)) {
        updatedScenes.add(scene);
      } else {
        final matchedCardId = AiConstraintEngine.resolveSceneCardId(scene, cards);
        if (matchedCardId.isNotEmpty && matchedCardId != scene.sceneCardId) {
          updatedScenes.add(scene.copyWith(sceneCardId: matchedCardId));
          hasChanges = true;
        } else {
          updatedScenes.add(scene);
        }
      }
    }

    // 2. 检查与修复 StudioShot.sceneId
    final updatedShots = <StudioShot>[];
    for (final shot in ep.shots) {
      if (shot.sceneId.isNotEmpty && validCardIds.contains(shot.sceneId)) {
        updatedShots.add(shot);
        continue;
      }

      // 需要修复：寻找对应的 DramaScene
      DramaScene? targetScene;
      if (shot.segmentId.isNotEmpty) {
        final segMatch = RegExp(r'seg-(\d+)').firstMatch(shot.segmentId);
        if (segMatch != null) {
          final segIdx = int.tryParse(segMatch.group(1) ?? '') ?? 0;
          if (segIdx >= 1 && segIdx <= updatedScenes.length) {
            targetScene = updatedScenes[segIdx - 1];
          }
        }
      }

      if (targetScene == null && shot.sceneId.startsWith('SC')) {
        targetScene = updatedScenes.where((s) => s.id == shot.sceneId).firstOrNull;
      }

      String resolvedId = '';
      if (targetScene != null) {
        if (targetScene.sceneCardId.isNotEmpty && validCardIds.contains(targetScene.sceneCardId)) {
          resolvedId = targetScene.sceneCardId;
        } else {
          resolvedId = AiConstraintEngine.resolveSceneCardId(targetScene, cards);
        }
      }

      if (resolvedId.isEmpty) {
        resolvedId = AiConstraintEngine.resolveSceneCardId(
          DramaScene(
            id: '',
            title: '',
            location: shot.continuity.worldPosition,
            atmosphere: shot.actionZh,
          ),
          cards,
        );
      }

      if (resolvedId.isNotEmpty && resolvedId != shot.sceneId) {
        updatedShots.add(shot.copyWith(sceneId: resolvedId));
        hasChanges = true;
      } else {
        // 如果依然没有匹配且旧值是 'SCxxx'，清空为 '' 避免无效引用
        if (shot.sceneId.startsWith('SC')) {
          updatedShots.add(shot.copyWith(sceneId: ''));
          hasChanges = true;
        } else {
          updatedShots.add(shot);
        }
      }
    }

    if (!hasChanges) return ep;

    final healedEp = ep.copyWith(
      scenes: updatedScenes,
      shots: updatedShots,
    );
    unawaited(saveEpisode(healedEp));
    return healedEp;
  }

  Future<List<StudioEpisode>> listEpisodes(String seriesId) async {
    final dir = episodesDir(seriesId);
    if (!dir.existsSync()) return const [];
    final result = <StudioEpisode>[];
    for (final entry in dir.listSync().whereType<Directory>()) {
      final episode = _readJson(
        File(p.join(entry.path, 'storyboard.json')),
        StudioEpisode.fromJson,
      );
      if (episode != null) {
        final migrated = episode.migrateSegmentsIfNeeded();
        final mediaHealed = _healEpisodeMediaIfNeeded(seriesId, migrated);
        result.add(_healEpisodeSceneBindingsSync(seriesId, mediaHealed));
      }
    }
    result.sort((a, b) => a.index.compareTo(b.index));
    return result;
  }

  Future<void> deleteEpisode(String seriesId, String episodeId) async {
    final dir = episodeDir(seriesId, episodeId);
    _forgetDirsUnder(dir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // 角色资产卡 CRUD
  // ---------------------------------------------------------------------------

  Future<CharacterCard> createCharacter({
    required String seriesId,
    required String name,
    String descriptionZh = '',
  }) async {
    await _ensureSeriesDirs(seriesId);
    final now = DateTime.now();
    final card = CharacterCard(
      id: idGenerator(),
      name: name.trim().isEmpty ? '未命名角色' : name.trim(),
      descriptionZh: descriptionZh,
      variations: [
        CharacterVariation(
          id: idGenerator(),
          name: '默认',
          active: true,
        ),
      ],
      updatedAt: now,
    );
    await saveCharacter(seriesId, card);
    return card;
  }

  Future<void> saveCharacter(String seriesId, CharacterCard card) async {
    await _ensureDir(characterDir(seriesId, card.id));
    await _writeJsonAtomic(
      File(p.join(characterDir(seriesId, card.id).path, 'config.json')),
      card.copyWith(updatedAt: DateTime.now()).toJson(),
    );
  }

  CharacterCard? readCharacter(String seriesId, String characterId) {
    return _readJson(
      File(p.join(characterDir(seriesId, characterId).path, 'config.json')),
      CharacterCard.fromJson,
    );
  }

  Future<List<CharacterCard>> listCharacters(String seriesId) async {
    final dir = charactersDir(seriesId);
    if (!dir.existsSync()) return const [];
    final result = <CharacterCard>[];
    for (final entry in dir.listSync().whereType<Directory>()) {
      final card = _readJson(
        File(p.join(entry.path, 'config.json')),
        CharacterCard.fromJson,
      );
      if (card != null) result.add(card);
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> deleteCharacter(String seriesId, String characterId) async {
    final dir = characterDir(seriesId, characterId);
    _forgetDirsUnder(dir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 复制一张基准参考图进角色目录，返回相对文件名（写进 config.json）。
  Future<String> addCharacterReference({
    required String seriesId,
    required String characterId,
    required String sourceFilePath,
  }) async {
    final dir = characterDir(seriesId, characterId);
    await _ensureDir(dir);
    await _ensureDir(Directory(p.join(dir.path, 'references')));
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(sourceFilePath)}';
    final target = File(p.join(dir.path, 'references', fileName));
    await File(sourceFilePath).copy(target.path);
    return p.join('references', fileName);
  }

  /// 从标准三视图正面视图区域自动裁切免冠面部特写锚点（`face_anchor.png`）。
  ///
  /// 标定排版：三视图中正面视图位于左侧 1/3（X 约 2%~32%），头部发型五官位于顶部（Y 约 3%~26%）。
  /// 裁切后保存为 `face_anchor.png`，更新角色卡的 `faceAnchorPath`。
  Future<File?> cropAndSaveFaceAnchor({
    required String seriesId,
    required String characterId,
    required File turnaroundFile,
  }) async {
    if (!await turnaroundFile.exists()) return null;
    try {
      final bytes = await turnaroundFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final w = image.width;
      final h = image.height;

      final isLandscape = w > h;
      final cropX = (w * (isLandscape ? 0.05 : 0.02)).round().clamp(0, w - 1);
      final cropY = (h * (isLandscape ? 0.05 : 0.03)).round().clamp(0, h - 1);
      final cropW = (w * (isLandscape ? 0.23 : 0.30)).round().clamp(1, w - cropX);
      final cropH = (h * (isLandscape ? 0.35 : 0.23)).round().clamp(1, h - cropY);

      final cropped = img.copyCrop(
        image,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );

      final dir = characterDir(seriesId, characterId);
      await _ensureDir(dir);
      final faceAnchorFile = File(p.join(dir.path, 'face_anchor.png'));
      await faceAnchorFile.writeAsBytes(img.encodePng(cropped));

      final card = readCharacter(seriesId, characterId);
      if (card != null) {
        final updated = card.copyWith(faceAnchorPath: 'face_anchor.png');
        await saveCharacter(seriesId, updated);
      }
      return faceAnchorFile;
    } catch (e) {
      debugPrint('[StudioProjectManager] cropAndSaveFaceAnchor failed: $e');
      return null;
    }
  }

  /// 将用户上传或选择的图片设为该角色的面部特写锚点（`face_anchor.png`）。
  Future<File?> setFaceAnchor({
    required String seriesId,
    required String characterId,
    required File imageFile,
  }) async {
    if (!await imageFile.exists()) return null;
    try {
      final dir = characterDir(seriesId, characterId);
      await _ensureDir(dir);
      final target = File(p.join(dir.path, 'face_anchor.png'));
      await imageFile.copy(target.path);

      final card = readCharacter(seriesId, characterId);
      if (card != null) {
        final updated = card.copyWith(faceAnchorPath: 'face_anchor.png');
        await saveCharacter(seriesId, updated);
      }
      try {
        PaintingBinding.instance.imageCache.evict(FileImage(target));
      } catch (_) {}
      return target;
    } catch (e) {
      debugPrint('[StudioProjectManager] setFaceAnchor failed: $e');
      return null;
    }
  }

  /// 删除角色的面部特写锚点（`face_anchor.png`），并清空卡片引用与图片缓存。
  Future<bool> deleteFaceAnchor({
    required String seriesId,
    required String characterId,
  }) async {
    final dir = characterDir(seriesId, characterId);
    final target = File(p.join(dir.path, 'face_anchor.png'));
    try {
      if (await target.exists()) {
        await target.delete();
      }
    } catch (e) {
      debugPrint('[StudioProjectManager] deleteFaceAnchor file delete failed: $e');
    }
    try {
      PaintingBinding.instance.imageCache.evict(FileImage(target));
    } catch (_) {}

    final card = readCharacter(seriesId, characterId);
    if (card != null) {
      final updated = card.copyWith(clearFaceAnchorPath: true);
      await saveCharacter(seriesId, updated);
      return true;
    }
    return false;
  }

  /// 将已裁剪的图像数据保存为该角色的面部特写锚点（`face_anchor.png`）。
  Future<File?> saveFaceAnchorImage({
    required String seriesId,
    required String characterId,
    required img.Image faceImage,
  }) async {
    try {
      final dir = characterDir(seriesId, characterId);
      await _ensureDir(dir);
      final target = File(p.join(dir.path, 'face_anchor.png'));
      final pngBytes = img.encodePng(faceImage);
      await target.writeAsBytes(pngBytes, flush: true);

      try {
        PaintingBinding.instance.imageCache.evict(FileImage(target));
      } catch (_) {}

      final card = readCharacter(seriesId, characterId);
      if (card != null) {
        final updated = card.copyWith(faceAnchorPath: 'face_anchor.png');
        await saveCharacter(seriesId, updated);
      }
      return target;
    } catch (e) {
      debugPrint('[StudioProjectManager] saveFaceAnchorImage failed: $e');
      return null;
    }
  }

  /// 根据指定的像素矩形区域，从源图片中裁切并保存面部特写锚点。
  Future<File?> cropFaceAnchorFromRect({
    required String seriesId,
    required String characterId,
    required File sourceImageFile,
    required int cropX,
    required int cropY,
    required int cropW,
    required int cropH,
  }) async {
    if (!await sourceImageFile.exists()) return null;
    try {
      final bytes = await sourceImageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final safeX = cropX.clamp(0, image.width - 1);
      final safeY = cropY.clamp(0, image.height - 1);
      final safeW = cropW.clamp(1, image.width - safeX);
      final safeH = cropH.clamp(1, image.height - safeY);

      final cropped = img.copyCrop(
        image,
        x: safeX,
        y: safeY,
        width: safeW,
        height: safeH,
      );
      return await saveFaceAnchorImage(
        seriesId: seriesId,
        characterId: characterId,
        faceImage: cropped,
      );
    } catch (e) {
      debugPrint('[StudioProjectManager] cropFaceAnchorFromRect failed: $e');
      return null;
    }
  }


  /// 独立生成 1:1 面部特写锚点图（免受全身服装干扰，纯粹锚定五官与发型）。
  Future<File> generateFaceAnchor({
    required String seriesId,
    required String characterId,
    ImageGenAdapter? imageAdapter,
    VisualEraGenre? eraGenre,
    String styleTokens = '',
  }) async {
    final card = readCharacter(seriesId, characterId);
    if (card == null) {
      throw StateError('Character $characterId not found');
    }
    final dir = characterDir(seriesId, characterId);
    await _ensureDir(dir);
    final target = File(p.join(dir.path, 'face_anchor.png'));

    final prompt = CharacterTurnaroundPrompt.buildPortrait(
      card.effectiveFacialPrompt,
      styleTokens: styleTokens,
      eraGenre: eraGenre,
      descriptionZh: card.facialFeaturesZh.isNotEmpty ? card.facialFeaturesZh : card.descriptionZh,
      negativePrompt: card.basePromptNegative,
    );
    final negative = CharacterTurnaroundPrompt.buildNegativePortrait(
      baseNegative: card.basePromptNegative,
      descriptionZh: card.facialFeaturesZh.isNotEmpty ? card.facialFeaturesZh : card.descriptionZh,
      positiveText: card.effectiveFacialPrompt,
    );

    final adapter = imageAdapter ?? SystemAiImageAdapter();
    await adapter.generate(ImageGenRequest(
      prompt: prompt,
      negativePrompt: negative,
      shotNumber: 0,
      outputFile: target,
      width: 1024,
      height: 1024,
      referenceImages: const [],
    ));

    final updated = card.copyWith(faceAnchorPath: 'face_anchor.png');
    await saveCharacter(seriesId, updated);
    return target;
  }

  // ---------------------------------------------------------------------------
  // 场景资产卡 CRUD
  // ---------------------------------------------------------------------------

  Future<SceneCard> createScene({
    required String seriesId,
    required String name,
    String descriptionZh = '',
    String promptEn = '',
    List<String> referenceImages = const [],
    bool sharedAcrossSeries = false,
  }) async {
    await _ensureSeriesDirs(seriesId);
    final now = DateTime.now();
    final card = SceneCard(
      id: idGenerator(),
      name: name.trim().isEmpty ? '未命名场景' : name.trim(),
      descriptionZh: descriptionZh,
      promptEn: promptEn,
      referenceImages: referenceImages,
      sharedAcrossSeries: sharedAcrossSeries,
      updatedAt: now,
    );
    await saveScene(seriesId, card);
    return card;
  }

  // ---------------------------------------------------------------------------
  // 创意方案历史持久化
  // ---------------------------------------------------------------------------

  Future<void> saveIdeaHistory(String seriesId, List<IdeaDirection> ideas) async {
    await _ensureSeriesDirs(seriesId);
    final file = File(p.join(ideasDir(seriesId).path, 'idea_history.json'));
    await _writeJsonAtomic(
      file,
      {'ideas': ideas.map((e) => e.toJson()).toList()},
    );
  }

  Future<List<IdeaDirection>> listIdeaHistory(String seriesId) async {
    final file = File(p.join(ideasDir(seriesId).path, 'idea_history.json'));
    final json = _readJson(file, (m) => m);
    if (json == null) return const [];
    final list = json['ideas'] as List?;
    if (list == null) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(IdeaDirection.fromJson)
        .toList();
  }

  Future<void> saveScene(String seriesId, SceneCard card) async {
    await _ensureDir(sceneDir(seriesId, card.id));
    await _writeJsonAtomic(
      File(p.join(sceneDir(seriesId, card.id).path, 'config.json')),
      card.copyWith(updatedAt: DateTime.now()).toJson(),
    );
  }

  SceneCard? readScene(String seriesId, String sceneId) {
    final card = _readJson(
      File(p.join(sceneDir(seriesId, sceneId).path, 'config.json')),
      SceneCard.fromJson,
    );
    if (card == null) return null;
    return _healPanoramaMasterPath(seriesId, card);
  }

  Future<List<SceneCard>> listScenes(String seriesId) async {
    final dir = scenesDir(seriesId);
    if (!dir.existsSync()) return const [];
    final result = <SceneCard>[];
    for (final entry in dir.listSync().whereType<Directory>()) {
      final card = _readJson(
        File(p.join(entry.path, 'config.json')),
        SceneCard.fromJson,
      );
      if (card != null) {
        result.add(_healPanoramaMasterPath(seriesId, card));
      }
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// 全景母图自愈守卫：若场景配置中的全景母图路径丢失或文件不存在，
  /// 但该场景底层的 panoramas/ 目录物理存在 pano_master_*.png，
  /// 则自动恢复关联最新的全景母图文件，避免因配置覆写而导致用户数据丢失。
  SceneCard _healPanoramaMasterPath(String seriesId, SceneCard card) {
    final sDir = sceneDir(seriesId, card.id);
    if (card.panoramaMasterPath != null && card.panoramaMasterPath!.isNotEmpty) {
      final f = File(p.isAbsolute(card.panoramaMasterPath!)
          ? card.panoramaMasterPath!
          : p.join(sDir.path, card.panoramaMasterPath!));
      if (f.existsSync()) return card;
    }

    // 扫描 panoramas/ 物理目录
    final panoDir = scenePanoramasDir(seriesId, card.id);
    if (panoDir.existsSync()) {
      final files = panoDir.listSync().whereType<File>().where((f) {
        final name = p.basename(f.path).toLowerCase();
        return name.startsWith('pano_master_') &&
            (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg'));
      }).toList();

      if (files.isNotEmpty) {
        files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        final newest = files.first;
        final rel = p.relative(newest.path, from: sDir.path);
        final healed = card.copyWith(panoramaMasterPath: rel);
        // 异步修复回写 config.json（无需阻塞等待）
        saveScene(seriesId, healed).catchError((e) {
          debugPrint('[StudioProjectManager] 自愈全景母图配置回写失败: $e');
        });
        return healed;
      }
    }
    return card;
  }

  Future<void> deleteScene(String seriesId, String sceneId) async {
    final dir = sceneDir(seriesId, sceneId);
    _forgetDirsUnder(dir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 确保传入的一组戏剧场次在场景库中均有对应场景卡。全新场景自动增量建卡入库并绑定 sceneCardId。
  Future<List<DramaScene>> _ensureScenesForDramaScenes(
    String seriesId,
    List<DramaScene> scenes,
  ) async {
    if (scenes.isEmpty) return const [];
    final existingCards = await listScenes(seriesId);
    final cardList = List<SceneCard>.from(existingCards);
    final resultScenes = <DramaScene>[];

    for (final s in scenes) {
      var resolvedId = AiConstraintEngine.resolveSceneCardId(s, cardList);
      if (resolvedId.isEmpty && (s.location.trim().isNotEmpty || s.title.trim().isNotEmpty)) {
        final cardName = s.location.trim().isNotEmpty ? s.location.trim() : s.title.trim();
        final now = DateTime.now();
        final newCard = SceneCard(
          id: idGenerator(),
          name: cardName,
          descriptionZh: '${s.location}。${s.atmosphere}'.trim(),
          promptEn: '${s.location}, ${s.setting}, ${s.timeOfDay}',
          updatedAt: now,
        );
        await saveScene(seriesId, newCard);
        cardList.add(newCard);
        resolvedId = newCard.id;
      }
      if (resolvedId.isNotEmpty && s.sceneCardId != resolvedId) {
        resultScenes.add(s.copyWith(sceneCardId: resolvedId));
      } else {
        resultScenes.add(s);
      }
    }
    return resultScenes;
  }

  /// 确保指定剧集的戏剧场次与 IP 场景库卡片完全同步。
  /// 对于未能匹配到现有场景卡的全新剧本地点，自动在场景库中增量新建 SceneCard 并完成绑定。
  /// 返回补齐/绑定完成后的最新场景卡列表。
  Future<List<SceneCard>> ensureScenesForEpisode({
    required String seriesId,
    required StudioEpisode episode,
  }) async {
    final updatedScenes = await _ensureScenesForDramaScenes(seriesId, episode.scenes);
    if (updatedScenes.isNotEmpty && updatedScenes != episode.scenes) {
      await saveEpisode(episode.copyWith(scenes: updatedScenes));
    }
    return listScenes(seriesId);
  }

  /// 批量对剧集的所有场景（或仅未解构的场景）执行七方位空间全息推演并落盘。
  Future<int> deconstructAllScenesSpatialProfiles(
    String seriesId, {
    bool overwriteExisting = false,
    void Function(int current, int total, String sceneName)? onProgress,
  }) async {
    final series = readSeries(seriesId);
    final eraGenre = series?.eraGenre ?? '';
    final visualStyle = series?.styleTokens ?? '';
    final prodType = series?.productionType.id ?? 'drama';
    final scenes = await listScenes(seriesId);
    if (scenes.isEmpty) return 0;

    var updatedCount = 0;
    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i];
      if (!overwriteExisting && scene.hasSpatialDeconstruction) {
        continue;
      }
      onProgress?.call(i + 1, scenes.length, scene.name);

      try {
        final result = await AiConstraintEngine.deconstructSceneSpatialProfile(
          sceneName: scene.name,
          baseDescription: scene.descriptionZh,
          eraGenre: eraGenre,
          visualStyle: visualStyle,
          productionType: prodType,
        );

        final newSpatialViews = AiConstraintEngine.parseSpatialViewsFromResult(
          result.data,
          baseScene: scene,
        );

        // 如果原图存在，将其保留到 front 视角
        if (scene.referenceImages.isNotEmpty &&
            (!newSpatialViews.containsKey(SceneDirection.front.name) ||
                !newSpatialViews[SceneDirection.front.name]!.hasImage)) {
          final front = newSpatialViews[SceneDirection.front.name] ??
              SceneDirectionalView(direction: SceneDirection.front);
          newSpatialViews[SceneDirection.front.name] = front.copyWith(
            imagePath: scene.referenceImages.first,
          );
        }

        final updatedCard = scene.copyWith(
          spatialViews: newSpatialViews,
          updatedAt: DateTime.now(),
        );

        await saveScene(seriesId, updatedCard);
        updatedCount++;
      } catch (e) {
        debugPrint('[StudioProjectManager] 场景 ${scene.name} 七方位解构跳过/失败: $e');
      }
    }
    return updatedCount;
  }

  // ---------------------------------------------------------------------------
  // 道具资产卡 CRUD
  //
  // 与角色/场景同构，但存储走 series_profile.json 的 props 列表而不是每道具
  // 一个 config.json：道具是无产物目录需求的轻资产（参考图按需才生成），
  // 拆成 N 个文件会让"这部剧有哪些道具"要读 N 次盘。参考图仍然按道具分子
  // 目录存放——那是大文件，不该进 JSON。
  // ---------------------------------------------------------------------------

  Directory propsDir(String seriesId) =>
      Directory(p.join(seriesDir(seriesId).path, 'props'));

  Directory propDir(String seriesId, String propId) =>
      Directory(p.join(propsDir(seriesId).path, propId));

  Future<PropCard> createProp({
    required String seriesId,
    required String name,
    String descriptionZh = '',
    String promptEn = '',
    bool isKeyProp = false,
  }) async {
    await _ensureSeriesDirs(seriesId);
    final series = readSeries(seriesId);
    if (series == null) {
      throw StateError('剧集项目不存在: $seriesId');
    }
    final card = PropCard(
      id: idGenerator(),
      name: name.trim().isEmpty ? '未命名道具' : name.trim(),
      descriptionZh: descriptionZh,
      promptEn: promptEn,
      isKeyProp: isKeyProp,
      updatedAt: DateTime.now(),
    );
    await saveSeries(series.copyWith(props: [...series.props, card]));
    return card;
  }

  Future<void> saveProp(String seriesId, PropCard card) async {
    final series = readSeries(seriesId);
    if (series == null) {
      throw StateError('剧集项目不存在: $seriesId');
    }
    final props = series.props.map((p) => p.id == card.id ? card : p).toList();
    await saveSeries(series.copyWith(props: props));
  }

  PropCard? readProp(String seriesId, String propId) {
    return readSeries(seriesId)?.props
        .where((p) => p.id == propId)
        .firstOrNull;
  }

  Future<List<PropCard>> listProps(String seriesId) async {
    final series = readSeries(seriesId);
    if (series == null) return const [];
    final result = series.props.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> deleteProp(String seriesId, String propId) async {
    final series = readSeries(seriesId);
    if (series == null) return;
    await saveSeries(
      series.copyWith(
        props: series.props.where((p) => p.id != propId).toList(),
      ),
    );
    final dir = propDir(seriesId, propId);
    _forgetDirsUnder(dir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 复制一张参考图进道具目录，返回相对文件名（写进 PropCard.referenceImages）。
  Future<String> addPropReference({
    required String seriesId,
    required String propId,
    required String sourceFilePath,
  }) async {
    final dir = propDir(seriesId, propId);
    await _ensureDir(dir);
    await _ensureDir(Directory(p.join(dir.path, 'references')));
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(sourceFilePath)}';
    final target = File(p.join(dir.path, 'references', fileName));
    await File(sourceFilePath).copy(target.path);
    return p.join('references', fileName);
  }

  /// 复制一张参考图进场景目录，返回相对文件名（写进 SceneCard.referenceImages）。
  Future<String> addSceneReference({
    required String seriesId,
    required String sceneId,
    required String sourceFilePath,
  }) async {
    final dir = sceneDir(seriesId, sceneId);
    await _ensureDir(dir);
    await _ensureDir(Directory(p.join(dir.path, 'references')));
    final fileName =
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(sourceFilePath)}';
    final target = File(p.join(dir.path, 'references', fileName));
    await File(sourceFilePath).copy(target.path);
    return p.join('references', fileName);
  }

  /// 保存 360° 等矩全景母图至场景专属 panoramas/ 目录，返回相对路径并自动落盘更新配置。
  Future<String> saveScenePanoramaMaster({
    required String seriesId,
    required String sceneId,
    required String sourceFilePath,
  }) async {
    final panoDir = scenePanoramasDir(seriesId, sceneId);
    await _ensureDir(panoDir);
    final ext = p.extension(sourceFilePath).isNotEmpty ? p.extension(sourceFilePath) : '.png';
    final fileName = 'pano_master_${DateTime.now().microsecondsSinceEpoch}$ext';
    final target = File(p.join(panoDir.path, fileName));
    await File(sourceFilePath).copy(target.path);
    final relPath = p.join('panoramas', fileName);

    final currentScene = readScene(seriesId, sceneId);
    if (currentScene != null) {
      await saveScene(
        seriesId,
        currentScene.copyWith(panoramaMasterPath: relPath),
      );
    }
    return relPath;
  }

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // 小说资产增量合并与单集/全案入库
  // ---------------------------------------------------------------------------

  /// 增量合并小说提炼出的世界观、角色库与场景库。
  ///
  /// - 角色卡：按姓名查重。如果已存在同名角色，保留其已有 ID、anchor 图与自定义提示词，仅补充描述；如为新角色则新增。
  /// - 场景库：按场景名查重。如果已存在同名场景则保留，如为新场景则新增。
  /// - 世界观与风格：如果已有世界观且新世界观非空，以段落追加；风格词如果非空且不包含则以逗号合并追加。
  Future<StudioSeries> mergeMasterAssets({
    required String seriesId,
    required Map<String, dynamic> masterExtraction,
  }) async {
    final series = readSeries(seriesId);
    if (series == null) {
      throw StateError('剧集项目不存在: $seriesId');
    }
    await _ensureSeriesDirs(seriesId);

    final newWorldview = (masterExtraction['worldview'] as String? ?? '').trim();
    final newStyleTokens = ((masterExtraction['style_tokens'] ?? masterExtraction['global_style']) as String? ?? '').trim();
    final now = DateTime.now();

    // 1. 增量更新角色卡库
    final existingCharacters = await listCharacters(seriesId);
    final rawChars = (masterExtraction['characters'] as List?) ?? const [];
    for (final c in rawChars) {
      if (c is! Map) continue;
      final name = (c['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;

      final descZh = ((c['description_zh'] ?? c['description'] ?? c['bio']) as String? ?? '').trim();
      final facialZh = (c['facial_features_zh'] as String? ?? '').trim();
      final facialPos = (c['facial_prompt'] as String? ?? '').trim();
      final attireZh = (c['default_attire_zh'] as String? ?? '').trim();
      final attirePos = (c['attire_prompt'] as String? ?? '').trim();
      final basePos = ((c['base_prompt_positive'] ?? c['prompt_positive'] ?? c['prompt']) as String? ?? '').trim();
      final baseNeg = ((c['base_prompt_negative'] ?? c['prompt_negative']) as String? ?? '').trim();
      final now = DateTime.now();

      final existing = existingCharacters.cast<CharacterCard?>().firstWhere(
        (card) => card?.name.trim() == name,
        orElse: () => null,
      );

      if (existing != null) {
        // 已有角色：保留已有锚点图片与定制提示词，若描述有增量则丰富
        final updatedChar = existing.copyWith(
          descriptionZh: existing.descriptionZh.isEmpty ? descZh : existing.descriptionZh,
          facialFeaturesZh: existing.facialFeaturesZh.isEmpty
              ? (facialZh.isNotEmpty ? facialZh : descZh)
              : existing.facialFeaturesZh,
          facialPrompt: existing.facialPrompt.isEmpty
              ? (facialPos.isNotEmpty ? facialPos : basePos)
              : existing.facialPrompt,
          defaultAttireZh: existing.defaultAttireZh.isEmpty ? attireZh : existing.defaultAttireZh,
          defaultAttirePrompt: existing.defaultAttirePrompt.isEmpty ? attirePos : existing.defaultAttirePrompt,
          basePromptPositive: existing.basePromptPositive.isEmpty ? basePos : existing.basePromptPositive,
          basePromptNegative: existing.basePromptNegative.isEmpty ? baseNeg : existing.basePromptNegative,
          updatedAt: now,
        );
        await saveCharacter(seriesId, updatedChar);
      } else {
        // 新角色：新增入库
        final charCard = CharacterCard(
          id: idGenerator(),
          name: name,
          descriptionZh: descZh,
          facialFeaturesZh: facialZh.isNotEmpty ? facialZh : descZh,
          facialPrompt: facialPos.isNotEmpty ? facialPos : basePos,
          defaultAttireZh: attireZh,
          defaultAttirePrompt: attirePos,
          basePromptPositive: basePos,
          basePromptNegative: baseNeg,
          variations: [
            CharacterVariation(
              id: idGenerator(),
              name: '默认',
              attirePrompt: attirePos,
              active: true,
            ),
          ],
          updatedAt: now,
        );
        await saveCharacter(seriesId, charCard);
      }
    }

    // 2. 增量更新场景库
    final existingScenes = await listScenes(seriesId);
    final rawScenes = (masterExtraction['scenes'] as List?) ?? const [];
    for (final s in rawScenes) {
      if (s is! Map) continue;
      final name = (s['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;

      final descZh = ((s['description_zh'] ?? s['description']) as String? ?? '').trim();
      final promptEn = ((s['prompt_en'] ?? s['prompt_positive'] ?? s['prompt']) as String? ?? '').trim();
      final now = DateTime.now();

      final rawSpatial = s['spatial_views'] as Map? ?? s['views'] as Map?;
      final spatialViews = <String, SceneDirectionalView>{};
      if (rawSpatial != null) {
        for (final entry in rawSpatial.entries) {
          if (entry.value is Map) {
            final viewMap = (entry.value as Map).map((k, v) => MapEntry(k.toString(), v));
            final dir = SceneDirection.fromKey(entry.key.toString());
            spatialViews[dir.name] = SceneDirectionalView.fromJson(viewMap, dir);
          }
        }
      }

      final existing = existingScenes.cast<SceneCard?>().firstWhere(
        (scene) => scene?.name.trim() == name,
        orElse: () => null,
      );

      if (existing != null) {
        // 已有场景：保留已有参考图，补全空缺描述与空间视角
        final mergedViews = Map<String, SceneDirectionalView>.from(existing.fullSpatialViews);
        for (final e in spatialViews.entries) {
          if (e.value.hasContent && (!mergedViews.containsKey(e.key) || !mergedViews[e.key]!.hasContent)) {
            mergedViews[e.key] = e.value;
          }
        }
        final updatedScene = existing.copyWith(
          descriptionZh: existing.descriptionZh.isEmpty ? descZh : existing.descriptionZh,
          promptEn: existing.promptEn.isEmpty ? promptEn : existing.promptEn,
          spatialViews: mergedViews,
          updatedAt: now,
        );
        await saveScene(seriesId, updatedScene);
      } else {
        // 新场景：新增入库
        final sceneCard = SceneCard(
          id: idGenerator(),
          name: name,
          descriptionZh: descZh,
          promptEn: promptEn,
          spatialViews: spatialViews,
          updatedAt: now,
        );
        await saveScene(seriesId, sceneCard);
      }
    }

    // 3. 增量更新关键道具库
    final existingProps = await listProps(seriesId);
    final rawProps = (masterExtraction['props'] as List?) ?? const [];
    for (final p in rawProps) {
      if (p is! Map) continue;
      final name = (p['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;

      final descZh = ((p['description_zh'] ?? p['description']) as String? ?? '').trim();
      final promptEn = ((p['prompt_en'] ?? p['prompt']) as String? ?? '').trim();

      final existing = existingProps.cast<PropCard?>().firstWhere(
        (card) => card?.name.trim() == name,
        orElse: () => null,
      );

      if (existing != null) {
        final updatedProp = existing.copyWith(
          descriptionZh: existing.descriptionZh.isEmpty ? descZh : existing.descriptionZh,
          promptEn: existing.promptEn.isEmpty ? promptEn : existing.promptEn,
          updatedAt: now,
        );
        await saveProp(seriesId, updatedProp);
      } else {
        final propCard = PropCard(
          id: idGenerator(),
          name: name,
          descriptionZh: descZh,
          promptEn: promptEn,
          updatedAt: now,
        );
        await saveProp(seriesId, propCard);
      }
    }

    // 4. 增量合并世界观、时代题材与全局风格锁
    final latestSeries = readSeries(seriesId) ?? series;
    var combinedWorldview = latestSeries.worldview.trim();
    if (newWorldview.isNotEmpty) {
      if (combinedWorldview.isEmpty) {
        combinedWorldview = newWorldview;
      } else if (!combinedWorldview.contains(newWorldview)) {
        combinedWorldview = '$combinedWorldview\n\n【章节增量补充设定】\n$newWorldview';
      }
    }

    final newEraGenre = (masterExtraction['era_genre'] as String? ?? '').trim();
    var combinedEraGenre = latestSeries.eraGenre.trim();
    if (combinedEraGenre.isEmpty && newEraGenre.isNotEmpty) {
      combinedEraGenre = newEraGenre;
    }

    final newStyleId = (masterExtraction['aesthetic_style'] as String? ?? '').trim();
    var combinedStyleId = latestSeries.styleId.trim();
    if (combinedStyleId.isEmpty && newStyleId.isNotEmpty) {
      combinedStyleId = newStyleId;
    }

    final matchedStyle = StudioPresetStore.instance.getStyleById(combinedStyleId);

    var combinedStyle = latestSeries.styleTokens.trim();
    if (newStyleTokens.isNotEmpty) {
      if (combinedStyle.isEmpty) {
        combinedStyle = newStyleTokens;
      } else if (!combinedStyle.contains(newStyleTokens)) {
        combinedStyle = '$combinedStyle, $newStyleTokens';
      }
    } else if (combinedStyle.isEmpty && matchedStyle != null && matchedStyle.positiveAnchor.isNotEmpty) {
      combinedStyle = matchedStyle.positiveAnchor;
    }

    var combinedNegativeStyle = latestSeries.negativeStyleTokens.trim();
    if (combinedNegativeStyle.isEmpty && matchedStyle != null && matchedStyle.negativeBan.isNotEmpty) {
      combinedNegativeStyle = matchedStyle.negativeBan;
    }

    final updatedSeries = latestSeries.copyWith(
      worldview: combinedWorldview,
      eraGenre: combinedEraGenre,
      styleId: combinedStyleId,
      styleTokens: combinedStyle,
      negativeStyleTokens: combinedNegativeStyle,
      updatedAt: DateTime.now(),
    );
    await saveSeries(updatedSeries);
    return updatedSeries;
  }

  /// 将单章节内容导入扩写至指定集数，不破坏其他集数大纲。
  ///
  /// - [targetEpisodeIndex]：若指定且存在对应序号集，则更新该集；若序号超过现有集数或为新集，则追加为新集。
  Future<StudioSeries> importChapterToEpisode({
    required String seriesId,
    required Map<String, dynamic> masterExtraction,
    required int targetEpisodeIndex,
    required String episodeTitle,
    required String episodeSynopsis,
    required String episodeSummary,
    required String episodeHook,
    List<DramaScene> scenes = const [],
    String screenplayText = '',
    ProtectedContract protectedContract = ProtectedContract.empty,
  }) async {
    // 1. 增量合并角色、场景与世界观资产
    final mergedSeries = await mergeMasterAssets(
      seriesId: seriesId,
      masterExtraction: masterExtraction,
    );

    // 2. 检查并更新或追加指定集数
    final existingEpisodes = await listEpisodes(seriesId);
    existingEpisodes.sort((a, b) => a.index.compareTo(b.index));

    final existingTarget = existingEpisodes.cast<StudioEpisode?>().firstWhere(
      (ep) => ep?.index == targetEpisodeIndex,
      orElse: () => null,
    );

    // 1.1 增量确保传入剧本场次在场景库中均有对应卡片并绑定 sceneCardId
    final rawScenes = scenes.isNotEmpty ? scenes : (existingTarget?.scenes ?? const []);
    final syncedScenes = await _ensureScenesForDramaScenes(seriesId, rawScenes);

    final now = DateTime.now();
    final String epId = existingTarget?.id ?? idGenerator();

    final effectiveScreenplayText = screenplayText.trim().isNotEmpty
        ? screenplayText.trim()
        : (syncedScenes.isNotEmpty
            ? DramaScene.exportToMarkdown(syncedScenes)
            : (existingTarget?.screenplayText ?? ''));

    final newEpisode = StudioEpisode(
      id: epId,
      seriesId: seriesId,
      index: targetEpisodeIndex,
      title: episodeTitle.trim().isNotEmpty ? episodeTitle.trim() : '第 $targetEpisodeIndex 集',
      synopsis: episodeSynopsis.trim(),
      shots: const [], // 单章重新导入时重置分镜列表，分镜必须后续由打磨后的剧本生成
      scenes: syncedScenes,
      screenplayText: effectiveScreenplayText,
      protectedContract: protectedContract.isNotEmpty ? protectedContract : (existingTarget?.protectedContract ?? ProtectedContract.empty),
      createdAt: existingTarget?.createdAt ?? now,
      updatedAt: now,
    );

    await _ensureEpisodeDirs(seriesId, epId);
    await saveEpisode(newEpisode);

    // 3. 更新剧情记忆库
    final currentMemories = List<EpisodeMemory>.from(mergedSeries.memories);
    final memoryIdx = currentMemories.indexWhere((m) => m.episodeId == epId);
    final newMemory = EpisodeMemory(
      episodeId: epId,
      title: newEpisode.title,
      summary: episodeSummary.trim(),
      hook: episodeHook.trim(),
      shotCount: newEpisode.shots.length,
      updatedAt: now,
    );

    if (memoryIdx >= 0) {
      currentMemories[memoryIdx] = newMemory;
    } else {
      currentMemories.add(newMemory);
    }

    final finalSeries = mergedSeries.copyWith(
      memories: currentMemories,
      updatedAt: now,
    );
    await saveSeries(finalSeries);
    return finalSeries;
  }

  /// 全案长篇小说解构入库（全季规划）。
  ///
  /// 返回更新后的 [StudioSeries] 实例。
  Future<StudioSeries> importNovelProject({
    required String seriesId,
    required Map<String, dynamic> masterExtraction,
    required Map<String, dynamic> episodeSegmentation,
  }) async {
    // 1. 增量入库角色、场景与世界观
    final mergedSeries = await mergeMasterAssets(
      seriesId: seriesId,
      masterExtraction: masterExtraction,
    );

    // 2. 清理旧剧集目录并按推荐分集批量创建剧集大纲与剧情记忆
    final oldEpisodes = await listEpisodes(seriesId);
    for (final ep in oldEpisodes) {
      await deleteEpisode(seriesId, ep.id);
    }

    final rawEpisodes = (episodeSegmentation['episodes'] as List?) ?? const [];
    final memories = <EpisodeMemory>[];
    final now = DateTime.now();

    for (var i = 0; i < rawEpisodes.length; i++) {
      final epData = rawEpisodes[i];
      if (epData is! Map) continue;
      final epId = idGenerator();
      final epIndex = (epData['index'] as num?)?.toInt() ?? (i + 1);
      final title = (epData['title'] as String? ?? '第 $epIndex 集').trim();
      final synopsis = (epData['synopsis'] as String? ?? '').trim();
      final summary = (epData['summary'] as String? ?? '').trim();
      final hook = (epData['hook'] as String? ?? '').trim();

      final episode = StudioEpisode(
        id: epId,
        seriesId: seriesId,
        index: epIndex,
        title: title,
        synopsis: synopsis,
        shots: const [],
        createdAt: now,
        updatedAt: now,
      );
      await _ensureEpisodeDirs(seriesId, epId);
      await saveEpisode(episode);

      memories.add(EpisodeMemory(
        episodeId: epId,
        title: title,
        summary: summary,
        hook: hook,
        shotCount: 0,
        updatedAt: now,
      ));
    }

    // 3. 更新并持久化 Series Profile
    final updatedSeries = mergedSeries.copyWith(
      memories: memories,
      updatedAt: DateTime.now(),
    );
    await saveSeries(updatedSeries);
    return updatedSeries;
  }


  // ---------------------------------------------------------------------------
  // 剧情记忆库
  // ---------------------------------------------------------------------------

  /// 构造注入 AI 的上下文字符串（前情摘要 + 上集钩子）。
  ///
  /// spec 的记忆库只保留 200 字以内摘要，所以这里也逐条截断——注入内容膨胀会
  /// 直接吃掉模型上下文窗口，而那部分开销用户完全看不到。
  String buildMemoryContext(StudioSeries series, {String? excludeEpisodeId}) {
    final buffer = StringBuffer();
    final memories = series.memories
        .where((m) => m.episodeId != excludeEpisodeId)
        .toList()
      ..sort((a, b) => a.episodeId.length.compareTo(b.episodeId.length));
    if (memories.isEmpty) return '';
    buffer.writeln('【前情提要】');
    for (final m in memories) {
      final summary = m.summary.trim();
      if (summary.isEmpty) continue;
      buffer.writeln('- ${m.title}：${_truncate(summary, 200)}');
    }
    final last = memories.lastWhere(
      (m) => m.hook.trim().isNotEmpty,
      orElse: () => memories.last,
    );
    if (last.hook.trim().isNotEmpty) {
      buffer.writeln('【上集末尾钩子】${_truncate(last.hook.trim(), 200)}');
    }
    return buffer.toString().trim();
  }

  /// 保存/更新某集的记忆条目（新集保存时由 AI 摘要回填）。
  Future<void> upsertEpisodeMemory({
    required String seriesId,
    required String episodeId,
    String? title,
    String? summary,
    String? hook,
    int? shotCount,
  }) async {
    final series = readSeries(seriesId);
    if (series == null) return;
    final memories = [...series.memories];
    final idx = memories.indexWhere((m) => m.episodeId == episodeId);
    if (idx >= 0) {
      memories[idx] = memories[idx].copyWith(
        title: title ?? memories[idx].title,
        summary: summary ?? memories[idx].summary,
        hook: hook ?? memories[idx].hook,
        shotCount: shotCount ?? memories[idx].shotCount,
        updatedAt: DateTime.now(),
      );
    } else {
      memories.add(EpisodeMemory(
        episodeId: episodeId,
        title: title ?? '',
        summary: summary ?? '',
        hook: hook ?? '',
        shotCount: shotCount ?? 0,
        updatedAt: DateTime.now(),
      ));
    }
    await saveSeries(series.copyWith(memories: memories));
  }

  // ---------------------------------------------------------------------------
  // 全局公共库索引
  // ---------------------------------------------------------------------------

  final Map<String, List<GlobalAudioAsset>> _globalAudioCache = {};

  /// 上次扫描时间，供 UI 显示"公共库更新于 x 分钟前"。
  DateTime? get globalLibraryScannedAt => _globalAudioScannedAt;
  DateTime? _globalAudioScannedAt;

  /// 扫描全局公共库的 BGM/SFX 文件列表。
  ///
  /// 结果按 kind 缓存；缓存期间新增的文件不会出现，直到调用方传
  /// `forceRefresh: true`（用户在 Finder 里手动丢素材正是这条路）。
  Future<Map<String, List<GlobalAudioAsset>>> scanGlobalLibrary({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _globalAudioCache.isNotEmpty) {
      return Map.unmodifiable(_globalAudioCache);
    }
    await ensureBaseStructure();
    final result = <String, List<GlobalAudioAsset>>{};
    for (final kind in ['bgm', 'sfx']) {
      final dir = Directory(
        p.join(AppPaths.videoStudioGlobalLibDir.path, kind),
      );
      final assets = <GlobalAudioAsset>[];
      if (dir.existsSync()) {
        for (final entry in dir.listSync().whereType<File>()) {
          final ext = p.extension(entry.path).toLowerCase();
          if (!_kAudioExtensions.contains(ext)) continue;
          final name = p.basenameWithoutExtension(entry.path);
          assets.add(GlobalAudioAsset(
            name: name,
            path: entry.path,
            kind: kind,
            mood: inferMoodFromName(name),
            sourceLayer: 'global',
            sizeBytes: entry.lengthSync(),
          ));
        }
      }
      assets.sort((a, b) => a.name.compareTo(b.name));
      result[kind] = assets;
    }
    _globalAudioCache
      ..clear()
      ..addAll(result);
    _globalAudioScannedAt = DateTime.now();
    return Map.unmodifiable(_globalAudioCache);
  }

  /// 扫描 IP 主库自带的 BGM（`<series>/library/bgm/`），层级标为 `series`。
  Future<List<GlobalAudioAsset>> scanSeriesBgm(String seriesId) async {
    final dir = Directory(
      p.join(seriesDir(seriesId).path, 'library', 'bgm'),
    );
    if (!dir.existsSync()) return const [];
    final assets = <GlobalAudioAsset>[];
    for (final entry in dir.listSync().whereType<File>()) {
      final ext = p.extension(entry.path).toLowerCase();
      if (!_kAudioExtensions.contains(ext)) continue;
      final name = p.basenameWithoutExtension(entry.path);
      assets.add(GlobalAudioAsset(
        name: name,
        path: entry.path,
        kind: 'bgm',
        mood: inferMoodFromName(name),
        sourceLayer: 'series',
        sizeBytes: entry.lengthSync(),
      ));
    }
    assets.sort((a, b) => a.name.compareTo(b.name));
    return assets;
  }

  /// 从文件名推断情绪标签。
  ///
  /// 全局库没有维护元数据库，用户最常见的做法就是把情绪写进文件名
  /// （`战斗_高潮.mp3`）。推断不到就返回空，调用方按"未分类"展示，
  /// 不硬塞一个默认情绪——那会让 BGM 推荐面板显示错误的标注。
  static String inferMoodFromName(String fileName) {
    final lower = fileName.toLowerCase();
    for (final mood in ShotMood.values) {
      if (lower.contains(mood.id) || fileName.contains(mood.label)) {
        return mood.id;
      }
    }
    if (lower.contains('battle') || lower.contains('fight')) return 'battle';
    return '';
  }

  /// 测试用：清空目录与缓存记忆。
  @visibleForTesting
  void resetCachesForTesting() {
    _ensuredDirs.clear();
    _globalAudioCache.clear();
    _globalAudioScannedAt = null;
  }

  // ---------------------------------------------------------------------------
  // 原子写入
  // ---------------------------------------------------------------------------

  static const Set<String> _kAudioExtensions = {
    '.mp3',
    '.wav',
    '.m4a',
    '.aac',
    '.flac',
    '.ogg',
  };

  /// 先写 `.tmp` 再 rename。rename 在同一文件系统上是原子的，读者要么看到
  /// 旧内容要么看到新内容，不会读到半截 JSON。
  Future<void> _writeJsonAtomic(File target, Map<String, dynamic> data) async {
    final dir = target.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    try {
      if (await target.exists()) {
        await target.delete();
      }
    } catch (_) {
      // 目标不存在时 rename 本身就能覆盖，删除失败可忽略。
    }
    await temp.rename(target.path);
  }

  T? _readJson<T>(File file, T Function(Map<String, dynamic>) fromJson) {
    try {
      if (!file.existsSync()) return null;
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.map((k, v) => MapEntry(k as String, v)));
    } catch (e) {
      // 单个损坏文件不该让整个列表页打不开：跳过它，其余项目照常展示。
      debugPrint('读取 JSON 失败，已跳过: ${file.path} ($e)');
      return null;
    }
  }

  void _forgetDirsUnder(Directory dir) {
    final prefix = '${dir.path}${p.separator}';
    _ensuredDirs.removeWhere((path, _) => path.startsWith(prefix));
  }

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}…';
  }
}
