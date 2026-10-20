/// 视频生成 Engine Adapter 层（design.md D3）。
///
/// 三种制作类型对应三种默认策略（spec: 差异化动态化策略）：
/// - `drama` → 云端图生视频（[KlingVideoAdapter]，需 API Key）
/// - `anime` / `narration` → 本地 FFmpeg Ken Burns 动效（[KenBurnsVideoAdapter]，
///   零成本、零网络，10 秒内出片）
///
/// 上层只依赖 [VideoGenAdapter]，所以新增 Runway / MiniMax 只需加一个实现类
/// 与工厂的一行分支。
library;

import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../../services/ai_config_store.dart';
import '../../../services/ai_logger.dart';
import '../../../services/app_http_client.dart';
import '../../../services/keychain_service.dart';
import '../../../services/media_capability.dart';
import '../../../services/settings_store.dart';
import '../../dola_pool/services/dola_config_store.dart';
import '../../dola_pool/services/dola_pool_video_adapter.dart';
import 'ffmpeg_composer.dart';
import 'image_gen_adapter.dart' show ImageHttpFn;
import 'video_task_ledger.dart';

/// Agnes 视频生成模式。
enum AgnesVideoMode {
  auto('auto'),
  text('text'),
  keyframe('keyframe'),
  reference('reference');

  const AgnesVideoMode(this.id);
  final String id;

  static AgnesVideoMode fromId(String id) {
    return AgnesVideoMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => AgnesVideoMode.auto,
    );
  }
}

/// 一次视频生成请求。
///
/// 分镜级与片段级生成共用这一个形状（design 决策 3）：
/// - 分镜级：`inputImage` 为该镜关键帧，`referenceImages` 为空，`promptZh` 为空
/// - 片段级：`inputImage` 为 null，`referenceImages` 为该片段全部出场角色与
///   场景的参考图，`promptZh` 为 `PromptAssembler.buildSegmentPrompt` 的产物
///
/// `inputImage` 从必建改为可选是**有意的兼容破坏**：本地 Ken Burns 动效必须
/// 有首帧，拿不到时它抛明确错误，而不是静默产出黑帧。
class VideoGenRequest {
  /// 首帧图片（已生成的关键帧）。本地 Ken Burns 必需；I2V 也用它。
  final File? inputImage;

  /// 尾帧图片（已生成的关键帧）。可选。
  final File? lastFrameImage;

  /// 多参考图（片段级生成用）。按序对应提示词里的 `{{ref N}}`。
  final List<File> referenceImages;

  /// 完整画面描述（片段级生成用）。为空时适配器回退到 [cameraMove]。
  final String promptZh;

  /// 运镜指令（英文短语，如 "slow push-in"）。I2V 引擎会读它。
  final String cameraMove;

  /// 期望时长（秒）。
  final double durationSec;

  /// 分镜编号（进度展示与定位）。片段级传该片段的首镜号。
  final int shotNumber;

  /// 输出目标文件（.mp4）。
  final File outputFile;

  /// 制作类型 id，用于选默认策略。
  final String productionType;

  /// 生成模式（auto / text / keyframe / reference）。
  final AgnesVideoMode mode;

  /// 分辨率档位（'' 表示不指定，沿用适配器默认值，如 '720P'）。
  final String sizeTier;

  /// 画幅比例（'' 表示不指定，沿用适配器默认值，如 '9:16'）。
  final String ratio;

  /// 随机种子（可选）。
  final int? seed;

  /// 台账关联上下文。全部为可选：不传时台账条目只有目标路径可依。
  ///
  /// 恢复路径靠这几个字段把云端任务对回本地的片段/分镜——缺了它们，重启后
  /// 即使取回视频也不知道该写进哪个剧集的哪个片段。
  final String? seriesId;
  final String? episodeId;
  final String? segmentId;

  /// 台账里的人类可读任务名（如「片段 3 视频」）。
  final String? label;

  const VideoGenRequest({
    required this.inputImage,
    this.lastFrameImage,
    this.referenceImages = const [],
    this.promptZh = '',
    this.cameraMove = '',
    required this.durationSec,
    required this.shotNumber,
    required this.outputFile,
    this.productionType = 'drama',
    this.mode = AgnesVideoMode.auto,
    this.sizeTier = '',
    this.ratio = '',
    this.seed,
    this.seriesId,
    this.episodeId,
    this.segmentId,
    this.label,
  });

  /// 适配器实际使用的提示词：片段提示词优先，否则退回运镜短语。
  ///
  /// 放在请求对象上而不是各适配器里判断，是为了让「哪段文字被提交给了模型」
  /// 在一处可见——排查「为什么生成的画面和分镜写的不一样」时不用翻四个适配器。
  String get effectivePrompt {
    final zh = promptZh.trim();
    if (zh.isNotEmpty) return zh;
    return cameraMove.trim();
  }

  /// 本次请求的全部参考图（含首帧与尾帧）。适配器按协议自行决定怎么用。
  List<File> get allImages {
    final result = <File>[];
    final first = inputImage;
    if (first != null) result.add(first);
    final last = lastFrameImage;
    if (last != null && !result.any((e) => e.path == last.path)) {
      result.add(last);
    }
    for (final f in referenceImages) {
      if (!result.any((e) => e.path == f.path)) result.add(f);
    }
    return result;
  }
}

/// 视频生成引擎抽象接口。
abstract interface class VideoGenAdapter {
  String get id;
  String get label;

  /// 是否需要 API Key（免费引擎为 false，UI 据此决定是否提示去设置）。
  bool get requiresApiKey;

  Future<bool> isAvailable();

  /// 生成片段。失败抛异常，由任务队列标记失败。
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  });
}

/// 可取消能力：云端 I2V 轮询期间用户可以在队列里取消单任务。
abstract interface class CancellableVideoGenAdapter {
  /// 请求取消正在进行的任务。已发出的 HTTP 不会被撤回，但不再继续轮询。
  void cancelCurrent();
}

/// 本地 FFmpeg Ken Burns 动效适配器。
///
/// 用 `zoompan` 滤镜把静图做成缓慢推拉/平移。实现上避开两个坑：
/// 1. **单张图必须先在输入侧循环**（`-loop 1 -t <秒>`），否则 zoompan 只拿到
///    一帧，出来的片段长度随缘。实测 `loop` 滤镜与 zoompan 串联会因参数解析
///    顺序报 "No option name"，所以循环放在输入侧、zoompan 只负责运动。
/// 2. **帧率必须显式给出**（`fps=30`）。zoompan 的 `d`（每输入帧重复多少输出
///    帧）与输出 fps 共同决定片段时长；只给一个会得到不等于预期的长度。
class KenBurnsVideoAdapter implements VideoGenAdapter {
  KenBurnsVideoAdapter();

  /// 缓存一次可用性探测结果：FFmpeg 在进程生命周期内不会凭白出现或消失，
  /// 而每次 `ffmpeg -version` 都是 100ms 级别的进程启动开销。
  bool? _cachedAvailable;

  @override
  String get id => 'local-kenburns-ffmpeg';

  @override
  String get label => '本地 Ken Burns 动效（FFmpeg，免费）';

  @override
  bool get requiresApiKey => false;

  @override
  Future<bool> isAvailable() async {
    if (_cachedAvailable != null) return _cachedAvailable!;
    final status = await FfmpegComposer.checkAvailability();
    _cachedAvailable = status.available;
    return _cachedAvailable!;
  }

  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (!await isAvailable()) {
      throw StateError(
        '本机未检测到 FFmpeg，无法生成 Ken Burns 动效。请先安装 FFmpeg。',
      );
    }
    // 本地动效的输入只能是单张图。片段级请求不带首帧（它的输入是参考图
    // 集合），拿不到就明确报错，而不是拿第一张参考图凑——那会让「片段视频」
    // 悄悄变成「第一张参考图的运镜视频」，用户看不出差别。
    final input = request.inputImage;
    if (input == null) {
      throw StateError(
        '本地 Ken Burns 动效需要一张首帧图片；片段级请求请先为其中的分镜'
        '生成关键帧，或改用支持多参考图的云端视频模型。',
      );
    }
    await request.outputFile.parent.create(recursive: true);

    final fps = 30;
    final mode = _pickMode(request);

    // 推拉与平移两套滤镜。推拉步长按总帧数归一化：3 秒片段推进 0.34 倍
    // （90 帧 × 0.0038），时长变化时观感速度一致。
    //
    // 这里刻意**不**先 scale 到 2 倍再裁：zoompan 每帧都要在放大的画布上裁切，
    // 2160×3840 的中间画布会让 3 秒片段的编码时间从 3 秒涨到 9 秒，而
    // spec 要求 narration/anime 的本地动效 10 秒内出片。1080×1920 直接
    // zoompan 的画质损失在短视频场景看不出来，速度换来的是可用性。
    final totalFrames = (request.durationSec * fps).round().clamp(30, 900);
    final zoomStep = 0.34 / totalFrames;
    // 除以总帧数，而不是 `fps*duration`：FFmpeg 表达式里没有括号优先级，
    // `on/30*2` 会被解析成 `(on/30)*2`——平移量在开头就冲到 2 倍，画面瞬间
    // 划出边界外，整段平移看起来跟没动一样。
    final frameSpan = totalFrames;
    final String filter;
    switch (mode) {
      case _KenBurnsMode.pushIn:
        filter =
            'fps=$fps,'
            "zoompan=z='min(zoom+$zoomStep,1.5)':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            'd=1:s=1080x1920:fps=$fps';
        break;
      case _KenBurnsMode.pullOut:
        // zoompan 的 zoom 表达式可以递减，但降到 1 以下会露出边缘，所以用
        // max 兜底：起点 1.5，逐步回到 1.0。
        filter =
            'fps=$fps,'
            "zoompan=z='if(eq(on,0),1.5,max(1.0,zoom-$zoomStep))':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            'd=1:s=1080x1920:fps=$fps';
        break;
      case _KenBurnsMode.panRight:
        filter =
            'fps=$fps,'
            "zoompan=z=1.06:x='(iw-iw/zoom)*on/$frameSpan':"
            "y='ih/2-(ih/zoom/2)':"
            'd=1:s=1080x1920:fps=$fps';
        break;
      case _KenBurnsMode.panLeft:
        filter =
            'fps=$fps,'
            "zoompan=z=1.06:x='(iw-iw/zoom)*(1-on/$frameSpan)':"
            "y='ih/2-(ih/zoom/2)':"
            'd=1:s=1080x1920:fps=$fps';
        break;
    }

