import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';

/// 两个 AI 五维拆镜入口共用的输入取值逻辑（spec: 拆镜入口的输入一致性）。
///
/// 剧本工作台与分镜看板都有「AI 五维拆镜」按钮。旧实现两边各拼各的：剧本
/// 台传打磨过的文学剧本全文，看板只传 4 行粗大纲文本框的内容——用户在两个
/// 面板点同一个按钮，喂给 AI 的输入源完全不同。
///
/// 现在两边都调这个函数，取值优先级固定为：
/// ```
/// synopsis = screenplayText.isNotEmpty ? screenplayText : ep.synopsis
/// scenes   = ep.scenes
/// contract = ep.protectedContract
/// ```
abstract final class BreakdownInput {
  /// 本集最新的文学剧本文本；为空时回退到粗大纲。
  ///
  /// 注意：分镜看板的 `_synopsisController` 默认初始化为 `episode.synopsis`。
  /// 只有当调用方传入的 [rawTextOverride] 非空且与 `episode.synopsis.trim()`
  /// 确实不同（即用户主动改写了输入框，或在全文模式下编辑了不同文本）时，才将其
  /// 视为显式覆盖；否则优先采用已打磨的 `episode.screenplayText`。
  static String synopsisOf(StudioEpisode episode, {String? rawTextOverride}) {
    final overrideText = rawTextOverride?.trim() ?? '';
    final defaultSynopsis = episode.synopsis.trim();
    final screenplay = episode.screenplayText.trim();
    if (overrideText.isNotEmpty && overrideText != defaultSynopsis) {
      return overrideText;
    }
    if (screenplay.isNotEmpty) return screenplay;
    if (overrideText.isNotEmpty) return overrideText;
    return defaultSynopsis;
  }

  /// 检测本集的文学剧本全文是否相对于结构化场次发生过独立修改。
  ///
  /// 当用户在剧本工作台的 Markdown 全文模式下修改了剧情并保留修改时，
  /// `screenplayText` 会与 `DramaScene.exportToMarkdown(scenes)` 不一致。
  /// 此时拆镜应以 `screenplayText` 为最高优先级剧情依据。
  static bool hasUnsyncedRawScreenplay(
    StudioEpisode episode, {
    String? rawTextOverride,
  }) {
    if (episode.scenes.isEmpty) return false;
    final effectiveText = (rawTextOverride != null &&
            rawTextOverride.trim().isNotEmpty &&
            rawTextOverride.trim() != episode.synopsis.trim())
        ? rawTextOverride.trim()
        : episode.screenplayText.trim();
    if (effectiveText.isEmpty) return false;
    final exported = DramaScene.exportToMarkdown(episode.scenes).trim();
    return effectiveText != exported;
  }

  /// 结构化场次与节拍。
  static List<DramaScene> scenesOf(StudioEpisode episode) => episode.scenes;

  /// 受保护契约。
  static ProtectedContract contractOf(StudioEpisode episode) =>
      episode.protectedContract;
}

/// 角色形态的四级解析优先级（spec: 生图与生视频的参考图取材同源 & 单镜角色形态激活的互斥唯一性）。
///
/// 优先级：分镜显式指定 → 单集覆盖 → 分镜动作/状态变化文本匹配形态名 → 角色默认激活形态。
abstract final class ShotVariationResolver {
  static CharacterVariation? resolve({
    required StudioEpisode? episode,
    required StudioShot shot,
    required CharacterCard? character,
  }) {
    if (character == null) return null;
    // 1. 分镜显式指定的形态。
    final shotVarId = shot.characterVariations[character.id];
    if (shotVarId != null && shotVarId.isNotEmpty) {
      final found =
          character.variations.where((v) => v.id == shotVarId).firstOrNull;
      if (found != null) return found;
    }
    // 2. 单集覆盖。
    if (episode != null &&
        episode.variationOverrides.containsKey(character.id)) {
      final epVarId = episode.variationOverrides[character.id];
      final found =
          character.variations.where((v) => v.id == epVarId).firstOrNull;
      if (found != null) return found;
    }
    // 3. 分镜动作描述或连续性状态变化中显式提及了某个非默认形态名称。
    final haystack =
        '${shot.actionZh} ${shot.continuity.stateChanges.join(' ')}'.trim();
    if (haystack.isNotEmpty) {
      for (final v in character.variations) {
        final name = v.name.trim();
        if (name.isEmpty || name == '默认' || name == '默认形态') continue;
        if (haystack.contains(name)) {
          return v;
        }
      }
    }
    // 4. 角色默认激活形态；一个都没有时为 null（不是"默认形态"的占位）。
    return character.activeVariation;
  }

  /// 为指定分镜构造唯一激活目标形态的临时 [CharacterCard]。
  ///
  /// 必须把未命中的形态显式置为 `active: false`，因为 [CharacterCard.activeVariation]
  /// 取的是列表中第一个 `active == true` 的项；若不重置第 0 个「默认」形态，
  /// 下游 `AssetBindingResolver` 永远只能拿到第 0 个形态。
  static CharacterCard resolveCharacterForShot({
    required StudioEpisode? episode,
    required StudioShot shot,
    required CharacterCard character,
  }) {
    final resolved = resolve(
      episode: episode,
      shot: shot,
      character: character,
    );
    if (resolved == null) return character;
    return character.copyWith(
      variations: [
        for (final v in character.variations)
          v.copyWith(active: v.id == resolved.id),
      ],
    );
  }
}
