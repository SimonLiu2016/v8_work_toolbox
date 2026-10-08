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

import '../../../services/ai_config_store.dart';
import '../../../services/app_http_client.dart';
import '../../../services/keychain_service.dart';
import 'ffmpeg_composer.dart';
import 'image_gen_adapter.dart' show ImageHttpFn;

/// 一次视频片段生成请求。
class VideoGenRequest {
  /// 首帧图片（已生成的关键帧）。Ken Burns 必需；I2V 也是。
  final File inputImage;

  /// 运镜指令（英文短语，如 "slow push-in"）。I2V 引擎会读它。
  final String cameraMove;

  /// 期望时长（秒）。
  final double durationSec;

  /// 分镜编号（进度展示与定位）。
  final int shotNumber;

  /// 输出目标文件（.mp4）。
  final File outputFile;

  /// 制作类型 id，用于选默认策略。
  final String productionType;

  const VideoGenRequest({
    required this.inputImage,
    required this.cameraMove,
    required this.durationSec,
    required this.shotNumber,
    required this.outputFile,
    this.productionType = 'drama',
  });
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
        '-i', request.inputImage.path,
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
    // 免去先传素材库再引用这一步。
    final imageBytes = await request.inputImage.readAsBytes();
    final dataUri =
        'data:image/png;base64,${base64Encode(imageBytes)}';

    final createResponse = await _post(
      Uri.parse(createEndpoint),
      key: key,
      body: {
        'model_name': 'kling-v1',
        'image': dataUri,
        'prompt': request.cameraMove.isEmpty
            ? 'gentle cinematic camera motion'
            : request.cameraMove,
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

    if (!await request.inputImage.exists()) {
      throw StateError('分镜首帧图片不存在: ${request.inputImage.path}');
    }

    final imageBytes = await request.inputImage.readAsBytes();
    final dataUri = 'data:image/png;base64,${base64Encode(imageBytes)}';

    final promptText = request.cameraMove.trim().isEmpty
        ? 'gentle cinematic camera motion, smooth pan'
        : request.cameraMove.trim();

    // 时长：SenseAudio 支持 4~15 秒，默认按 request 钳制
    final duration = request.durationSec.round().clamp(4, 15);

    final createEndpoint = Uri.parse('$baseUrl/video/create');
    final payload = {
      'model': _model,
      'content': [
        {'type': 'text', 'text': promptText},
        {'type': 'image', 'url': dataUri, 'role': 'first_frame'},
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

/// 视频生成适配器工厂。
///
/// 选择顺序：显式偏好 → 全局系统配置的 video 槽位模型 (SenseAudio) → 有 Key 的商业引擎 (Kling) → 本地 Ken Burns。
/// 本地引擎不可用（没装 FFmpeg）时仍返回它，让上层把"请安装 FFmpeg"或"请配置视频模型"的可操作提示显示出来。
class VideoGenAdapterFactory {
  VideoGenAdapterFactory._();

  static Future<VideoGenAdapter> create({
    String? preferredEngineId,
    String productionType = 'drama',
  }) async {
    // 1. 显式偏好匹配
    if (preferredEngineId != null && preferredEngineId.isNotEmpty) {
      final adapter = await _byId(preferredEngineId);
      if (adapter != null) return adapter;
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
                  : 'doubao-seedance-2-0-260128');
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

    // 4. 回退到本地 Ken Burns
    return KenBurnsVideoAdapter();
  }

  static Future<VideoGenAdapter?> _byId(String id) async {
    if (id == 'kling-i2v') return KlingVideoAdapter();
    if (id == 'local-kenburns-ffmpeg') return KenBurnsVideoAdapter();
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
          return SenseAudioVideoAdapter(
            baseUrl: provider.baseUrl,
            model: candidate.model.isNotEmpty
                ? candidate.model
                : (provider.videoModels.isNotEmpty
                    ? provider.videoModels.first
                    : 'doubao-seedance-2-0-260128'),
            apiKey: key?.trim(),
            providerId: provider.id,
            keychainKeyId: provider.keychainKeyId,
          );
        }
      }
      return SenseAudioVideoAdapter();
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
                : 'doubao-seedance-2-0-260128');
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
  }
}

extension on KlingVideoAdapter {
  void disposeForTesting() => _client?.close();
}
