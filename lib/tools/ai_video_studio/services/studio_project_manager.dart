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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../services/app_paths.dart';
import '../models/studio_models.dart';

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
    final series = StudioSeries(
      id: idGenerator(),
      name: name.trim().isEmpty ? '未命名剧集' : name.trim(),
      productionType: productionType,
      worldview: worldview,
      styleTokens: styleTokens,
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
    await _ensureEpisodeDirs(episode.seriesId, episode.id);
    final updated = episode.copyWith(updatedAt: DateTime.now());
    await _writeJsonAtomic(
      episodeStoryboardFile(episode.seriesId, episode.id),
      updated.toJson(),
    );
  }

  /// 读一集。旧版数据在这里自动补齐片段分组（design 决策 2）。
  ///
  /// 迁移是纯函数、不落盘——见 [StudioEpisode.migrateSegmentsIfNeeded]。
  /// 因此「打开旧剧集」不会改变文件的 mtime，用户不会看到"我没编辑却被改了"。
  StudioEpisode? readEpisode(String seriesId, String episodeId) {
    return _readJson(
      episodeStoryboardFile(seriesId, episodeId),
      StudioEpisode.fromJson,
    )?.migrateSegmentsIfNeeded();
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
      if (episode != null) result.add(episode.migrateSegmentsIfNeeded());
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
    return _readJson(
      File(p.join(sceneDir(seriesId, sceneId).path, 'config.json')),
      SceneCard.fromJson,
    );
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
      if (card != null) result.add(card);
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> deleteScene(String seriesId, String sceneId) async {
    final dir = sceneDir(seriesId, sceneId);
    _forgetDirsUnder(dir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
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

    // 1. 增量更新角色卡库
    final existingCharacters = await listCharacters(seriesId);
    final rawChars = (masterExtraction['characters'] as List?) ?? const [];
    for (final c in rawChars) {
      if (c is! Map) continue;
      final name = (c['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;

      final descZh = ((c['description_zh'] ?? c['description'] ?? c['bio']) as String? ?? '').trim();
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
          basePromptPositive: basePos,
          basePromptNegative: baseNeg,
          variations: [
            CharacterVariation(
              id: idGenerator(),
              name: '默认',
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

      final existing = existingScenes.cast<SceneCard?>().firstWhere(
        (scene) => scene?.name.trim() == name,
        orElse: () => null,
      );

      if (existing != null) {
        // 已有场景：保留已有参考图，补全空缺描述
        final updatedScene = existing.copyWith(
          descriptionZh: existing.descriptionZh.isEmpty ? descZh : existing.descriptionZh,
          promptEn: existing.promptEn.isEmpty ? promptEn : existing.promptEn,
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
          updatedAt: now,
        );
        await saveScene(seriesId, sceneCard);
      }
    }

    // 3. 增量合并世界观与全局风格锁
    var combinedWorldview = series.worldview.trim();
    if (newWorldview.isNotEmpty) {
      if (combinedWorldview.isEmpty) {
        combinedWorldview = newWorldview;
      } else if (!combinedWorldview.contains(newWorldview)) {
        combinedWorldview = '$combinedWorldview\n\n【章节增量补充设定】\n$newWorldview';
      }
    }

    var combinedStyle = series.styleTokens.trim();
    if (newStyleTokens.isNotEmpty) {
      if (combinedStyle.isEmpty) {
        combinedStyle = newStyleTokens;
      } else if (!combinedStyle.contains(newStyleTokens)) {
        combinedStyle = '$combinedStyle, $newStyleTokens';
      }
    }

    final updatedSeries = series.copyWith(
      worldview: combinedWorldview,
      styleTokens: combinedStyle,
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

    final now = DateTime.now();
    final String epId = existingTarget?.id ?? idGenerator();
    final newEpisode = StudioEpisode(
      id: epId,
      seriesId: seriesId,
      index: targetEpisodeIndex,
      title: episodeTitle.trim().isNotEmpty ? episodeTitle.trim() : '第 $targetEpisodeIndex 集',
      synopsis: episodeSynopsis.trim(),
      shots: existingTarget?.shots ?? const [],
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