    await FfmpegComposer.runRaw(
      args: [
        '-y',
        // 输入侧循环单张图 + 用 -frames:v 精确控制帧数。用 -t 控制时长时
        // zoompan 的 d=1 会让时长取决于输入帧率，实测同样参数会得到 2.5 秒
        // 而不是 3 秒。
        '-loop', '1',
        '-i', input.path,
        '-vf', filter,
        '-frames:v', '$totalFrames',
        '-r', '$fps',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'ultrafast',
        '-tune', 'stillimage',
        '-crf', '23',
        '-movflags', '+faststart',
        request.outputFile.path,
      ],
      onStderrLine: (line) {
        final progress = FfmpegComposer.parseProgress(
          line: line,
          durationSec: request.durationSec,
        );
        if (progress != null) onProgress?.call(progress);
      },
    );

    if (!await request.outputFile.exists()) {
      throw StateError('FFmpeg 未生成输出文件：${request.outputFile.path}');
    }
    final size = await request.outputFile.length();
    if (size < 1024) {
      throw StateError('FFmpeg 输出文件异常（仅 $size 字节）');
    }
    onProgress?.call(1);
    return request.outputFile;
  }

  /// 按运镜词选动效；识别不出就按镜号轮换，避免全集都是一种镜头运动。
  _KenBurnsMode _pickMode(VideoGenRequest request) {
    final move = request.cameraMove.toLowerCase();
    if (move.contains('pan right') || move.contains('truck right')) {
      return _KenBurnsMode.panRight;
    }
    if (move.contains('pan left') || move.contains('truck left')) {
      return _KenBurnsMode.panLeft;
    }
    if (move.contains('pull out') || move.contains('zoom out')) {
      return _KenBurnsMode.pullOut;
    }
    return request.shotNumber.isEven
        ? _KenBurnsMode.pushIn
        : _KenBurnsMode.panRight;
  }

  /// 测试用：清除缓存，模拟 FFmpeg 刚装上/被卸载。
  void resetAvailabilityForTesting() => _cachedAvailable = null;
}

enum _KenBurnsMode { pushIn, pullOut, panRight, panLeft }

/// 可灵（Kling）图生视频适配器。
///
/// 异步任务模型：创建任务 → 轮询状态 → 下载结果。云端一段 5 秒视频通常
/// 30-120 秒，所以全程可取消、可超时（默认 5 分钟，spec 同）。
class KlingVideoAdapter
    implements VideoGenAdapter, CancellableVideoGenAdapter {
  KlingVideoAdapter({http.Client? client, ImageHttpFn? httpFn})
    : _httpFn = httpFn,
      _client = client;

  final http.Client? _client;
  final ImageHttpFn? _httpFn;

  static const String createEndpoint =
      'https://api.klingai.com/v1/videos/image2video';
  static const String queryEndpoint =
      'https://api.klingai.com/v1/videos/image2video';

  /// Keychain 键名（读写两侧共用同一常量）。
  static const String keychainKeyId = 'studio_video_kling_key';

  bool _cancelled = false;

  @override
  String get id => 'kling-i2v';

  @override
  String get label => '可灵 Kling 图生视频';

  @override
  bool get requiresApiKey => true;

  @override
  Future<bool> isAvailable() async =>
      (await readApiKey())?.isNotEmpty ?? false;

  Future<String?> readApiKey() async {
    final key = await KeychainService.instance.readSecret(keychainKeyId);
    if (key == null || key.trim().isEmpty) return null;
    return key.trim();
  }

  Future<void> saveApiKey(String key) => KeychainService.instance
      .writeSecret(keychainKeyId, key.trim());

  Future<void> clearApiKey() =>
      KeychainService.instance.deleteSecret(keychainKeyId);

  @override
  void cancelCurrent() => _cancelled = true;

  // Agnes 不用固定轮询超时——预算拆成排队 + 生成两段，见 _pollUntilDone。

  /// 可灵的固定轮询超时。Agnes 用两段预算，不用它（见 [_pollUntilDone]）。
  Duration get _pollTimeout => const Duration(minutes: 5);

  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('可灵 API Key 未配置');
    }
    _cancelled = false;

    // 首帧以 base64 data URI 提交：可灵的 image 字段接受 data URI，
    // 免去先传素材库再引用这一步。片段级请求不带首帧时取参考图第一张。
    final firstFrame = request.inputImage ??
        (request.referenceImages.isNotEmpty
            ? request.referenceImages.first
            : null);
    if (firstFrame == null) {
      throw StateError('可灵图生视频需要一张首帧或参考图');
    }
    final imageBytes = await firstFrame.readAsBytes();
    final dataUri =
        'data:image/png;base64,${base64Encode(imageBytes)}';

    final createResponse = await _post(
      Uri.parse(createEndpoint),
      key: key,
      body: {
        'model_name': 'kling-v1',
        'image': dataUri,
        'prompt': request.effectivePrompt.isEmpty
            ? 'gentle cinematic camera motion'
            : request.effectivePrompt,
        'duration': '5',
        'mode': 'std',
        'cfg_scale': 0.5,
      },
    );
    final taskId = _readTaskId(createResponse);
    if (taskId == null) {
      throw StateError(
        '可灵创建任务失败：${_truncate(_errorOf(createResponse), 200)}',
      );
    }

    final deadline = DateTime.now().add(_pollTimeout);
    var videoUrl = '';
    var lastStatus = '';
    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) {
        throw StateError('任务已被用户取消');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      final body = await _get(
        Uri.parse('$queryEndpoint/$taskId'),
        key: key,
      );
      final status = _readStatus(body);
      lastStatus = status;
      switch (status) {
        case 'succeeded':
          videoUrl = _readVideoUrl(body);
          if (videoUrl.isEmpty) {
            throw StateError('可灵任务成功但未返回视频地址');
          }
          break;
        case 'failed':
          throw StateError(
            '可灵生成失败：${_truncate(_errorOf(body), 200)}',
          );
        default:
          // processing / submitted：继续轮询。进度只能给出"还在跑"的量级，
          // 不假装知道百分比——编一个假进度比不显示进度更糟。
          onProgress?.call(0.5);
      }
      if (videoUrl.isNotEmpty) break;
    }

    if (videoUrl.isEmpty) {
      throw StateError(
        '可灵任务在 ${_pollTimeout.inMinutes} 分钟内未完成（最后状态：$lastStatus）',
      );
    }

    final client = _client ?? AppHttpClient.create();
    final download = await client.get(Uri.parse(videoUrl));
    if (download.statusCode != 200) {
      throw StateError('下载可灵视频失败 (HTTP ${download.statusCode})');
    }
    await request.outputFile.parent.create(recursive: true);
    await request.outputFile.writeAsBytes(download.bodyBytes, flush: true);
    onProgress?.call(1);
    return request.outputFile;
  }

  // ---------------------------------------------------------------------------
  // HTTP 细节
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _post(
    Uri uri, {
    required String key,
    required Map<String, dynamic> body,
  }) async {
    final req = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $key'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final response = _httpFn != null
        ? await _httpFn(req)
        : await (_client ?? AppHttpClient.create())
              .send(req)
              .then(http.Response.fromStream);
    return _decodeBody(response);
  }

  Future<Map<String, dynamic>> _get(Uri uri, {required String key}) async {
    final req = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $key';
    final response = _httpFn != null
        ? await _httpFn(req)
        : await (_client ?? AppHttpClient.create())
              .send(req)
              .then(http.Response.fromStream);
    return _decodeBody(response);
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '可灵 API 返回 HTTP ${response.statusCode}：'
        '${_truncate(_extractError(response.body), 200)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('可灵返回体不是 JSON 对象');
    }
    return decoded.map((k, v) => MapEntry(k as String, v));
  }

  static String? _readTaskId(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      final id = data['task_id'] ?? data['taskId'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  static String _readStatus(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      final status = data['task_status'] ?? data['taskStatus'];
      if (status is String) return status;
    }
    return '';
  }

  static String _readVideoUrl(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! Map) return '';
    final result = data['task_result'];
    if (result is! Map) return '';
    final videos = result['videos'];
    if (videos is! List || videos.isEmpty) return '';
    final first = videos.first;
    if (first is Map) {
      final url = first['url'];
      if (url is String) return url;
    }
    return '';
  }

  static String _errorOf(Map<String, dynamic> body) {
    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;
    return body.toString();
  }

  static String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return (decoded['message'] ?? decoded['error'] ?? body).toString();
      }
    } catch (_) {}
    return body;
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}

