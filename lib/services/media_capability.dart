/// 模型能力矩阵（spec: 模型能力声明 / 请求参数规整）。
///
/// 为什么需要它：四个视频/图像适配器原先各自把模型参数写死 + clamp——
/// SenseAudio 恒发 `'ratio': '9:16'` / `'resolution': '720p'`，Agnes 恒发
/// `'aspect_ratio': '9:16'`。上游网关因此以 `plugin usage enum is not an
/// allowed value` 一类 400 拒绝，而每次接新模型都要重演一遍「发现 400 → 加一条
/// 特判」。Toonflow 的解法是把能力变成**可声明、可查询、可测试的数据**
/// （`packages/providers/src/media/*.ts` 的 `mode` + `durationResolutionMap`）。
///
/// 三种使用方式：
/// - **声明**：`AiProviderConfig.mediaCapabilities` 里按模型 id 覆盖
/// - **查询**：[MediaCapabilityResolver.resolve] 未命中时按协议取保守默认
/// - **规整**：[MediaRequestNormalizer] 把请求参数落到能力范围内
library;

import 'package:flutter/foundation.dart' show immutable;

/// 生成模式。对应 Toonflow `MediaModel.mode` 的取值。
///
/// 用一个枚举而不是字符串，是为了让「模式不被支持」这类判断在编译期就能发现
/// 漏写分支——字符串比较在加新模式时会静默失配。
enum MediaGenMode {
  /// 纯文本生成（文生图 / 文生视频）。
  text('text'),

  /// 单图输入（图生图 / 图生视频）。
  singleImage('singleImage'),

  /// 首尾帧都必须提供。
  startEndRequired('startEndRequired'),

  /// 尾帧可选。
  endFrameOptional('endFrameOptional'),

  /// 首帧可选。
  startFrameOptional('startFrameOptional'),

  /// 多参考图（数量上限由 [MediaModelCapability.maxReferenceImages] 给）。
  multiReference('multiReference');

  final String id;
  const MediaGenMode(this.id);

  static MediaGenMode? fromId(String? value) {
    if (value == null) return null;
    for (final m in values) {
      if (m.id == value) return m;
    }
    return null;
  }
}

/// 一个模型的能力声明。
///
/// [isDeclared] 是这张表上最重要的字段：它区分「这是模型官方文档/实测的结论」
/// 与「协议猜的兜底」。UI 必须把后者标注为「默认能力，未经确认」，否则用户
/// 会以为限制是被验证过的，从而不敢调、或乱调。
@immutable
class MediaModelCapability {
  /// 支持的生成模式。空集合表示不限制（保守起见放行所有模式）。
  final Set<MediaGenMode> modes;

  /// 支持的时长集合（秒，视频用）。空集合表示不限制。
  final List<int> durations;

  /// 时长 → 可用分辨率。缺省时按 [resolutions] 通用。
  ///
  /// 用 Map 而不是 Toonflow 的数组，是因为 Dart 侧只需要「给定时长有哪些
  /// 分辨率」这一种查询；数组形态的 `durationResolutionMap` 在 UI 上反而要
  /// 展开成二维表。
  final Map<int, List<String>> durationResolutions;

  /// 通用分辨率集合（图像用，或视频未按时长区分时用）。
  final List<String> resolutions;

  /// 支持的画幅比例，如 `9:16`。空集合表示不限制。
  final List<String> ratios;

  /// 可接受的参考图数量上限，三态：
  ///
  /// - `0`：明确不支持参考图，携带即拒；
  /// - `null`：没测过上限，放行任意数量；
  /// - 正数：有上限，超过即拒。
  ///
  /// 之所以不用 `0` 表达「没测过」：那会让 UI 显示"不支持参考图"这句假话，
  /// 用户于是根本不用这个引擎做片段级生成——比测试红着严重得多。也不用
  /// 虚构大数：UI 会显示"最多支持 100 张"，那是比"不支持"更坏的假话，
  /// 它给了用户错误的预期。
  final int? maxReferenceImages;

  /// 是否支持指定首帧。
  final bool supportsFirstFrame;

  /// 是否支持指定尾帧。
  final bool supportsLastFrame;

  /// 是否支持原生音频（视频模型）。
  final bool supportsNativeAudio;

  /// 是否支持负向提示词（图像模型）。默认支持，不支持的模型（如 Agnes 图像）将在提交前剔除负向词。
  final bool supportsNegativePrompt;

  /// 是否为显式声明（false = 协议级保守默认）。
  final bool isDeclared;

