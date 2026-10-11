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
import '../../dola_pool/services/dola_pool_video_adapter.dart';
import 'ffmpeg_composer.dart';
import 'image_gen_adapter.dart' show ImageHttpFn;

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

  const VideoGenRequest({
    required this.inputImage,
    this.referenceImages = const [],
    this.promptZh = '',
    this.cameraMove = '',
    required this.durationSec,
    required this.shotNumber,
    required this.outputFile,
    this.productionType = 'drama',
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

  /// 本次请求的全部参考图（含首帧）。适配器按协议自行决定怎么用。
  List<File> get allImages {
    final result = <File>[];
    final first = inputImage;
    if (first != null) result.add(first);
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
      throw StateError('Agnes API Key 未配置，请前往「系统设置 -> AI 基础设施」配置视频模型供应商密钥');
    }
    _cancelled = false;

    // Agnes 的 keyframe 模式只接受单张 first_frame，且官方禁止首帧与参考素材
    // 同时使用。因此多参考图在这里只能取第一张，降级数量由调用方记录到
    // StudioSegment.degradedRefCount（design 决策 4）——不在这里静默丢弃。
    final firstFrame = request.inputImage ??
        (request.referenceImages.isNotEmpty
            ? request.referenceImages.first
            : null);
    final String? dataUri = firstFrame != null && await firstFrame.exists()
        ? await _prepareKeyframeDataUri(firstFrame)
        : null;

    // 片段提示词优先：它含逐镜动作与台词，比单独运镜短语更能驱动画面。
    final promptText = request.effectivePrompt.isEmpty
        ? 'cinematic camera motion, smooth video movement'
        : request.effectivePrompt;

    // 时长：Agnes Video 2.5 Flash 接受字符串 "4"~"12"，默认 "5"
    final durationSeconds = request.durationSec.round().clamp(4, 12).toString();

    final createUrl =
        baseUrl.endsWith('/v1') ? '$baseUrl/videos' : '$baseUrl/v1/videos';

    // 动态选择模式：有首帧则使用 keyframe 模式，无首帧回退到 text 文生视频
    // 注意：Agnes 官方严禁首尾帧素材与参考素材同时使用，keyframe 模式下切勿传递 image 或 images 字段
    final isKeyframe = dataUri != null && dataUri.isNotEmpty;
    final payload = <String, dynamic>{
      'model': _model,
      'prompt': promptText,
      'mode': isKeyframe ? 'keyframe' : 'text',
      'seconds': durationSeconds,
      'aspect_ratio': '9:16',
      if (isKeyframe) 'first_frame': dataUri,
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

    final taskId = SenseAudioVideoAdapter._extractTaskId(createResponse);
    if (taskId == null || taskId.isEmpty) {
      throw StateError(
        'Agnes 创建视频任务失败: ${SenseAudioVideoAdapter._truncate(SenseAudioVideoAdapter._extractErrorMessage(createResponse), 200)}',
      );
    }

    final deadline = DateTime.now().add(_pollTimeout);
    var videoUrl = '';
    var lastStatus = '';

    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) {
        throw StateError('视频生成任务已被用户取消');
      }

      await Future<void>.delayed(const Duration(seconds: 3));
      if (_cancelled) {
        throw StateError('视频生成任务已被用户取消');
      }

      Map<String, dynamic>? queryData;
      final rootUrl = baseUrl.endsWith('/v1')
          ? baseUrl.substring(0, baseUrl.length - 3)
          : baseUrl;

      // 1. 优先尝试通用 OpenAI Videos 轮询端点：/v1/videos/$taskId（中转站与标准化网关原生兼容）
      final stdQueryUri = Uri.parse(
        baseUrl.endsWith('/v1')
            ? '$baseUrl/videos/$taskId'
            : '$baseUrl/v1/videos/$taskId',
      );
      try {
        final stdResp = await _getRaw(stdQueryUri, key: key);
        if (stdResp.statusCode == 200) {
          final decoded = jsonDecode(stdResp.body);
          if (decoded is Map) {
            queryData = decoded.map((k, v) => MapEntry(k as String, v));
          }
        }
      } catch (_) {}

      // 2. 若中转站未开启或直连官方 Hub，尝试专用查询接口：/agnesapi?video_id=...&model_name=...
      if (queryData == null) {
        final agnesApiUri = Uri.parse(
          '$rootUrl/agnesapi?video_id=$taskId&model_name=$_model',
        );
        try {
          final agnesResp = await _getRaw(agnesApiUri, key: key);
          if (agnesResp.statusCode == 200) {
            final decoded = jsonDecode(agnesResp.body);
            if (decoded is Map) {
              queryData = decoded.map((k, v) => MapEntry(k as String, v));
            }
          }
        } catch (_) {}
      }

      if (queryData != null) {
        final status = SenseAudioVideoAdapter._extractStatus(queryData);
        lastStatus = status;

        final progressVal = SenseAudioVideoAdapter._extractProgress(queryData);
        if (progressVal != null) {
          onProgress?.call(progressVal);
        } else {
          onProgress?.call(0.5);
        }

        if (status == 'completed' ||
            status == 'succeeded' ||
            status == 'success') {
          videoUrl = SenseAudioVideoAdapter._extractVideoUrl(queryData);
          if (videoUrl.isNotEmpty) break;
        } else if (status == 'failed' || status == 'error') {
          throw StateError(
            'Agnes 视频生成失败: ${SenseAudioVideoAdapter._truncate(SenseAudioVideoAdapter._extractErrorMessage(queryData), 200)}',
          );
        }
      }
    }

    if (videoUrl.isEmpty) {
      throw StateError(
        'Agnes 任务在 ${_pollTimeout.inMinutes} 分钟内未完成（最后状态: $lastStatus）',
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

  /// 将关键帧图片高效降采样为 720P JPEG 并返回轻量 Data URI，避免因 Base64 体积过大遭中转网关截断。
  static Future<String> _prepareKeyframeDataUri(File file) async {
    final rawBytes = await file.readAsBytes();
    // 超过 180KB 必定触发压缩；即使原图本身略小，也统一进行安全归一化以保证格式与尺寸合规
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        // 等比限制最大边长为 720x1280 竖屏规格（或 1280x720 横屏规格）
        img.Image processed = decoded;
        if (decoded.width > 720 || decoded.height > 1280) {
          final aspect = decoded.width / decoded.height;
          if (aspect <= 720.0 / 1280.0) {
            // 高度优先限制为 1280
            processed = img.copyResize(decoded, height: 1280);
          } else {
            // 宽度优先限制为 720
            processed = img.copyResize(decoded, width: 720);
          }
        }
        // 编码为高质量 JPEG (质量 80)，体积精简至 60~100KB，传输迅捷且永不被截断
        final jpegBytes = img.encodeJpg(processed, quality: 80);
        return 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
      }
    } catch (e) {
      AiLogger.logWarning(
        '关键帧预处理转码失败，回退原始编码: $e',
        providerName: 'Agnes',
      );
    }
    // 降级回退
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

  void disposeForTesting() => _client?.close();
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
        resolution: '',
        ratio: '',
        referenceImageCount: request.allImages.length,
        hasFirstFrame: request.inputImage != null,
        hasLastFrame: false,
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
        referenceImages: request.referenceImages,
        promptZh: request.promptZh,
        cameraMove: request.cameraMove,
        durationSec: result.request.durationSec,
        shotNumber: request.shotNumber,
        outputFile: request.outputFile,
        productionType: request.productionType,
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
    AiProviderConfig? provider,
  }) {
    if (adapter is KenBurnsVideoAdapter) return adapter;
    // 已在 [_byId] 内包过的就不再包第二层：双层规整会让
    // `NormalizingVideoAdapter.unwrap()` 拿到又一个包装器，调用方对内层具体
    // 类型的判断（如工坊设置同步测试的 `isA<SenseAudioVideoAdapter>()`）失效。
    if (adapter is NormalizingVideoAdapter) return adapter;
    final capability = provider != null
        ? MediaCapabilityResolver.resolve(provider, modelId)
        : MediaCapabilityPresets.forModel(modelId) ??
            MediaCapabilityDefaults.openai;
    return NormalizingVideoAdapter(adapter, capability, modelId: modelId);
  }

  static Future<VideoGenAdapter> create({
    String? preferredEngineId,
    String productionType = 'drama',
  }) async {
    // 1. 显式偏好匹配
    if (preferredEngineId != null && preferredEngineId.isNotEmpty) {
      final adapter = await _byId(preferredEngineId);
      if (adapter != null) return _wrap(adapter, preferredEngineId);
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
            return AgnesVideoAdapter(
              baseUrl: provider.baseUrl,
              model: modelName,
              apiKey: key.trim(),
              providerId: provider.id,
              keychainKeyId: provider.keychainKeyId,
            );
          }
          return SenseAudioVideoAdapter(
            baseUrl: provider.baseUrl,
            model: modelName,
            apiKey: key.trim(),
            providerId: provider.id,
            keychainKeyId: provider.keychainKeyId,
          );
        }
      }
    }

    // 3. drama 制作类型回退检测 Kling
    if (productionType == 'drama') {
      final kling = KlingVideoAdapter();
      if (await kling.isAvailable()) return kling;
    }

    // 4. 检查内置 Dola 免费号池
    final dolaAdapter = DolaPoolVideoAdapter();
    if (await dolaAdapter.isAvailable()) return dolaAdapter;

    // 5. 回退到本地 Ken Burns
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
            provider: provider,
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
            provider: provider,
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