/// SenseAudio 视频生成适配器（集成豆包 Seedance 2.0 等官方视频大模型）。
///
/// 异步任务模型：
/// 1. 读取本地关键帧图片，转为 base64 Data URL (`data:image/png;base64,...`)；
/// 2. POST `/v1/video/create` 提交生成任务，包含 model、duration、resolution、ratio 与 content（首帧+运镜提示词）；
/// 3. GET `/v1/video/status?id=<task_id>` 轮询任务状态（支持 pending/processing/completed/failed）；
/// 4. 成功后流式下载 mp4 视频并持久化写入 request.outputFile。
class SenseAudioVideoAdapter
    implements VideoGenAdapter, CancellableVideoGenAdapter {
  SenseAudioVideoAdapter({
    String? baseUrl,
    String? model,
    String? apiKey,
    String? providerId,
    String? keychainKeyId,
    http.Client? client,
    ImageHttpFn? httpFn,
  })  : _rawBaseUrl = baseUrl,
        _model = model ?? 'doubao-seedance-2-0-260128',
        _apiKey = apiKey,
        _providerId = providerId,
        _keychainKeyId = keychainKeyId,
        _client = client,
        _httpFn = httpFn;

  final String? _rawBaseUrl;
  final String _model;
  final String? _apiKey;
  final String? _providerId;
  final String? _keychainKeyId;
  final http.Client? _client;
  final ImageHttpFn? _httpFn;

  bool _cancelled = false;

  @override
  String get id =>
      _providerId != null ? 'senseaudio-$_providerId' : 'senseaudio-video';

  @override
  String get label => 'SenseAudio 视频模型 ($_model)';

  @override
  bool get requiresApiKey => true;

  String get baseUrl {
    final raw = (_rawBaseUrl != null && _rawBaseUrl.trim().isNotEmpty)
        ? _rawBaseUrl.trim()
        : 'https://api.senseaudio.cn/v1';
    final trimmed = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    return trimmed;
  }

  Future<String?> readApiKey() async {
    if (_apiKey != null && _apiKey.isNotEmpty) return _apiKey;
    if (_keychainKeyId != null && _keychainKeyId.isNotEmpty) {
      final key = await KeychainService.instance.readSecret(_keychainKeyId);
      if (key != null && key.trim().isNotEmpty) return key.trim();
    }
    return null;
  }

  @override
  Future<bool> isAvailable() async {
    final key = await readApiKey();
    return key != null && key.isNotEmpty;
  }

  @override
  void cancelCurrent() => _cancelled = true;

  Duration get _pollTimeout => const Duration(minutes: 5);

  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('SenseAudio API Key 未配置，请前往「系统设置 -> AI 基础设施」配置视频模型供应商密钥');
    }
    _cancelled = false;

    // 至少要有一张图。SenseAudio 是纯图生视频，没有文生视频模式。
    //
    // 分镜级路径用该镜关键帧；片段级请求不带首帧，参考图集合的第一张顶上
    // ——协议上 content[0] 就是 first_frame，谁来当这一张由请求形状决定。
    if (request.allImages.isEmpty) {
      throw StateError(
        'SenseAudio 图生视频需要一张首帧或参考图；请先为分镜生成关键帧，'
        '或为出场角色配置参考图。',
      );
    }
    for (final file in request.allImages) {
      if (!await file.exists()) {
        throw StateError('参考图片不存在: ${file.path}');
      }
    }

    // 片段提示词优先：它含逐镜动作、台词与连续性状态，比单独的运镜短语
    // 信息量大得多。为空（分镜级路径）才退回运镜短语。
    final promptText = request.effectivePrompt.isEmpty
        ? 'gentle cinematic camera motion, smooth pan'
        : request.effectivePrompt;

    // 时长：SenseAudio 支持 4~15 秒，默认按 request 钳制
    final duration = request.durationSec.round().clamp(4, 15);

    final createEndpoint = Uri.parse('$baseUrl/video/create');

    // content 数组的图片项：首张 role=first_frame，其余 role=reference。
    //
    // SenseAudio 的协议就是数组，多张参考是原生能力——这是四个适配器里
    // 唯一不需要降级的。分镜级路径只传一张，行为与改造前完全一致。
    final imageItems = <Map<String, dynamic>>[];
    for (var i = 0; i < request.allImages.length; i++) {
      final file = request.allImages[i];
      final bytes = await file.readAsBytes();
      imageItems.add({
        'type': 'image',
        'url': 'data:image/png;base64,${base64Encode(bytes)}',
        'role': i == 0 ? 'first_frame' : 'reference',
      });
    }

    final payload = {
      'model': _model,
      'content': [
        {'type': 'text', 'text': promptText},
        ...imageItems,
      ],
      'duration': duration,
      'ratio': '9:16',
      'resolution': '720p',
    };

    final createResponse = await _post(
      createEndpoint,
      key: key,
      body: payload,
    );

    final taskId = _extractTaskId(createResponse);
    if (taskId == null || taskId.isEmpty) {
      throw StateError(
        'SenseAudio 创建视频任务失败: ${_truncate(_extractErrorMessage(createResponse), 200)}',
      );
    }

    final deadline = DateTime.now().add(_pollTimeout);
    var videoUrl = '';
    var lastStatus = '';

    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) {
        throw StateError('视频生成任务已被用户取消');
      }

      await Future<void>.delayed(const Duration(seconds: 4));

      final statusEndpoint = Uri.parse('$baseUrl/video/status?id=$taskId');
      final body = await _get(statusEndpoint, key: key);

      final status = _extractStatus(body);
      lastStatus = status;

      final progressVal = _extractProgress(body);
      if (progressVal != null) {
        onProgress?.call(progressVal);
      } else {
        onProgress?.call(0.5);
      }

      if (status == 'completed' ||
          status == 'succeeded' ||
          status == 'success') {
        videoUrl = _extractVideoUrl(body);
        if (videoUrl.isEmpty) {
          throw StateError('SenseAudio 任务已完成但未返回有效视频播放地址');
        }
        break;
      } else if (status == 'failed' || status == 'error') {
        throw StateError(
          'SenseAudio 视频生成失败: ${_truncate(_extractErrorMessage(body), 200)}',
        );
      }
    }

    if (videoUrl.isEmpty) {
      throw StateError(
        'SenseAudio 任务在 ${_pollTimeout.inMinutes} 分钟内未完成（最后状态: $lastStatus）',
      );
    }

    final http.Response download;
    if (_httpFn != null) {
      download = await _httpFn(http.Request('GET', Uri.parse(videoUrl)));
    } else {
      final client = _client ?? AppHttpClient.create();
      download = await client.get(Uri.parse(videoUrl));
    }
    if (download.statusCode != 200) {
      throw StateError('下载生成的视频失败 (HTTP ${download.statusCode}): $videoUrl');
    }

    await request.outputFile.parent.create(recursive: true);
    await request.outputFile.writeAsBytes(download.bodyBytes, flush: true);
    onProgress?.call(1.0);
    return request.outputFile;
  }

  Future<Map<String, dynamic>> _post(
    Uri uri, {
    required String key,
    required Map<String, dynamic> body,
  }) async {
    final req = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer $key'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final response = _httpFn != null
        ? await _httpFn(req)
        : await (_client ?? AppHttpClient.create())
            .send(req)
            .then(http.Response.fromStream);
    return _decodeBody(response);
  }

  Future<Map<String, dynamic>> _get(Uri uri, {required String key}) async {
    final req = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $key';
    final response = _httpFn != null
        ? await _httpFn(req)
        : await (_client ?? AppHttpClient.create())
            .send(req)
            .then(http.Response.fromStream);
    return _decodeBody(response);
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'SenseAudio API 返回 HTTP ${response.statusCode}：'
        '${_truncate(_extractError(response.body), 200)}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('SenseAudio API 返回体不是 JSON 对象');
    }
    return decoded.map((k, v) => MapEntry(k as String, v));
  }

  static String? _extractTaskId(Map<String, dynamic> body) {
    if (body['id'] is String) return body['id'] as String;
    if (body['task_id'] is String) return body['task_id'] as String;
    final data = body['data'];
    if (data is Map) {
      final id = data['id'] ?? data['task_id'] ?? data['taskId'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  static String _extractStatus(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      final s = data['status'] ?? data['task_status'];
      if (s is String) return s.toLowerCase();
    }
    final s = body['status'] ?? body['task_status'];
    if (s is String) return s.toLowerCase();
    return '';
  }

  static double? _extractProgress(Map<String, dynamic> body) {
    final data = body['data'];
    dynamic p = (data is Map) ? (data['progress'] ?? data['percentage']) : null;
    p ??= body['progress'];
    if (p is num) {
      return (p > 1.0)
          ? (p / 100.0).clamp(0.0, 0.99)
          : p.toDouble().clamp(0.0, 0.99);
    }
    return null;
  }

  static String _extractVideoUrl(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      final url = data['video_url'] ?? data['url'] ?? data['output'];
      if (url is String && url.isNotEmpty) return url;
      final result = data['result'] ?? data['output'];
      if (result is Map) {
        final rUrl = result['video_url'] ?? result['url'];
        if (rUrl is String && rUrl.isNotEmpty) return rUrl;
      }
    }
    final url = body['video_url'] ?? body['url'];
    if (url is String && url.isNotEmpty) return url;
    return '';
  }

  static String _extractErrorMessage(Map<String, dynamic> body) {
    if (body['message'] is String && (body['message'] as String).isNotEmpty) {
      return body['message'] as String;
    }
    if (body['msg'] is String && (body['msg'] as String).isNotEmpty) {
      return body['msg'] as String;
    }
    if (body['error'] != null) {
      return body['error'].toString();
    }
    final data = body['data'];
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    return body.toString();
  }

  static String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return (decoded['message'] ??
                decoded['msg'] ??
                decoded['error'] ??
                body)
            .toString();
      }
    } catch (_) {}
    return body;
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  void disposeForTesting() => _client?.close();
}