  const MediaModelCapability({
    this.modes = const {},
    this.durations = const [],
    this.durationResolutions = const {},
    this.resolutions = const [],
    this.ratios = const [],
    this.maxReferenceImages = 0,
    this.supportsFirstFrame = false,
    this.supportsLastFrame = false,
    this.supportsNativeAudio = false,
    this.supportsNegativePrompt = true,
    this.isDeclared = false,
  });

  /// 给定时长下可用的分辨率。未按时长区分时回落到通用集合。
  List<String> resolutionsFor(int durationSec) =>
      durationResolutions[durationSec] ?? resolutions;

  /// 时长是否被支持。空集合表示不限制。
  bool supportsDuration(int durationSec) =>
      durations.isEmpty || durations.contains(durationSec);

  /// 取**不超过** [requested] 的最大合法时长。
  ///
  /// 向下取整而不是四舍五入：向上可能取到用户没要求的值（为多余的时间付费），
  /// 而向下保证「不超过预期」这条不可破坏的期望。全部合法时长都大于请求值时
  /// 返回最小的那个——那已经是模型能给出的最近值。
  int snapDuration(int requested) {
    if (durations.isEmpty) return requested;
    final sorted = [...durations]..sort();
    var best = sorted.first;
    for (final d in sorted) {
      if (d <= requested) best = d;
    }
    return best;
  }