/// Agnes Video 2.5 Flash 视频生成适配器（通过中转站 / 官方 OpenAI Videos 兼容协议接入）。
///
/// ## 恢复路径的三个公开入口
///
/// 云端视频任务**创建即计费**，所以「轮询到一半进程死了」必须能接着等，
/// 而不能重新创建（那会二次计费）。这三个方法是 `VideoTaskRecovery` 与任务
/// 面板的唯一入口，它们与 [generateVideo] 共用同一套轮询逻辑：
///
/// - [resumePolling]：为一个已存在的云端任务重新挂起一整段预算的轮询；
/// - [refreshStatusOnce]：只查一次，不碰预算——用户想看「那个卡住的任务
///   现在怎样了」时不该被迫再等十几分钟；
/// - [refetchCompleted]：任务早已完成、只是当初没下载，重新取回产物。
///
/// 恢复时按台账里的型号与供应商重建适配器，而不是读当前槽位配置——用户可能
/// 已经换了默认型号，而那个云端任务还是老型号。
class AgnesVideoAdapter
    implements VideoGenAdapter, CancellableVideoGenAdapter {
  AgnesVideoAdapter({
    String? baseUrl,
    String? model,
    String? apiKey,
    String? providerId,
    String? keychainKeyId,
    http.Client? client,
    ImageHttpFn? httpFn,
  })  : _rawBaseUrl = baseUrl,
        _model = model ?? 'agnes-video-2.5-flash',
        _apiKey = apiKey,
        _providerId = providerId,
        _keychainKeyId = keychainKeyId,
        _client = client,
        _httpFn = httpFn;

  final String? _rawBaseUrl;
  final String _model;
  final String? _apiKey;
  final String? _providerId;
  final String? _keychainKeyId;
  final http.Client? _client;
  final ImageHttpFn? _httpFn;

  bool _cancelled = false;

  @override
  String get id =>
      _providerId != null ? 'agnes-$_providerId' : 'agnes-video-2.5-flash';

  @override
  String get label => 'Agnes 视频模型 ($_model)';

  @override
  bool get requiresApiKey => true;

  String get baseUrl {
    final raw = (_rawBaseUrl != null && _rawBaseUrl.trim().isNotEmpty)
        ? _rawBaseUrl.trim()
        : 'https://apihub.agnes-ai.com/v1';
    var trimmed = raw;
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// 查询端点的根地址（去掉 `/v1` 后缀）。
  ///
  /// `/agnesapi` 挂在根下而不是 `/v1` 下：文档示例是
  /// `https://api.agnes-ai.cn/agnesapi?...`，而创建端点是
  /// `https://api.agnes-ai.cn/v1/videos`。两者前缀不同，不能简单地拼。
  String get _queryRoot {
    final b = baseUrl;
    return b.endsWith('/v1') ? b.substring(0, b.length - 3) : b;
  }

  Future<String?> readApiKey() async {
    if (_apiKey != null && _apiKey.isNotEmpty) return _apiKey;
    if (_keychainKeyId != null && _keychainKeyId.isNotEmpty) {
      final key = await KeychainService.instance.readSecret(_keychainKeyId);
      if (key != null && key.trim().isNotEmpty) return key.trim();
    }
    return null;
  }

  @override
  Future<bool> isAvailable() async {
    final key = await readApiKey();
    return key != null && key.isNotEmpty;
  }

  @override
  void cancelCurrent() => _cancelled = true;

  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('Agnes API Key 未配置，请前往「系统设置 -> AI 基础设施」配置视频模型供应商密钥');
    }
    _cancelled = false;

    // 1. 模式推导与官方互斥校验（官方规则表）
    final String derivedMode;
    final String? firstFrameUri;
    final String? lastFrameUri;
    final List<String> refUris;

    switch (request.mode) {
      case AgnesVideoMode.keyframe:
        if (request.referenceImages.isNotEmpty) {
          throw StateError('Agnes keyframe 模式下首尾帧素材与参考素材不能同时使用');
        }
        if (request.inputImage == null && request.lastFrameImage == null) {
          throw StateError('Agnes keyframe 模式需要首帧或尾帧');
        }
        firstFrameUri = (request.inputImage != null && await request.inputImage!.exists())
            ? await _prepareFrameDataUri(request.inputImage!, roleName: '首帧')
            : null;
        lastFrameUri = (request.lastFrameImage != null && await request.lastFrameImage!.exists())
            ? await _prepareFrameDataUri(request.lastFrameImage!, roleName: '尾帧')
            : null;
        if (firstFrameUri == null && lastFrameUri == null) {
          throw StateError('Agnes keyframe 模式提供的首尾帧图片文件不存在');
        }
        derivedMode = 'keyframe';
        refUris = const [];
        break;

      case AgnesVideoMode.reference:
        if (request.inputImage != null || request.lastFrameImage != null) {
          throw StateError('Agnes reference 模式下首尾帧素材与参考素材不能同时使用');
        }
        if (request.referenceImages.isEmpty) {
          throw StateError('Agnes reference 模式需要至少一张参考素材');
        }
        firstFrameUri = null;
        lastFrameUri = null;
        refUris = await Future.wait(
          request.referenceImages.map((f) => _prepareFrameDataUri(f, roleName: '参考图')),
        );
        derivedMode = 'reference';
        break;

      case AgnesVideoMode.text:
        if (request.inputImage != null ||
            request.lastFrameImage != null ||
            request.referenceImages.isNotEmpty) {
          throw StateError('Agnes text 模式下不能传递任何图片素材');
        }
        firstFrameUri = null;
        lastFrameUri = null;
        refUris = const [];
        derivedMode = 'text';
        break;

      case AgnesVideoMode.auto:
        // auto 模式自适应推导：
        // 1. 若提供了首尾帧且存在，则走 keyframe；
        // 2. 若仅提供了参考图且第一张存在，则第一张提升为首帧走 keyframe；
        // 3. 其余情况（无图片或图片在磁盘上不存在）自适应回退到 text 模式。
        final rawFirst = request.inputImage ??
            (request.referenceImages.isNotEmpty ? request.referenceImages.first : null);
        final rawLast = request.lastFrameImage;

        final fUri = (rawFirst != null && await rawFirst.exists())
            ? await _prepareFrameDataUri(rawFirst, roleName: '首帧')
            : null;
        final lUri = (rawLast != null && await rawLast.exists())
            ? await _prepareFrameDataUri(rawLast, roleName: '尾帧')
            : null;

        if (fUri != null || lUri != null) {
          derivedMode = 'keyframe';
          firstFrameUri = fUri;
          lastFrameUri = lUri;
          refUris = const [];
        } else {
          derivedMode = 'text';
          firstFrameUri = null;
          lastFrameUri = null;
          refUris = const [];
        }
        break;
    }

    // 片段提示词优先：它含逐镜动作与台词，比单独运镜短语更能驱动画面。
    final promptText = request.effectivePrompt.isEmpty
        ? 'cinematic camera motion, smooth video movement'
        : request.effectivePrompt;

    // 时长：Agnes Video 2.5 Flash 接受字符串 "4"~"12"，默认 "5"
    final durationSeconds = request.durationSec.round().clamp(4, 12).toString();

    // 尺寸档位：大小写归一（能力矩阵小写 → Agnes 大写），未指定时默认 720P
    final resolvedSize = request.sizeTier.trim().isNotEmpty
        ? request.sizeTier.trim().toUpperCase()
        : '720P';

    // 画幅比例：随请求，未指定时默认 9:16
    final resolvedRatio = request.ratio.trim().isNotEmpty
        ? request.ratio.trim()
        : '9:16';

    final createUrl =
        baseUrl.endsWith('/v1') ? '$baseUrl/videos' : '$baseUrl/v1/videos';

    final payload = <String, dynamic>{
      'model': _model,
      'prompt': promptText,
      'mode': derivedMode,
      'seconds': durationSeconds,
      'size': resolvedSize,
      'aspect_ratio': resolvedRatio,
      if (firstFrameUri != null) 'first_frame': firstFrameUri,
      if (lastFrameUri != null) 'last_frame': lastFrameUri,
      if (refUris.isNotEmpty) 'images': refUris,
      if (request.seed != null) 'seed': request.seed,
    };

    onProgress?.call(0.1);
    final createResponse = await _post(
      Uri.parse(createUrl),
      key: key,
      body: payload,
      onRetryNotice: (attempt, delaySec) {
        onProgress?.call(0.05);
      },
    );

    // 查询要用 video_id，不是 id / task_id——文档明言这三者的分工。
    // 存错字段的后果是恢复路径永远查不到任务，用户失去唯一的线索。
    final taskId = _readVideoId(createResponse) ??
        SenseAudioVideoAdapter._extractTaskId(createResponse);
    if (taskId == null || taskId.isEmpty) {
      throw StateError(
        'Agnes 创建视频任务失败: ${SenseAudioVideoAdapter._truncate(SenseAudioVideoAdapter._extractErrorMessage(createResponse), 200)}',
      );
    }

    final sanitizedPayload = <String, dynamic>{
      'model': _model,
      'prompt': promptText,
      'mode': derivedMode,
      'seconds': durationSeconds,
      'size': resolvedSize,
      'aspect_ratio': resolvedRatio,
      if (firstFrameUri != null)
        'first_frame': '<data:image;base64,... len=${firstFrameUri.length}>',
      if (lastFrameUri != null)
        'last_frame': '<data:image;base64,... len=${lastFrameUri.length}>',
      if (refUris.isNotEmpty)
        'images': refUris
            .map((u) => '<data:image;base64,... len=${u.length}>')
            .toList(),
      if (request.seed != null) 'seed': request.seed,
    };

    // **先落台账再轮询**（spec: 创建即持久化）。顺序反了就失去「轮询途中被
    // 杀也留得下线索」这个性质——而任务创建即计费，线索断了用户只能认损。
    final parsedSec = int.tryParse(durationSeconds) ?? request.durationSec.round();
    final ledgerEntry = await VideoTaskLedger.instance.record(
      providerId: _providerId ?? id,
      adapterId: id,
      model: _model,
      remoteTaskId: taskId,
      seriesId: request.seriesId ?? '',
      episodeId: request.episodeId ?? '',
      segmentId: request.segmentId ?? '',
      shotNumber: request.shotNumber,
      label: request.label ?? '视频任务',
      targetPath: request.outputFile.path,
      prompt: request.effectivePrompt.isEmpty
          ? null
          : request.effectivePrompt,
      requestSnapshot: <String, dynamic>{
        'channel': 'video',
        'providerId': _providerId ?? id,
        'model': _model,
        'prompt': promptText,
        'durationSec': parsedSec,
        'durationSeconds': parsedSec,
        'aspectRatio': resolvedRatio,
        'ratio': resolvedRatio,
        'sizeTier': resolvedSize,
        'resolution': resolvedSize,
        'mode': derivedMode,
        if (request.seed != null) 'seed': request.seed.toString(),
        if (request.inputImage != null) 'firstFramePath': request.inputImage!.path,
        if (request.lastFrameImage != null) 'lastFramePath': request.lastFrameImage!.path,
        'referencePaths': [
          ...request.referenceImages.map((f) => f.path),
        ],
        'rawPayload': sanitizedPayload,
      },
    );

    final videoUrl = await _pollUntilDone(
      videoId: taskId,
      key: key,
      onProgress: onProgress,
      ledgerEntry: ledgerEntry,
    );

    if (videoUrl.isEmpty) {
      // 预算耗尽但云端未见失败。**不抛错判失败**——那会让上层记成失败、
      // 用户以为没花钱也没产出；事实是钱花了、视频还在云端。台账已置为
      // cloudProcessing，任务面板可继续等待。
      AiLogger.logWarning(
        'Agnes 视频任务超出本地轮询预算，云端仍在处理（video_id: $taskId）',
        providerName: 'Agnes',
      );
      throw StateError(
        'Agnes 视频任务在本地等待预算内未完成，但云端仍在处理中（video_id: $taskId）。'
        '积分已扣除，视频未丢失——可在任务面板点「继续等待」取回，'
        '或复制该 id 去 Agnes 控制台自查。',
      );
    }

    await _downloadTo(videoUrl, request.outputFile);
    await VideoTaskLedger.instance.update(
      ledgerEntry.localId,
      status: VideoTaskLedgerStatus.completed,
      lastRemoteStatus: 'completed',
      lastProgress: 100,
    );
    onProgress?.call(1.0);
    return request.outputFile;
  }

  /// 将首帧、尾帧或参考图进行合规校验与预处理：
  /// - 校验单边尺寸需在 256–5760 像素之间，越界抛出 StateError；
  /// - 等比限制最大边长为 720x1280 规格（竖屏 720x1280，横屏 1280x720）；
  /// - 统一转码为高质量 JPEG（质量 80），体积精简至 60~100KB。
  static Future<String> _prepareFrameDataUri(File file, {String roleName = '图片'}) async {
    final rawBytes = await file.readAsBytes();
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        if (decoded.width < 256 || decoded.height < 256) {
          throw StateError(
            '$roleName图片尺寸过小：单边尺寸需不小于 256 像素（当前为 ${decoded.width}×${decoded.height}）',
          );
        }
        img.Image processed = decoded;
        if (decoded.width > 720 || decoded.height > 1280) {
          final aspect = decoded.width / decoded.height;
          if (aspect <= 720.0 / 1280.0) {
            processed = img.copyResize(decoded, height: 1280);
          } else {
            processed = img.copyResize(decoded, width: 720);
          }
        }
        final jpegBytes = img.encodeJpg(processed, quality: 80);
        return 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
      }
    } on StateError {
      rethrow;
    } catch (e) {
      AiLogger.logWarning(
        '$roleName预处理转码失败，回退原始编码: $e',
        providerName: 'Agnes',
      );
    }
    return 'data:image/png;base64,${base64Encode(rawBytes)}';
  }

  Future<Map<String, dynamic>> _post(
    Uri uri, {
    required String key,
    required Map<String, dynamic> body,
    void Function(int attempt, int delaySec)? onRetryNotice,
  }) async {
    final maxAttempts = 5;
    var currentDelayMs = 2000;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final stopwatch = Stopwatch()..start();
      AiLogger.logRequest(
        providerName: 'Agnes',
        protocol: 'openai-video',
        model: body['model'] as String? ?? _model,
        endpoint: uri.toString(),
        promptSummary: body['prompt'] as String?,
      );

      final req = http.Request('POST', uri)
        ..headers['Authorization'] = 'Bearer $key'
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
      final response = _httpFn != null
          ? await _httpFn(req)
          : await (_client ?? AppHttpClient.create())
              .send(req)
              .then(http.Response.fromStream);
      stopwatch.stop();

      // 判断是否属于可自动换路重试的网关瞬时错误：
      // 1. 429: 上游分组负载饱和并发限流
      // 2. 502 / 503 / 504: 网关错误或上游视频队列已满
      // 3. 400 且提示缺少首帧: 中转站个别坏上游渠道丢弃了图片参数，重试可轮询切换到正常节点
      final statusCode = response.statusCode;
      final bodyText = response.body;
      final isRateLimited = statusCode == 429;
      final isGatewayError = statusCode == 502 || statusCode == 503 || statusCode == 504;
      final isBadChannelParameterDrop = statusCode == 400 &&
          (bodyText.contains('first_frame 或 last_frame') ||
              bodyText.contains('keyframe 模式需要') ||
              bodyText.contains('first_frame'));

      if ((isRateLimited || isGatewayError || isBadChannelParameterDrop) &&
          attempt < maxAttempts) {
        final reason = isBadChannelParameterDrop
            ? '网关渠道节点异常丢失参数，切换路由节点重试'
            : (isRateLimited ? '上游负载饱和 (429)' : '网关或视频队列繁忙 ($statusCode)');
        
        final waitSec = (currentDelayMs / 1000.0).toStringAsFixed(1);
        AiLogger.logWarning(
          'Agnes API $reason，第 $attempt/$maxAttempts 次重试，等待 ${waitSec}s...',
          providerName: 'Agnes',
        );
        onRetryNotice?.call(attempt, (currentDelayMs / 1000).ceil());

        await Future<void>.delayed(Duration(milliseconds: currentDelayMs));
        // 指数退避加 200~600ms 随机抖动
        final jitter = 200 + (attempt * 100 % 400);
        currentDelayMs = (currentDelayMs * 1.5).round() + jitter;
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final err = 'Agnes API 返回 HTTP ${response.statusCode}：'
            '${SenseAudioVideoAdapter._truncate(SenseAudioVideoAdapter._extractError(response.body), 200)}';
        AiLogger.logError(err, providerName: 'Agnes');
        throw StateError(err);
      }

      AiLogger.logResponse(
        providerName: 'Agnes',
        statusCode: response.statusCode,
        durationMs: stopwatch.elapsedMilliseconds,
        bodyPreview: response.body,
      );

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Agnes API 返回体不是 JSON 对象');
      }
      return decoded.map((k, v) => MapEntry(k as String, v));
    }

    throw StateError('Agnes API 请求在重试 $maxAttempts 次后依然未能接入可用上游渠道');
  }

  Future<http.Response> _getRaw(Uri uri, {required String key}) async {
    final req = http.Request('GET', uri)
      ..headers['Authorization'] = 'Bearer $key';
    return _httpFn != null
        ? await _httpFn(req)
        : await (_client ?? AppHttpClient.create())
            .send(req)
            .then(http.Response.fromStream);
  }

  // ---------------------------------------------------------------------------
  // 轮询核心（generateVideo 与恢复路径共用）
  // ---------------------------------------------------------------------------

  /// 轮询直到完成。返回视频地址；预算耗尽返回空串（**不抛错**）。
  ///
  /// 返回空而不是抛错是刻意的：云端任务创建即计费，此时抛错会让上层把任务
  /// 记成失败，用户以为"没花钱也没产出"，而事实是钱花了、视频还在云端。
  /// 调用方据此把台账条目置为 cloudProcessing。
  ///
  /// 这个方法与恢复路径共用——重启后重新挂起的轮询走同一套逻辑，不复制第二份。
  Future<String> _pollUntilDone({
    required String videoId,
    required String key,
    void Function(double progress)? onProgress,
    VideoTaskLedgerEntry? ledgerEntry,
  }) async {
    // 两段预算：排队 + 生成。阶段切换以云端 queued → in_progress 为依据，
    // 这是唯一可靠的推断（Agnes 不返回"预计开始时间"）。
    final queueBudget = SettingsStore.instance.videoQueueBudget;
    final genBudget = SettingsStore.instance.videoGenerateBudget;
    final totalBudget = Duration(
      milliseconds: queueBudget.inMilliseconds + genBudget.inMilliseconds,
    );

    final deadline = DateTime.now().add(totalBudget);
    var interval = const Duration(seconds: 2);
    var videoUrl = '';
    var sawInProgress = ledgerEntry?.sawInProgress ?? false;

    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) {
        throw StateError('视频生成任务已被用户取消');
      }

      await Future<void>.delayed(interval);
      if (_cancelled) {
        throw StateError('视频生成任务已被用户取消');
      }

      final outcome = await _queryTask(videoId: videoId, key: key);

      if (outcome.notFound) {
        // 明确的失败信号：任务标识在云端不存在。重试无意义。
        throw StateError(outcome.errorMessage ?? '云端任务不存在');
      }
      if (outcome.rateLimited) {
        // 限流：退避并保持上一次已知状态与进度。**不得**依据错误体更新
        // 进度或阶段——它没有那些字段，读了只会得到虚假的"未知"。
        interval = Duration(
          milliseconds: (interval.inMilliseconds * 2).clamp(2000, 8000),
        );
        AiLogger.logWarning(
          'Agnes 查询被限流，退避到 ${interval.inSeconds}s',
          providerName: 'Agnes',
        );
        continue;
      }
      if (outcome.errorMessage != null) {
        // 其他查询错误（网络 / 5xx / 响应畸形）。云端可能好着，不当任务失败。
        interval = Duration(
          milliseconds: (interval.inMilliseconds * 2).clamp(2000, 8000),
        );
        continue;
      }

      final queryData = outcome.body;
      if (queryData == null) {
        interval = Duration(
          milliseconds: (interval.inMilliseconds * 2).clamp(2000, 8000),
        );
        continue;
      }

      // 间隔恢复：查询成功说明链路是通的
      interval = const Duration(seconds: 2);

      // 顶层字段，不用 data 嵌套——那是 SenseAudio 的形态，不是 Agnes 的。
      // 内部字段（internal_status / internal_progress）刻意不读：文档明言
      // 即使它们仍是 pending/0，也应以 status/progress 为准。
      //
      // 状态取值域实测有**五态**（2026-10-13）：queued / pending /
      // in_progress / completed / failed。文档只列了四态，漏了 pending
      // （出现在 started_at 之前、progress=0）。所以这里只判两个终态，
      // 其余一切值一律视为"还在跑"——枚举匹配是个漏不得的游戏。
      final status = (queryData['status'] as String? ?? '').toLowerCase();
      final progressVal = (queryData['progress'] as num?)?.toInt();
      final startedAt = (queryData['started_at'] as num?)?.toInt();

      // started_at 非空即认为已进入生成段。用时间戳而不是状态字符串：
      // pending 既出现在排队尾也出现在生成前，字符串判不了阶段。
      if (startedAt != null && startedAt > 0 && !sawInProgress) {
        sawInProgress = true;
      }

      if (progressVal != null) {
        onProgress?.call(progressVal.clamp(0, 100) / 100.0);
      } else {
        // 云端没给进度时不编造百分比——只报个"还在跑"的中性值。
        onProgress?.call(0.5);
      }

      if (ledgerEntry != null) {
        await VideoTaskLedger.instance.update(
          ledgerEntry.localId,
          lastRemoteStatus: status,
          lastProgress: progressVal,
          sawInProgress: sawInProgress ? true : null,
          elapsedPollMs: totalBudget.inMilliseconds -
              deadline.difference(DateTime.now()).inMilliseconds,
        );
      }

      if (status == 'completed') {
        final meta = queryData['metadata'];
        final metaUrl = meta is Map ? meta['url'] as String? : null;
        videoUrl = (queryData['url'] as String?) ?? metaUrl ?? '';
        if (videoUrl.isNotEmpty) break;
      } else if (status == 'failed') {
        final msg = _readErrorMessage(queryData);
        if (ledgerEntry != null) {
          await VideoTaskLedger.instance.update(
            ledgerEntry.localId,
            status: VideoTaskLedgerStatus.failed,
            lastRemoteStatus: status,
            error: msg,
          );
        }
        throw StateError('Agnes 视频生成失败: $msg');
      }
      // 其余状态（queued / pending / in_progress / 文档外的任何值）：继续轮询。
      // 刻意不做枚举匹配——今天漏一个 pending，明天来个 initializing 又漏。
    }

    if (videoUrl.isEmpty && ledgerEntry != null) {
      // 预算耗尽但任务未见 failed——云端还在跑。置为 cloudProcessing 而非
      // failed，让用户知道东西还在。
      await VideoTaskLedger.instance.update(
        ledgerEntry.localId,
        status: VideoTaskLedgerStatus.cloudProcessing,
      );
    }
    return videoUrl;
  }

  /// 查询云端任务。主路径是 `/agnesapi`（文档推荐，keyframe/reference 模式
  /// 必须带 model_name），`/v1/videos/<id>` 降为兜底。
  Future<_QueryOutcome> _queryTask({
    required String videoId,
    required String key,
  }) async {
    final primary = Uri.parse(
      '$_queryRoot/agnesapi?video_id=$videoId&model_name=$_model',
    );
    try {
      final resp = await _getRaw(primary, key: key);
      final outcome = _QueryOutcome.fromResponse(
        resp,
        fromFallback: false,
        videoId: videoId,
      );
      // 成功拿到业务体 → 主路径的结论。
      if (outcome.body != null) {
        return outcome;
      }
      // notFound / rateLimited 是主路径给出的**明确结论**，不是"主路径坏了"。
      // 尤其限流是 HTTP 200 带 error body——落兜底只会让兜底也撞同一个限流。
      if (outcome.notFound || outcome.rateLimited) {
        return outcome;
      }
      // 其余（HTTP 5xx / 响应畸形）视为主路径不可用，落兜底。
    } on StateError {
      rethrow;
    } catch (_) {
      // 落到兜底路径
    }

    final fallback = Uri.parse(
      baseUrl.endsWith('/v1')
          ? '$baseUrl/videos/$videoId'
          : '$baseUrl/v1/videos/$videoId',
    );
    final resp = await _getRaw(fallback, key: key);
    return _QueryOutcome.fromResponse(
      resp,
      fromFallback: true,
      videoId: videoId,
    );
  }

  Future<void> _downloadTo(String videoUrl, File outputFile) async {
    final http.Response download;
    if (_httpFn != null) {
      download = await _httpFn(http.Request('GET', Uri.parse(videoUrl)));
    } else {
      final client = _client ?? AppHttpClient.create();
      download = await client.get(Uri.parse(videoUrl));
    }
    if (download.statusCode != 200) {
      throw StateError(
        '下载生成的视频失败 (HTTP ${download.statusCode}): $videoUrl',
      );
    }
    final bytes = download.bodyBytes;
    // 完整性校验：缺失或大小异常都不算完成。把 200 字节的坏文件当成功，
    // 用户拿到的是一个打不开的片段，比明确失败难查得多。
    if (bytes.length < 1024) {
      throw StateError('下载到的视频文件异常（仅 ${bytes.length} 字节）');
    }
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(bytes, flush: true);
  }

  /// 读取视频 ID。优先顶层 `video_id`，再退 `data.video_id`。
  static String? _readVideoId(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      final v = data['video_id'] ?? data['videoId'];
      if (v is String && v.isNotEmpty) return v;
    }
    final v = body['video_id'] ?? body['videoId'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  /// 读取失败原因。Agnes 的 error 是对象：`{"message": "..."}`。
  static String _readErrorMessage(Map<String, dynamic> body) {
    final err = body['error'];
    if (err is Map) {
      final msg = err['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    if (err is String && err.isNotEmpty) return err;
    final msg = body['message'];
    if (msg is String && msg.isNotEmpty) return msg;
    return '未知错误（响应: ${SenseAudioVideoAdapter._truncate(body.toString(), 200)}）';
  }

  // ---------------------------------------------------------------------------
  // 恢复路径（与 generateVideo 共用同一套轮询逻辑，不复制第二份）
  // ---------------------------------------------------------------------------

  /// 恢复路径专用：为一个已存在的云端任务继续轮询。
  ///
  /// 与 [_pollUntilDone] 的差别只在这**不创建任务**——恢复时云端任务早已
  /// 存在，再调创建接口就是第二次计费。返回视频地址；预算耗尽返回 null
  /// （**不抛错**），让调用方把条目留待下一轮。
  Future<String?> resumePolling({
    required VideoTaskLedgerEntry entry,
    void Function(double progress)? onProgress,
  }) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) return null;
    _cancelled = false;
    final url = await _pollUntilDone(
      videoId: entry.remoteTaskId,
      key: key,
      onProgress: onProgress,
      ledgerEntry: entry,
    );
    return url.isEmpty ? null : url;
  }

  /// 轻量查询一次任务状态，只更新台账。
  ///
  /// **与 [resumePolling] 的分界**：那个重新挂起一整段轮询预算，这个只查
  /// 一次就返回。用户想看"那个卡住的任务现在怎样了"时不该被迫再等十几分钟
  /// ——所以它不碰 [_pollUntilDone] 的预算与 `sawInProgress`。
  ///
  /// 返回查询到的状态原文；查不到（网络/限流）返回 null，调用方据此提示
  /// "稍后再试"，而不是假装任务消失了。
  Future<String?> refreshStatusOnce(VideoTaskLedgerEntry entry) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) return null;
    _cancelled = false;

    final outcome = await _queryTask(videoId: entry.remoteTaskId, key: key);
    if (outcome.notFound) {
      throw StateError(outcome.errorMessage ?? '云端任务不存在');
    }
    if (outcome.rateLimited || outcome.errorMessage != null) {
      return null;
    }
    final body = outcome.body;
    if (body == null) return null;

    final status = (body['status'] as String? ?? '').toLowerCase();
    final progress = (body['progress'] as num?)?.toInt();
    final startedAt = (body['started_at'] as num?)?.toInt();

    await VideoTaskLedger.instance.update(
      entry.localId,
      lastRemoteStatus: status,
      lastProgress: progress,
      // started_at 非空即认为已进入生成段——与 _pollUntilDone 同一套判据。
      sawInProgress: (startedAt != null && startedAt > 0) ? true : null,
    );
    return status;
  }

  /// 重新下载一个**已完成**任务的产物。
  ///
  /// 用于「任务完成了但当时没下载成功」与「用户手动点取回」两种情形。云端
  /// 地址有过期时间，取不到时明确告知而不是写一个空文件。
  Future<File> refetchCompleted(VideoTaskLedgerEntry entry) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('API Key 不可用，无法取回该任务');
    }
    final outcome = await _queryTask(videoId: entry.remoteTaskId, key: key);
    if (outcome.notFound) {
      throw StateError(outcome.errorMessage ?? '云端任务不存在');
    }
    final body = outcome.body;
    if (body == null) {
      throw StateError('查询失败，请稍后再试');
    }
    final status = (body['status'] as String? ?? '').toLowerCase();
    if (status != 'completed') {
      throw StateError('云端任务当前状态为 $status，尚未完成，无法取回');
    }
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('云端任务已完成但未返回视频地址（可能已过期）');
    }

    final target = File(entry.targetPath);
    await _downloadTo(url, target);
    await VideoTaskLedger.instance.update(
      entry.localId,
      status: VideoTaskLedgerStatus.completed,
      lastRemoteStatus: 'completed',
      lastProgress: 100,
    );
    return target;
  }

  /// 下载到指定文件。恢复路径直接复用，不另写一份下载逻辑。
  Future<void> downloadTo(String videoUrl, File outputFile) =>
      _downloadTo(videoUrl, outputFile);

  void disposeForTesting() => _client?.close();
}

/// 一次查询的结论。
///
/// 三个"非业务体"出口（notFound / rateLimited / errorMessage）与 `body`
/// 分开：它们的处置方式完全不同——前两者要直接采纳主路径的结论，后者要落
/// 兜底路径。合成一个可空字段就会丢掉这个区别。
class _QueryOutcome {
  const _QueryOutcome({
    this.body,
    this.notFound = false,
    this.rateLimited = false,
    this.errorMessage,
  });

  /// 业务体。null 表示这次查询没拿到可用响应。
  final Map<String, dynamic>? body;

  /// 任务标识在云端不存在（404）。明确的失败信号，不重试。
  final bool notFound;

  /// 被限流。要退避，但**不得**据此更新进度或阶段。
  final bool rateLimited;

  /// 其他查询错误（5xx / 响应畸形）。调用方退避后重试。
  final String? errorMessage;

  factory _QueryOutcome.fromResponse(
    http.Response resp, {
    required bool fromFallback,
    required String videoId,
  }) {
    if (resp.statusCode == 404) {
      return _QueryOutcome(
        notFound: true,
        errorMessage: '云端任务不存在（video_id: $videoId）',
      );
    }
    if (resp.statusCode == 429) {
      return const _QueryOutcome(rateLimited: true);
    }
    if (resp.statusCode != 200) {
      return _QueryOutcome(
        errorMessage: '查询失败 (HTTP ${resp.statusCode})'
            '${fromFallback ? ' [兜底路径]' : ''}',
      );
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        body = decoded.map((k, v) => MapEntry(k as String, v));
      }
    } catch (_) {
      // 响应畸形：落到 errorMessage，让调用方退避重试。
    }
    if (body == null) {
      return _QueryOutcome(
        errorMessage: '查询响应解析失败'
            '${fromFallback ? ' [兜底路径]' : ''}',
      );
    }