  /// 取比例最接近的合法值。
  ///
  /// 评分是「比例差 × 10 + 像素量差」，比例优先但不唯一：`1152x2048` 与
  /// `864x1536` 的比例差都是 0，但前者像素量更接近工坊请求的 1080×1920，
  /// 出图细节更多。纯比例差会让两者打平、永远取列表里靠前的那个——那通常
  /// 是白名单里较小的那个（`864x1536` 排在 `1152x2048` 前面），用户得不到
  /// 本该得到的清晰度。
  String snapResolution(String requested, List<String> legal) {
    if (legal.isEmpty) return requested;
    if (legal.contains(requested)) return requested;
    final requestedRatio = _ratioOf(requested);
    if (requestedRatio == null) return legal.first;
    final requestedPixels = _pixelsOf(requested);
    var best = legal.first;
    var bestScore = double.infinity;
    for (final candidate in legal) {
      final ratio = _ratioOf(candidate);
      if (ratio == null) continue;
      final pixels = _pixelsOf(candidate);
      final pixelDelta = requestedPixels > 0 && pixels > 0
          ? (pixels - requestedPixels).abs() / requestedPixels
          : 0.0;
      final score = (ratio - requestedRatio).abs() * 10.0 + pixelDelta;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  /// 解析 `1152x2048` 的像素量；解析不出返回 0。
  static double _pixelsOf(String value) {
    final match = RegExp(r'(\d+)\s*[x×]\s*(\d+)').firstMatch(value);
    if (match == null) return 0;
    final w = int.tryParse(match.group(1)!);
    final h = int.tryParse(match.group(2)!);
    if (w == null || h == null) return 0;
    return (w * h).toDouble();
  }

  /// 从 `1152x2048` 或 `1152×2048` 解析宽高比；解析不出返回 null。
  static double? _ratioOf(String value) {
    final match = RegExp(r'(\d+)\s*[x×]\s*(\d+)').firstMatch(value);
    if (match == null) return null;
    final w = int.tryParse(match.group(1)!);
    final h = int.tryParse(match.group(2)!);
    if (w == null || h == null || h == 0) return null;
    return w / h;
  }

  MediaModelCapability copyWith({
    Set<MediaGenMode>? modes,
    List<int>? durations,
    Map<int, List<String>>? durationResolutions,
    List<String>? resolutions,
    List<String>? ratios,
    int? maxReferenceImages,
    bool? supportsFirstFrame,
    bool? supportsLastFrame,
    bool? supportsNativeAudio,
    bool? supportsNegativePrompt,
    bool? isDeclared,
  }) {
    return MediaModelCapability(
      modes: modes ?? this.modes,
      durations: durations ?? this.durations,
      durationResolutions: durationResolutions ?? this.durationResolutions,
      resolutions: resolutions ?? this.resolutions,
      ratios: ratios ?? this.ratios,
      maxReferenceImages: maxReferenceImages ?? this.maxReferenceImages,
      supportsFirstFrame: supportsFirstFrame ?? this.supportsFirstFrame,
      supportsLastFrame: supportsLastFrame ?? this.supportsLastFrame,
      supportsNativeAudio: supportsNativeAudio ?? this.supportsNativeAudio,
      supportsNegativePrompt: supportsNegativePrompt ?? this.supportsNegativePrompt,
      isDeclared: isDeclared ?? this.isDeclared,
    );
  }

  Map<String, dynamic> toJson() => {
    'modes': modes.map((m) => m.id).toList(),
    'durations': durations,
    'duration_resolutions': durationResolutions.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    'resolutions': resolutions,
    'ratios': ratios,
    // null 不写进 json：缺省即 null，避免配置文件里出现大段 "max_reference_images": null
    if (maxReferenceImages != null)
      'max_reference_images': maxReferenceImages,
    'supports_first_frame': supportsFirstFrame,
    'supports_last_frame': supportsLastFrame,
    'supports_native_audio': supportsNativeAudio,
    'supports_negative_prompt': supportsNegativePrompt,
    'is_declared': isDeclared,
  };

  static MediaModelCapability fromJson(Map<String, dynamic> json) {
    Set<MediaGenMode> parseModes() {
      final raw = json['modes'];
      if (raw is! List) return const {};
      return raw
          .map((e) => MediaGenMode.fromId(e as String?))
          .whereType<MediaGenMode>()
          .toSet();
    }

    // 用 whereType 而不是 as List?：手写配置里把 durations 写成字符串是常见
    // 错误，as 会抛 TypeError 让整个 AI 配置页打不开。宽容解析的代价是那条
    // 声明被当成空——比"配置页打不开"好得多。
    List<int> parseInts(String key) => (json[key] is List)
        ? (json[key] as List).whereType<num>().map((n) => n.toInt()).toList()
        : const [];

    List<String> parseStrings(String key) => (json[key] is List)
        ? (json[key] as List).whereType<String>().toList()
        : const [];

    Map<int, List<String>> parseDurationResolutions() {
      final raw = json['duration_resolutions'];
      if (raw is! Map) return const {};
      final result = <int, List<String>>{};
      for (final entry in raw.entries) {
        final key = int.tryParse(entry.key);
        if (key == null) continue;
        final value = entry.value;
        result[key] = value is List ? value.cast<String>() : const [];
      }
      return result;
    }

    return MediaModelCapability(
      modes: parseModes(),
      durations: parseInts('durations'),
      durationResolutions: parseDurationResolutions(),
      resolutions: parseStrings('resolutions'),
      ratios: parseStrings('ratios'),
      // 缺省是 null（没测过）而不是 0（明确不支持）——两者语义相反。
      maxReferenceImages: (json['max_reference_images'] as num?)?.toInt(),
      supportsFirstFrame: json['supports_first_frame'] as bool? ?? false,
      supportsLastFrame: json['supports_last_frame'] as bool? ?? false,
      supportsNativeAudio: json['supports_native_audio'] as bool? ?? false,
      supportsNegativePrompt: json['supports_negative_prompt'] as bool? ?? true,
      // 能从磁盘上读出来就说明它是被声明过的——手写的配置文件不会带这个字段，
      // 但那是用户在明确配置自己的能力，理应算声明。
      isDeclared: json['is_declared'] as bool? ?? true,
    );
  }
}

/// 保守默认能力（spec: Image or Video candidate without declaration）。
///
/// **为什么要"保守"**：默认值取「最不容易被上游拒」的组合——最短时长、最低
/// 分辨率、单参考、无尾帧、无原生音频。代价是未声明模型的画质/时长偏低；
/// 用 `isDeclared: false` 让 UI 明示「默认能力，未经确认」来补偿，引导用户
/// 补充声明。
///
/// 三档的划分依据是各家协议的已知形态，不是猜测：
/// - `openai`：OpenAI 兼容的图像/视频端点通常接受任意 ratio + size，但时长
///   往往有最小步进（4 秒起），且大多数不接受尾帧。
/// - `agnes`：Agnes 专用协议的 `seconds` 接受字符串 "4"~"12"，且官方禁止
///   首尾帧与参考素材同时使用（见 `AgnesVideoAdapter` 的注释）。
/// - 其他（anthropic / gemini / 未知）：不参与媒体生成，给一个尽量空的壳。
abstract final class MediaCapabilityDefaults {
  /// OpenAI 兼容协议的保守默认。
  static const MediaModelCapability openai = MediaModelCapability(
    modes: {
      MediaGenMode.text,
      MediaGenMode.singleImage,
      MediaGenMode.multiReference,
    },
    durations: [4, 5, 6, 8, 10, 12, 15],
    resolutions: ['480p', '720p', '1080p'],
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4'],
    maxReferenceImages: 1,
    supportsFirstFrame: true,
    supportsLastFrame: false,
    supportsNativeAudio: false,
    isDeclared: false,
  );

  /// Agnes 专用协议的保守默认。
  static const MediaModelCapability agnes = MediaModelCapability(
    modes: {
      MediaGenMode.text,
      MediaGenMode.singleImage,
      MediaGenMode.startFrameOptional,
      MediaGenMode.multiReference,
    },
    durations: [4, 5, 6, 8, 10, 12],
    resolutions: ['480p', '720p'],
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4'],
    maxReferenceImages: 8,
    supportsFirstFrame: true,
    supportsLastFrame: false,
    supportsNativeAudio: false,
    isDeclared: false,
  );

  /// 不参与媒体生成的协议（anthropic / gemini / 未知）。
  static const MediaModelCapability none = MediaModelCapability(
    isDeclared: false,
  );

  /// 按协议 id 取默认。用字符串而不是枚举，避免与 `ai_config_store.dart`
  /// 形成循环依赖（那个文件要 import 本文件来声明 `mediaCapabilities` 的值类型）。
  static MediaModelCapability forProtocolId(String protocolId) {
    switch (protocolId) {
      case 'openai':
        return openai;
      case 'agnes':
        return agnes;
      case 'stepfun':
        // StepFun 走 OpenAI 兼容协议，能力按 openai 处理。
        return openai;
      default:
        return none;
    }
  }
}

/// 能力解析器：模型 id → 能力声明。
///
/// 纯函数、无 IO、无单例状态——测试不需要 Keychain 或 HTTP，也因此可以被
/// 任何工具复用（工坊、阅读器、运维工具都可能消费媒体槽位）。
class MediaCapabilityResolver {
  const MediaCapabilityResolver();

  /// 解析 [modelId] 在 [provider] 上的能力。
  ///
  /// 三级查找（spec: 模型能力声明）：
  /// 1. 用户在供应商上写的显式声明——最高优先级，他知道自己接的是什么；
  ///    若用户声明的 maxReferenceImages 小于官方预设，自动自愈升格为预设上限（8 张）；
  /// 2. [MediaCapabilityPresets] 的内置声明——模型 id 是官方 id，跨供应商通用；
  /// 3. 协议级保守默认——`isDeclared: false`，UI 必须标注"未经确认"。
  static MediaModelCapability resolve(
    AiProviderConfigLike provider,
    String modelId,
  ) {
    final declared = provider.mediaCapabilities[modelId];
    final preset = MediaCapabilityPresets.forModel(modelId);
    if (declared != null) {
      if (preset != null) {
        final declaredMax = declared.maxReferenceImages;
        final presetMax = preset.maxReferenceImages;
        if (presetMax != null && (declaredMax == null || declaredMax < presetMax)) {
          return declared.copyWith(
            maxReferenceImages: presetMax,
            modes: {...declared.modes, ...preset.modes},
          );
        }
      }
      return declared;
    }
    if (preset != null) return preset;
    return MediaCapabilityDefaults.forProtocolId(provider.protocolId);
  }
}

/// [MediaCapabilityResolver.resolve] 需要的最小提供者形状。
///
/// 用抽象而不是直接依赖 `AiProviderConfig`：`media_capability.dart` 因此不
/// 被 `ai_config_store.dart` 反向依赖，避免两个服务文件互相 import。
abstract class AiProviderConfigLike {
  /// 协议类型 id（`AiProtocolType.name`）。
  String get protocolId;
  Map<String, MediaModelCapability> get mediaCapabilities;
}


/// 内置模型的已知能力（spec: 模型能力声明 · 显式声明）。
///
/// **这些数字从哪来**——这是全文件最重要的注释：
/// - SenseAudio 视频：`video_gen_adapter.dart` 的 `SenseAudioVideoAdapter`
///   写死了 `duration.clamp(4, 15)`、`ratio: '9:16'`、`resolution: '720p'`，
///   且 payload 的 `content` 数组原生支持多张 image（首张 `first_frame`、
///   其余 `reference`）。因此它是四个适配器里唯一能声明多参考的。
/// - SenseAudio 图像：`image_gen_adapter.dart` 的
///   `SenseAudioImageAdapter.supportedDimensions` 就是现成的白名单，直接搬。
/// - Agnes 视频：`AgnesVideoAdapter` 写死 `seconds.clamp(4, 12)`、
///   `aspect_ratio: '9:16'`，且官方文档明确「keyframe 模式下禁止首尾帧与
///   参考素材同时使用」——所以 `maxReferenceImages` 只能是 1。
/// - Dola 视频：免费号池只接受 5 / 10 / 15 秒三档，且请求体只有
///   `text_block`（见 `DolaPoolVideoAdapter`），没有任何图片输入通道——所以
///   `supportsFirstFrame` 为 false、`maxReferenceImages` 为 0。
///
/// 声明成常量而不是从适配器反推：适配器的 clamp 是**兜底**，能力矩阵是**意图**。
/// 两者刻意分开，才能让"适配器偷偷 clamp"这件事在测试里被发现。
abstract final class MediaCapabilityPresets {
  /// SenseAudio / 豆包 Seedance 2.0 视频。
  static const MediaModelCapability seedance2Video =
      MediaModelCapability(
    modes: {
      MediaGenMode.text,
      MediaGenMode.singleImage,
      MediaGenMode.startFrameOptional,
      MediaGenMode.multiReference,
    },
    durations: [4, 5, 6, 8, 10, 12, 15],
    durationResolutions: {
      4: ['480p', '720p', '1080p'],
      8: ['480p', '720p', '1080p'],
      12: ['480p', '720p', '1080p'],
      15: ['480p', '720p'],
    },
    resolutions: ['480p', '720p', '1080p'],
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4'],
    maxReferenceImages: 9,
    supportsFirstFrame: true,
    supportsLastFrame: false,
    supportsNativeAudio: true,
    isDeclared: true,
  );

  /// SenseAudio 图像（官方原生双模，尺寸白名单见 `supportedDimensions`）。
  static const MediaModelCapability senseAudioImage =
      MediaModelCapability(
    modes: {
      MediaGenMode.text,
      MediaGenMode.singleImage,
      MediaGenMode.multiReference,
    },
    resolutions: [
      '1024x1024', '1024x1280', '1280x1024',
      '1536x864', '864x1536',
      '1024x1536', '1536x1024',
      '2016x864', '864x2016',
      '2048x1024', '1024x2048',
      '2048x1152', '1152x2048',
      '2048x1360', '1360x2048',
      '2688x1152', '1536x2048', '2048x1536',
      '2688x1344', '1344x2688', '3136x1344',
    ],
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4'],
    maxReferenceImages: 1,
    supportsFirstFrame: false,
    supportsLastFrame: false,
    supportsNativeAudio: false,
    isDeclared: true,
  );

  /// Agnes Video 2.5（标准型号）。
  ///
  /// 四档分辨率来自官方文档的 size 枚举：`"720P"` / `"1080P"` / `"1K"` / `"2K"`。
  /// 时长是字符串 `"4"`–`"12"`，离散档位见 [durations]。
  ///
  /// `maxReferenceImages: 8` 是 reference 模式的上限（文档：图片最多 8 张、
  /// 单次请求媒体总数不超过 12）。适配器已能提交 `images[]`（data URI），
  /// 所以这个上限现在既描述模型也描述我们的实现。
  ///
  /// 计费按输出秒数 × 分辨率单价，**任务创建即计费**；输入图片前 5 张免费。
  ///
  /// **输出像素映射**（文档实测表，规格字段里没有"输出尺寸"这一维，故记在此）：
  /// 同比例下标准型号与 Flash 的输出不同——16:9 这里输出 1280×720，
  /// Flash 输出 1280×704。2K = 对应 720P 宽高的 2 倍；1K 固定 1024×1024。
  /// 9:16 → 720×1280 / 1080×1920 / 1440×2560。
  static const MediaModelCapability agnesVideo25 = MediaModelCapability(
    modes: {
      MediaGenMode.text,
      MediaGenMode.singleImage,
      MediaGenMode.startFrameOptional,
      MediaGenMode.multiReference,
    },
    durations: [4, 5, 6, 8, 10, 12],
    resolutions: ['720p', '1080p', '1k', '2k'],
    // 六种比例，与文档的 aspect_ratio 白名单一致。以前这里只列五种，
    // 缺 21:9——适配器又把 aspect_ratio 写死成 9:16，两边一起把超宽屏挡在
    // 可用范围之外。
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4', '21:9'],
    maxReferenceImages: 8,
    supportsFirstFrame: true,
    supportsLastFrame: true,
    // 描述**输出**是否带原生音轨，不是输入侧是否接受音频参考。Agnes 的
    // audios[] 是 reference 模式的输入参考，与这个字段无关。
    supportsNativeAudio: false,
    isDeclared: true,
  );

  /// Agnes Video 2.5 Flash。
  ///
  /// 与标准型号的差异全是文档明文的硬校验（返回 HTTP 400，且**在校验失败时
  /// 不创建任务、不计费**）：
  /// - `size` 必须为 `"720P"`，传其他值直接 400 → [resolutions] 收窄为一档；
  /// - 不支持参考视频 → 不声明视频参考模式；
  /// - reference 图片最多 5 张（标准型号是 8 张）→ [maxReferenceImages] 分档。
  ///
  /// 首尾帧能力与标准型号一致（文档：除上述限制外其余参数能力一致）。
  ///
  /// **输出像素映射**（2026 年 9 月实测，文档明言 16:9 的尺寸以实际文件为准）：
  /// 21:9 → 1680×720、16:9 → 1280×704、4:3 → 960×720、1:1 → 720×720、
  /// 3:4 → 720×960、9:16 → 720×1280。注意 16:9 与标准型号不同。
  static const MediaModelCapability agnesVideo25Flash = MediaModelCapability(
    modes: {
      MediaGenMode.text,
      MediaGenMode.singleImage,
      MediaGenMode.startFrameOptional,
      // 不声明 multiReference：适配器虽已能发 images[]，但 Flash 的 5 张上限
      // 与标准型号的 8 张不同，声明同一模式会让「支持几种模式」这件事在两个
      // 型号间失真。5 张的上限由 maxReferenceImages 表达。
      MediaGenMode.multiReference,
    },
    durations: [4, 5, 6, 8, 10, 12],
    resolutions: ['720p'],
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4', '21:9'],
    maxReferenceImages: 5,
    supportsFirstFrame: true,
    supportsLastFrame: true,
    supportsNativeAudio: false,
    isDeclared: true,
  );

  /// Agnes 图像模型（2.0 / 2.1 / 2.5 Flash）。
  ///
  /// 三档的参数能力一致——文档明言 2.5 Flash「请求与响应参数、支持尺寸、价格
  /// 和计费方法均与 2.1 Flash 保持一致」，2.0 同族。仍按型号给三条声明：
  /// 用户配置里出现的是具体型号 id，`forModel` 要能逐个别名命中。
  ///
  /// 尺寸是档位式（`"1K"`/`"2K"`/`"3K"`/`"4K"`）配 ratio，不是精确像素。
  /// 文档同时兼容 `1024x768` 这类历史精确写法，但「不支持的尺寸可能被标准化」，
  /// 所以这里只声明档位——让规整层按档位吸附，而不是猜一个可能被改写的像素值。
  /// 9:16 下 2K = 1472x2624（文档输出尺寸表）。
  static const MediaModelCapability agnesImage = MediaModelCapability(
    modes: {MediaGenMode.text, MediaGenMode.multiReference},
    // 图像模型没有时长维度：空集合让 supportsDuration() 恒真（不限制），
    // 规整层因此不会对图像请求做时长吸附。
    durations: <int>[],
    resolutions: ['1k', '2k', '3k', '4k'],
    ratios: ['1:1', '3:4', '4:3', '16:9', '9:16', '2:3', '3:2', '21:9'],
    maxReferenceImages: 8,
    supportsFirstFrame: false,
    supportsLastFrame: false,
    supportsNativeAudio: false,
    supportsNegativePrompt: false,
    isDeclared: true,
  );

  /// Dola 免费号池视频（seedance 2.0 / 2.5）。
  ///
  /// 三档时长是免费版硬限制，不是推测值。`maxReferenceImages: 0` 与
  /// `supportsFirstFrame: false` 来自请求体形态：`DolaPoolVideoAdapter` 的
  /// payload 只有 `text_block`，没有任何图片输入通道。
  ///
  /// 声明 0 而不是 1 是刻意的：声明 1 会让调用方以为"传一张也行"，然后把
  /// 首帧塞进一个没有图片字段的请求。0 让「不被支持的能力必须显式拒绝」
  /// 能真正生效——依赖参考图的片段级生成在 Dola 路径下被明确拒绝，用户看到
  /// 原因并去切引擎，而不是静默丢图后拿到一个不一致的片段。
  ///
  /// **30 秒档位暂不声明**：上游 `seedance-2.5` 支持 5/10/30，但 30 秒走两段
  /// 15 秒 + FFmpeg 拼接，适配器尚未实现。声明一个必然抛错的值比不声明更让
  /// 用户困惑——他会按 30 秒规划分镜，提交时才知道不行。30 秒与拼接实现属于
  /// 同一批工作，留给后续 change。
  static const MediaModelCapability dolaVideo25 = MediaModelCapability(
    modes: {MediaGenMode.text, MediaGenMode.singleImage, MediaGenMode.multiReference},
    durations: [5, 10],
    resolutions: ['480p', '720p'],
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4'],
    // null = 没测过上限。上游文档说 10 张，但我们没实测，也不做上线控制。
    maxReferenceImages: null,
    supportsFirstFrame: true,
    supportsLastFrame: false,
    supportsNativeAudio: false,
    isDeclared: true,
  );

  /// `seedance-2.0`：时长 5/10/15（上游明确的三档，15 秒我们就能出）。
  static const MediaModelCapability dolaVideo20 = MediaModelCapability(
    modes: {MediaGenMode.text, MediaGenMode.singleImage, MediaGenMode.multiReference},
    durations: [5, 10, 15],
    resolutions: ['480p', '720p'],
    ratios: ['9:16', '16:9', '1:1', '4:3', '3:4'],
    maxReferenceImages: null,
    supportsFirstFrame: true,
    supportsLastFrame: false,
    supportsNativeAudio: false,
    isDeclared: true,
  );

  static MediaModelCapability? forModel(String modelId) {
    // 前缀归一到具体型号。必须放在 switch 之前——它的 default 会吞掉未枚举
    // 的值。Dola 的模型 id 由适配器拼出（'dola-pool-$_model'）。
    //
    // 按型号而不是「dola-pool- 前缀一把命中」：两个型号的合法时长不同
    // （2.5 → 5/10，2.0 → 5/10/15），合并会让其中一个拿到错误的集合。
    // 未知的 dola-pool-* 型号返回 null，让调用方落到协议默认并显示
    // 「未经确认」——比误命中一个错误的声明诚实。
    if (modelId.contains('seedance-2.5')) return dolaVideo25;
    if (modelId.contains('seedance-2.0')) return dolaVideo20;
    switch (modelId) {
      case 'doubao-seedance-2-0-260128':
      case 'doubao-seedance-1-5-pro':
        return seedance2Video;
      case 'senseaudio-image-2.0-260319':
      case 'doubao-seedream-5-0-260128':
      case 'sensenova-u1-fast':
        return senseAudioImage;
      // Agnes 视频：两个型号的限制不同（Flash 固定 720P、参考图 5 张），
      // 必须分开命中，不能「agnes- 前缀一把梭」。
      case 'agnes-video-2.5-flash':
        return agnesVideo25Flash;
      case 'agnes-video-2.5':
        return agnesVideo25;
      // Agnes 图像：三档同族参数，但用户配置里写的是具体型号 id，逐个别名命中。
      // 曾经 agnes-image-2.5-flash 被映到视频声明上——图像模型因此拿到了
      // 视频的时长与模式约束。现在按型号分流。
      case 'agnes-image-2.0-flash':
      case 'agnes-image-2.1-flash':
      case 'agnes-image-2.5-flash':
        return agnesImage;
      default:
        return null;
    }
  }
}

/// 一次规整的结果：规整后的请求 + 人类可读的变更列表。
///
/// [changes] 是给用户和日志看的——「请求 15s 吸附为 12s」这类信息必须可见，
/// 否则用户以为参数生效了，排查时完全无法归因。
class NormalizationResult<T> {
  const NormalizationResult({required this.request, required this.changes});

  final T request;

  /// 形如 `时长 15s → 12s（模型上限）` 的说明列表。
  final List<String> changes;

  bool get hasChanges => changes.isNotEmpty;
}

/// 请求规整的输入形状（spec: 请求参数规整）。
///
/// 用普通类而不是 `VideoGenRequest`：规整层不该依赖工坊的适配器文件，
/// 否则 `media_capability.dart` 会被 `ai_video_studio` 反向拖入依赖图。
class MediaRequestSpec {
  final double durationSec;

  /// 请求的分辨率（如 `1080p` / `1152x2048`）。空串表示不指定。
  final String resolution;

  /// 请求的画幅比例（如 `9:16`）。空串表示不指定。
  final String ratio;

  /// 参考图数量（含首帧）。
  final int referenceImageCount;

  /// 是否指定了首帧。
  final bool hasFirstFrame;

  /// 是否指定了尾帧。
  final bool hasLastFrame;

  /// 请求的生成模式。null 表示未指定（放行）。
  final MediaGenMode? mode;

  const MediaRequestSpec({
    this.durationSec = 0,
    this.resolution = '',
    this.ratio = '',
    this.referenceImageCount = 0,
    this.hasFirstFrame = false,
    this.hasLastFrame = false,
    this.mode,
  });
}

/// 请求规整器（spec: 请求参数规整）。
///
/// **吸附与拒绝是两件事**（design 决策 3）：
/// - 参数超范围（时长/分辨率/比例/参考数量）→ 吸附 + 记录变更
/// - 能力维度不支持（无参考能力却带参考图、不支持首帧却指定首帧、模式不在
///   集合内）→ 抛 [MediaCapabilityException]，不降级提交
///
/// 后者如果也降级，用户会在毫不知情的情况下得到一个完全不同的产物——例如把
/// 带角色参考的关键帧静默改成纯文生图，角色一致性直接丢失且无从察觉。
class MediaRequestNormalizer {
  const MediaRequestNormalizer(this.capability);

  final MediaModelCapability capability;

  /// 规整一份请求。能力维度不支持时抛 [MediaCapabilityException]。
  NormalizationResult<MediaRequestSpec> normalize(MediaRequestSpec spec) {
    final changes = <String>[];

    // --- 拒绝类检查（不做任何降级）---
    //
    // null 表示没测过上限，跳过数量校验——用 `0` 表达「没测过」会让 UI 说
    // "不支持参考图"，用户于是根本不用这个引擎做片段级生成。
    final maxRefs = capability.maxReferenceImages;
    if (maxRefs != null && spec.referenceImageCount > maxRefs) {
      throw MediaCapabilityException(
        '当前模型最多支持 $maxRefs 张参考图，'
        '本次请求携带 ${spec.referenceImageCount} 张。'
        '请减少参考图，或改用支持多参考的模型。',
      );
    }
    if (spec.hasFirstFrame && !capability.supportsFirstFrame) {
      throw MediaCapabilityException('当前模型不支持指定首帧。');
    }
    if (spec.hasLastFrame && !capability.supportsLastFrame) {
      throw MediaCapabilityException('当前模型不支持指定尾帧。');
    }
    final mode = spec.mode;
    if (mode != null &&
        capability.modes.isNotEmpty &&
        !capability.modes.contains(mode)) {
      throw MediaCapabilityException(
        '当前模型不支持 ${mode.id} 生成模式。',
      );
    }

    // --- 吸附类（记录变更但不拒）---
    var duration = spec.durationSec;
    if (spec.durationSec > 0 && capability.durations.isNotEmpty) {
      final snapped = capability.snapDuration(spec.durationSec.round());
      if (snapped != spec.durationSec.round()) {
        changes.add('时长 ${spec.durationSec.round()}s → ${snapped}s');
        duration = snapped.toDouble();
      }
    }

    var resolution = spec.resolution;
    if (spec.resolution.isNotEmpty) {
      final legal = capability.resolutionsFor(spec.durationSec.round());
      if (legal.isNotEmpty) {
        final snapped = capability.snapResolution(spec.resolution, legal);
        if (snapped != spec.resolution) {
          changes.add('分辨率 $spec.resolution → $snapped');
          resolution = snapped;
        }
      }
    }

    var ratio = spec.ratio;
    if (spec.ratio.isNotEmpty &&
        capability.ratios.isNotEmpty &&
        !capability.ratios.contains(spec.ratio)) {
      changes.add('画幅 ${spec.ratio} 不在模型支持列表内');
      ratio = spec.ratio; // 保留原值：比例不被支持时由适配器决定是否拒绝
    }

    return NormalizationResult(
      request: MediaRequestSpec(
        durationSec: duration,
        resolution: resolution,
        ratio: ratio,
        referenceImageCount: spec.referenceImageCount,
        hasFirstFrame: spec.hasFirstFrame,
        hasLastFrame: spec.hasLastFrame,
        mode: spec.mode,
      ),
      changes: changes,
    );
  }
}

/// 能力矩阵抛出的可读错误。UI 直接展示 [message]。
class MediaCapabilityException implements Exception {
  const MediaCapabilityException(this.message);

  final String message;

  @override
  String toString() => 'MediaCapabilityException: $message';
}