    // HTTP 200 也可能带限流错误体（上游惯用做法）。认它而不是当成任务状态，
    // 否则会把一次限流读成"任务消失了"。
    final errText = body['error'];
    if (errText != null) {
      final text = errText is Map
          ? (errText['message']?.toString() ?? errText.toString())
          : errText.toString();
      if (text.contains('429') ||
          text.toLowerCase().contains('rate') ||
          text.contains('饱和')) {
        return const _QueryOutcome(rateLimited: true);
      }
    }
    return _QueryOutcome(body: body);
  }
}

/// 视频生成适配器工厂。
///
/// 选择顺序：显式偏好 → 全局系统配置的 video 槽位模型 (Agnes / SenseAudio) → 有 Key 的商业引擎 (Kling) → 本地 Ken Burns。
/// 本地引擎不可用（没装 FFmpeg）时仍返回它，让上层把"请安装 FFmpeg"或"请配置视频模型"的可操作提示显示出来。
/// 规整包装器：把 [MediaRequestNormalizer] 套在任意视频适配器外。
///
/// **为什么用包装而不是在每个适配器里调用**（design 决策 5）：四个适配器的
/// payload 构造差异很大，但规整逻辑完全相同。包装让新适配器自动获得规整，
/// 不需要每个作者记得调用——漏一次的后果是"这个模型的参数没被吸附"，
/// 而这种 bug 只在特定模型上出现，测试很难覆盖到。
///
/// 代价是运行时的静态类型不再是具体适配器（`adapter is KenBurnsVideoAdapter`
/// 会失效）。用 [unwrap] 取回内层，`SegmentVideoGenTask` 的
/// `forceLocalKenBurns` 判断已改为先 unwrap 再比较。
class NormalizingVideoAdapter implements VideoGenAdapter, CancellableVideoGenAdapter {
  NormalizingVideoAdapter(this._inner, this._capability, {this.modelId = ''});

  final VideoGenAdapter _inner;
  final MediaModelCapability _capability;

  /// 仅用于日志：让「哪个模型的参数被吸附了」可查。
  final String modelId;

  @override
  String get id => _inner.id;

  @override
  String get label => _inner.label;

  @override
  bool get requiresApiKey => _inner.requiresApiKey;

  @override
  Future<bool> isAvailable() => _inner.isAvailable();

  @override
  void cancelCurrent() {
    final inner = _inner;
    if (inner is CancellableVideoGenAdapter) {
      (inner as CancellableVideoGenAdapter).cancelCurrent();
    }
  }

  /// 取回内层适配器。规整发生在 [_inner] 之前，所以拿到的还是原始实现。
  VideoGenAdapter unwrap() => _inner;

  /// 当前适配器遵循的能力约束（时长、画幅、参考图上限等）。
  MediaModelCapability get capability => _capability;

  /// 测试用：读内部的能力声明，验证「配置层是否接上」。
  ///
  /// 不跑 generateVideo——那会真去打云端。只断言解析结果。
  @visibleForTesting
  MediaModelCapability get debugCapabilityForTesting => _capability;

  /// 最近一次 [generateVideo] 的参数变更记录。
  ///
  /// 暴露出来是为了让 `SegmentVideoGenTask` 能把「实际提交时长」写回数据层
  /// ——用户请求 15s 而模型只支持 12s 时，看板要能显示这个差异。
  List<String> get lastChanges => List.unmodifiable(_lastChanges);

  List<String> _lastChanges = const [];

  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    final normalizer = MediaRequestNormalizer(_capability);
    final result = normalizer.normalize(
      MediaRequestSpec(
        durationSec: request.durationSec,
        resolution: request.sizeTier,
        ratio: request.ratio,
        referenceImageCount: request.allImages.length,
        hasFirstFrame: request.inputImage != null,
        hasLastFrame: request.lastFrameImage != null,
      ),
    );

    // 吸附必须可见（spec: 规整与降级可见）。走 AiLogger 而不是 debugPrint：
    // 用户报"为什么生成的视频只有 12 秒"时，日志是唯一能回答的地方。
    _lastChanges = result.changes;
    if (result.hasChanges) {
      AiLogger.logWarning(
        '参数规整：${result.changes.join('；')}',
        providerName: modelId.isEmpty ? _inner.id : modelId,
      );
    }

    return _inner.generateVideo(
      VideoGenRequest(
        inputImage: request.inputImage,
        lastFrameImage: request.lastFrameImage,
        referenceImages: request.referenceImages,
        promptZh: request.promptZh,
        cameraMove: request.cameraMove,
        durationSec: result.request.durationSec,
        shotNumber: request.shotNumber,
        outputFile: request.outputFile,
        productionType: request.productionType,
        mode: request.mode,
        sizeTier: result.request.resolution,
        ratio: result.request.ratio,
        seed: request.seed,
        seriesId: request.seriesId,
        episodeId: request.episodeId,
        segmentId: request.segmentId,
        label: request.label,
      ),
      onProgress: onProgress,
    );
  }
}

class VideoGenAdapterFactory {
  VideoGenAdapterFactory._();

  /// 把适配器包上能力规整（spec: 请求参数规整）。
  ///
  /// 本地 Ken Burns 不包：它没有外部参数约束，且它的时长上限来自
  /// `totalFrames.clamp(30, 900)`（即 1–30 秒），本来就不该被媒体模型的能力
  /// 矩阵裁剪。包了反而会让"narration 类型想要 40 秒片段"这种合理请求被拒。
  static VideoGenAdapter _wrap(
    VideoGenAdapter adapter,
    String modelId, {
    AiProviderConfigLike? capabilitySource,
  }) {
    if (adapter is KenBurnsVideoAdapter) return adapter;
    // 已在 [_byId] 内包过的就不再包第二层：双层规整会让
    // `NormalizingVideoAdapter.unwrap()` 拿到又一个包装器，调用方对内层具体
    // 类型的判断（如工坊设置同步测试的 `isA<SenseAudioVideoAdapter>()`）失效。
    if (adapter is NormalizingVideoAdapter) return adapter;
    // 三级查找与 `MediaCapabilityResolver.resolve` 一致：显式声明 > 内置预设
    // > 协议保守默认。这里不直接调 resolver 是因为 `capabilitySource` 可能为
    // null（Kling / Dola 之外的路径没有可传的来源）。
    final capability = switch (capabilitySource) {
      final source? when source.mediaCapabilities.containsKey(modelId) =>
        MediaCapabilityResolver.resolve(source, modelId),
      _ =>
        MediaCapabilityPresets.forModel(modelId) ??
            MediaCapabilityDefaults.openai,
    };
    return NormalizingVideoAdapter(adapter, capability, modelId: modelId);
  }

  static Future<VideoGenAdapter> create({
    String? preferredEngineId,
    String productionType = 'drama',
  }) async {
    // 1. 显式偏好匹配
    if (preferredEngineId != null && preferredEngineId.isNotEmpty) {
      final adapter = await _byId(preferredEngineId);
      if (adapter != null) {
        // 能力查找统一用 adapter.id，不用 preferredEngineId。
        //
        // 两者对号池是不同的：用户在设置里选的是 'dola-pool-2.5'（短 id），
        // 而适配器的 id 是 'dola-pool-seedance-2.5'（含型号全名）。用短 id
        // 去查能力，内置预设和用户覆盖都命中不了——能力查找会静默落到
        // openai 默认值，而那个默认值的时长集合与 Dola 真实能力不同。
        //
        // 号池引擎同样要接上能力配置层，否则用户在界面上改的覆盖只在小退
        // 那条路上生效。
        final source = adapter is DolaPoolVideoAdapter
            ? DolaConfigStore.instance
            : null;
        return _wrap(adapter, adapter.id, capabilitySource: source);
      }
    }

    // 2. 优先检查系统全局配置的 video 槽位候选供应商
    final videoCandidates = AiConfigStore.instance.slotBindings['video'] ?? [];
    for (final candidate in videoCandidates) {
      final provider = AiConfigStore.instance.providers.firstWhere(
        (p) => p.id == candidate.providerId && p.enabled,
        orElse: () => const AiProviderConfig(
          id: '',
          name: '',
          protocol: AiProtocolType.openai,
          baseUrl: '',
          keychainKeyId: '',
        ),
      );
      if (provider.id.isNotEmpty) {
        final key =
            await KeychainService.instance.readSecret(provider.keychainKeyId);
        if (key != null && key.trim().isNotEmpty) {
          final modelName = candidate.model.isNotEmpty
              ? candidate.model
              : (provider.videoModels.isNotEmpty
                  ? provider.videoModels.first
                  : 'agnes-video-2.5-flash');
          final isAgnes = modelName.toLowerCase().contains('agnes') ||
              provider.baseUrl.toLowerCase().contains('agnes');
          if (isAgnes) {
            // 必须过 _wrap：这条路径是日常最常走的，漏规整意味着用户请求的
            // 时长/画幅会原样发给模型。provider 一并传入，让能力矩阵优先用
            // 供应商自己声明的模型参数，而不是协议级保守默认（design 决策 4）。
            return _wrap(
              AgnesVideoAdapter(
                baseUrl: provider.baseUrl,
                model: modelName,
                apiKey: key.trim(),
                providerId: provider.id,
                keychainKeyId: provider.keychainKeyId,
              ),
              modelName,
              capabilitySource: provider,
            );
          }
          return _wrap(
            SenseAudioVideoAdapter(
              baseUrl: provider.baseUrl,
              model: modelName,
              apiKey: key.trim(),
              providerId: provider.id,
              keychainKeyId: provider.keychainKeyId,
            ),
            modelName,
            capabilitySource: provider,
          );
        }
      }
    }

    // 3. drama 制作类型回退检测 Kling
    if (productionType == 'drama') {
      final kling = KlingVideoAdapter();
      if (await kling.isAvailable()) return _wrap(kling, 'kling-i2v');
    }

    // 4. 检查内置 Dola 免费号池
    final dolaAdapter = DolaPoolVideoAdapter();
    if (await dolaAdapter.isAvailable()) {
      // 传入号池自己的能力配置，让用户在界面上改的覆盖优先于内置预设。
      // 不传的话能力查找只有预设一档，用户改什么都不生效。
      return _wrap(
        dolaAdapter,
        dolaAdapter.id,
        capabilitySource: DolaConfigStore.instance,
      );
    }

    // 5. 回退到本地 Ken Burns
    //
    // 不包：它的上界来自 totalFrames.clamp(30, 900)（即 1–30 秒），本来就不
    // 该被媒体模型的能力矩阵裁剪。包了反而会让「narration 类型想要 40 秒
    // 片段」这种合理请求被拒。测试把这条排除写成显式断言，防止后来者误当
    // 漏包「修好」它（design 决策 3）。
    return KenBurnsVideoAdapter();
  }

  static Future<VideoGenAdapter?> _byId(String id) async {
    if (id.startsWith('dola-pool')) {
      final model = id.contains('2.0') ? 'seedance-2.0' : 'seedance-2.5';
      return DolaPoolVideoAdapter(model: model);
    }
    if (id == 'kling-i2v') return KlingVideoAdapter();
    if (id == 'local-kenburns-ffmpeg') return KenBurnsVideoAdapter();
    if (id == 'agnes-video-2.5-flash' || id.startsWith('agnes')) {
      final videoCandidates =
          AiConfigStore.instance.slotBindings['video'] ?? [];
      for (final candidate in videoCandidates) {
        final provider = AiConfigStore.instance.providers.firstWhere(
          (p) => p.id == candidate.providerId,
          orElse: () => const AiProviderConfig(
            id: '',
            name: '',
            protocol: AiProtocolType.openai,
            baseUrl: '',
            keychainKeyId: '',
          ),
        );
        if (provider.id.isNotEmpty) {
          final key =
              await KeychainService.instance.readSecret(provider.keychainKeyId);
          return _wrap(
            AgnesVideoAdapter(
              baseUrl: provider.baseUrl,
              model: candidate.model.isNotEmpty
                  ? candidate.model
                  : 'agnes-video-2.5-flash',
              apiKey: key?.trim(),
              providerId: provider.id,
              keychainKeyId: provider.keychainKeyId,
            ),
            candidate.model.isNotEmpty ? candidate.model : 'agnes-video-2.5-flash',
            capabilitySource: provider,
          );
        }
      }
      return AgnesVideoAdapter();
    }
    if (id == 'system-video' || id.startsWith('senseaudio')) {
      final videoCandidates =
          AiConfigStore.instance.slotBindings['video'] ?? [];
      for (final candidate in videoCandidates) {
        final provider = AiConfigStore.instance.providers.firstWhere(
          (p) => p.id == candidate.providerId,
          orElse: () => const AiProviderConfig(
            id: '',
            name: '',
            protocol: AiProtocolType.openai,
            baseUrl: '',
            keychainKeyId: '',
          ),
        );
        if (provider.id.isNotEmpty) {
          final key =
              await KeychainService.instance.readSecret(provider.keychainKeyId);
          final modelName = candidate.model.isNotEmpty
              ? candidate.model
              : (provider.videoModels.isNotEmpty
                  ? provider.videoModels.first
                  : 'agnes-video-2.5-flash');
          if (modelName.toLowerCase().contains('agnes')) {
            return AgnesVideoAdapter(
              baseUrl: provider.baseUrl,
              model: modelName,
              apiKey: key?.trim(),
              providerId: provider.id,
              keychainKeyId: provider.keychainKeyId,
            );
          }
          return _wrap(
            SenseAudioVideoAdapter(
              baseUrl: provider.baseUrl,
              model: modelName,
              apiKey: key?.trim(),
              providerId: provider.id,
              keychainKeyId: provider.keychainKeyId,
            ),
            modelName,
            capabilitySource: provider,
          );
        }
      }
      return AgnesVideoAdapter();
    }
    return null;
  }

  /// 获取当前系统配置绑定的视频模型摘要信息（供工坊设置 UI 呈现）。
  static ({
    bool isConfigured,
    String providerName,
    String modelName,
    String description,
  }) getSystemVideoConfigSummary() {
    final videoCandidates = AiConfigStore.instance.slotBindings['video'] ?? [];
    for (final candidate in videoCandidates) {
      final provider = AiConfigStore.instance.providers.firstWhere(
        (p) => p.id == candidate.providerId,
        orElse: () => const AiProviderConfig(
          id: '',
          name: '',
          protocol: AiProtocolType.openai,
          baseUrl: '',
          keychainKeyId: '',
        ),
      );
      if (provider.id.isNotEmpty) {
        final model = candidate.model.isNotEmpty
            ? candidate.model
            : (provider.videoModels.isNotEmpty
                ? provider.videoModels.first
                : 'agnes-video-2.5-flash');
        return (
          isConfigured: true,
          providerName: provider.name,
          modelName: model,
          description: '${provider.name} ($model)',
        );
      }
    }
    return (
      isConfigured: false,
      providerName: '',
      modelName: '',
      description: '未配置视频模型',
    );
  }

  static List<VideoGenAdapter> allAdapters() => [
        DolaPoolVideoAdapter(),
        AgnesVideoAdapter(),
        SenseAudioVideoAdapter(),
        KlingVideoAdapter(),
        KenBurnsVideoAdapter(),
      ];

  /// 测试用：取消工厂创建的适配器上正在进行的任务。
  static void cancelForTesting(VideoGenAdapter adapter) {
    if (adapter case final CancellableVideoGenAdapter cancellable) {
      cancellable.cancelCurrent();
    }
  }

  /// 测试用：释放工厂创建的 HTTP 客户端。
  static void disposeForTesting(VideoGenAdapter adapter) {
    if (adapter is KlingVideoAdapter) adapter.disposeForTesting();
    if (adapter is SenseAudioVideoAdapter) adapter.disposeForTesting();
    if (adapter is AgnesVideoAdapter) adapter.disposeForTesting();
  }
}

extension on KlingVideoAdapter {
  void disposeForTesting() => _client?.close();
}
