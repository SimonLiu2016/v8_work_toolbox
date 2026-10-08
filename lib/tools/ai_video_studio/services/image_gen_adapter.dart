/// 图像生成 Engine Adapter 层（design.md D3：阶梯式引擎接口）。
///
/// 上层只依赖 [ImageGenAdapter] 这一个接口，所以把硅基流动换成 Stability AI
/// 只需新增一个实现类 + 改工厂的一行，UI 层一格代码都不用动。免费方案
/// （[LocalStubImageAdapter]）保证零 API Key 时全流程仍可跑通——spec 要求
/// 首次使用不得出现"功能不可用"提示。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../services/ai_config_store.dart';
import '../../../services/ai_logger.dart';
import '../../../services/app_http_client.dart';
import '../../../services/keychain_service.dart';

/// 一次关键帧生成请求。
class ImageGenRequest {
  /// 最终英文生图 Prompt（由 `PromptAssembler` 组装）。
  final String prompt;

  /// 负向 Prompt。
  final String negativePrompt;

  /// 分镜编号（用于占位图文字与文件名）。
  final int shotNumber;

  /// 输出目标文件（.png / .jpg）。
  final File outputFile;

  /// 画幅。竖屏 9:16 固定为 1080×1920（spec: 仅支持 9:16 竖屏）。
  final int width;
  final int height;

  /// 基准参考图路径（角色首图，部分引擎支持垫图）。
  final String? referenceImagePath;

  const ImageGenRequest({
    required this.prompt,
    this.negativePrompt = '',
    required this.shotNumber,
    required this.outputFile,
    this.width = 1080,
    this.height = 1920,
    this.referenceImagePath,
  });
}

/// 图像生成引擎抽象接口。
abstract interface class ImageGenAdapter {
  /// 引擎标识（设置页下拉的值）。
  String get id;

  /// 展示名。
  String get label;

  /// 是否已配置可用（免费引擎恒为 true）。
  Future<bool> isAvailable();

  /// 生成并写入 [ImageGenRequest.outputFile]，返回该文件。
  ///
  /// 失败时抛异常——上层任务队列据此把分镜标记为失败并提供重试，而不是
  /// 留下一个空白文件假装成功。
  Future<File> generate(ImageGenRequest request);
}

/// HTTP 后端签名，便于测试注入（不引入真实网络）。
typedef ImageHttpFn = Future<http.Response> Function(http.Request request);

/// 硅基流动 Flux-schnell 图像生成适配器。
///
/// 免费额度每日有限（design.md Risks），因此模型 id 固定为 Flux-schnell
/// 这一档——它是 SiliconFlow 上免费额度覆盖的型号。
class SiliconFlowImageAdapter implements ImageGenAdapter {
  SiliconFlowImageAdapter({http.Client? client, ImageHttpFn? httpFn})
    : _httpFn = httpFn,
      _client = client;

  final http.Client? _client;
  final ImageHttpFn? _httpFn;

  static const String endpoint =
      'https://api.siliconflow.cn/v1/images/generations';
  static const String modelId = 'black-forest-labs/FLUX.1-schnell';

  /// Keychain 里的键名。集中常量，避免读写两侧拼写漂移后静默读到空 Key。
  static const String keychainKeyId = 'studio_image_siliconflow_key';

  @override
  String get id => 'siliconflow-flux-schnell';

  @override
  String get label => '硅基流动 Flux-schnell（每日免费额度）';

  @override
  Future<bool> isAvailable() async =>
      (await readApiKey())?.isNotEmpty ?? false;

  /// 读取 API Key。未配置返回 null（工厂据此选择本地占位实现）。
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
  Future<File> generate(ImageGenRequest request) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('硅基流动 API Key 未配置');
    }

    final payload = <String, dynamic>{
      'model': modelId,
      'prompt': request.prompt,
      'image_size': '${request.width}x${request.height}',
      'num_inference_steps': 4,
      'batch_size': 1,
      if (request.negativePrompt.trim().isNotEmpty)
        'negative_prompt': request.negativePrompt.trim(),
    };

    final http.Response response;
    final req = http.Request('POST', Uri.parse(endpoint))
      ..headers['Authorization'] = 'Bearer $key'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(payload);
    if (_httpFn != null) {
      response = await _httpFn(req);
    } else {
      response = await (_client ?? AppHttpClient.create())
          .send(req)
          .then(http.Response.fromStream);
    }

    if (response.statusCode != 200) {
      throw StateError(
        '硅基流动图像生成失败 (HTTP ${response.statusCode}): '
        '${_truncate(_extractError(response.body), 200)}',
      );
    }

    final decoded = jsonDecode(response.body);
    final images = (decoded is Map ? decoded['images'] : null);
    if (images is! List || images.isEmpty) {
      throw const FormatException('硅基流动返回体中没有 images 字段');
    }
    final first = images.first;
    final url = first is Map ? first['url'] as String? : null;
    if (url == null || url.isEmpty) {
      throw const FormatException('硅基流动返回的 image 没有 url');
    }

    // URL 下载与生成请求分开：图片 CDN 的失败与 API 的失败要能区分排查。
    final imageResp = await (_client ?? AppHttpClient.create())
        .get(Uri.parse(url));
    if (imageResp.statusCode != 200) {
      throw StateError('下载生成图失败 (HTTP ${imageResp.statusCode})');
    }
    final bytes = imageResp.bodyBytes;
    if (bytes.length < 128) {
      // 128 字节以下的"图片"几乎必然是错误页占位。
      throw const FormatException('下载到的图像数据异常（过小）');
    }
    await request.outputFile.parent.create(recursive: true);
    await request.outputFile.writeAsBytes(bytes, flush: true);
    return request.outputFile;
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

/// SenseAudio 图像生成适配器（集成 SenseAudio-Image-2.0、豆包 Seedream 5.0、SenseNova U1 等官方图像模型）。
///
/// 遵循 SenseAudio 官方标准规范：
/// 1. 同步接口：POST `/v1/image/sync`，响应直接包含 `{"url": "https://..."}`；
/// 2. 异步接口：POST `/v1/image/async` 返回 `{"task_id": "..."}`，GET `/v1/image/pending?task_id=...` 轮询状态；
/// 3. 分辨率白名单吸附：自动将工坊请求的高宽规范化到模型支持的严格尺寸白名单（如 1080x1920 -> 1152x2048）；
/// 4. 参考图 Data URI 传递：读取本地角色参考图转为 Base64 Data URI 透传至 `reference` 字段；
/// 5. 方案 C 双模自适应调度：默认优先调用同步接口，遇超时或服务端排队状态时平滑切换异步轮询；
/// 6. 全链路接入 `AiLogger`。
class SenseAudioImageAdapter implements ImageGenAdapter {
  SenseAudioImageAdapter({
    this.baseUrl = 'https://api.senseaudio.cn/v1',
    this.model = 'senseaudio-image-2.0-260319',
    this.apiKey,
    this.providerId,
    this.keychainKeyId,
    http.Client? client,
    ImageHttpFn? httpFn,
  })  : _client = client,
        _httpFn = httpFn;

  final String baseUrl;
  final String model;
  final String? apiKey;
  final String? providerId;
  final String? keychainKeyId;
  final http.Client? _client;
  final ImageHttpFn? _httpFn;

  @override
  String get id => 'senseaudio-image';

  @override
  String get label => 'SenseAudio 图像生成 (官方原生双模)';

  static const String defaultEndpoint = 'https://api.senseaudio.cn/v1';
  static const String defaultModelId = 'senseaudio-image-2.0-260319';

  /// 模型支持的官方尺寸白名单映射。
  static const Map<String, List<String>> supportedDimensions = {
    'senseaudio-image-2.0-260319': [
      // ≤1.5K
      '1024x1024',
      '1024x1280', '1280x1024',
      '1536x864', '864x1536',
      '1024x1536', '1536x1024',
      '2016x864', '864x2016',
      '2048x1024', '1024x2048',
      '2048x1152', '1152x2048',
      '2048x1360', '1360x2048',
      // 2K
      '2688x1152', '1536x2048', '2048x1536',
      '2688x1344', '1344x2688', '3136x1344',
    ],
    'doubao-seedream-5-0-260128': [
      '2304x1728', '1728x2304',
      '2496x1664', '1664x2496',
      '2048x2048', '3136x1344',
      '2848x1600', '1600x2848',
      '3456x2592', '2592x3456',
      '2496x3744', '3744x2496',
      '4096x2304', '2304x4096',
      '3072x3072', '4704x2016',
    ],
    'sensenova-u1-fast': [
      '1664x2496', '2496x1664',
      '1760x2368', '2368x1760',
      '1824x2272', '2272x1824',
      '2048x2048', '2752x1536',
      '1536x2752', '3072x1376',
      '1344x3136',
    ],
  };

  /// 智能尺寸吸附算法：根据目标模型与输入高宽（如工坊 1080x1920），挑选宽高比最接近的合法尺寸。
  static String snapToSupportedSenseAudioSize(int width, int height, String targetModel) {
    final list = supportedDimensions[targetModel] ??
        supportedDimensions['senseaudio-image-2.0-260319']!;
    if (list.isEmpty) return '1152x2048';

    final targetRatio = width / (height <= 0 ? 1 : height);
    String bestMatch = list.first;
    double minDiff = double.infinity;

    for (final sizeStr in list) {
      final parts = sizeStr.split('x');
      if (parts.length != 2) continue;
      final w = int.tryParse(parts[0]) ?? 0;
      final h = int.tryParse(parts[1]) ?? 0;
      if (w <= 0 || h <= 0) continue;

      final ratio = w / h;
      final ratioDiff = (ratio - targetRatio).abs();
      final pixelDiff = ((w * h) - (width * height)).abs() / (width * height > 0 ? (width * height) : 1);
      final score = ratioDiff * 10.0 + pixelDiff;

      if (score < minDiff) {
        minDiff = score;
        bestMatch = sizeStr;
      }
    }
    return bestMatch;
  }

  @override
  Future<bool> isAvailable() async {
    final key = await _resolveApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<String?> _resolveApiKey() async {
    if (apiKey != null && apiKey!.trim().isNotEmpty) return apiKey!.trim();
    if (keychainKeyId != null && keychainKeyId!.isNotEmpty) {
      final key = await KeychainService.instance.readSecret(keychainKeyId!);
      if (key != null && key.trim().isNotEmpty) return key.trim();
    }

    // 优先读取 AiConfigStore 绑定的 image 槽位
    final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
    for (final candidate in imageCandidates) {
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
      if (provider.id.isNotEmpty && provider.keychainKeyId.isNotEmpty) {
        final key = await KeychainService.instance.readSecret(provider.keychainKeyId);
        if (key != null && key.trim().isNotEmpty) {
          return key.trim();
        }
      }
    }

    // 兜底读取视频槽位绑定的同一个 SenseAudio 供应商 Key
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
      if (provider.id.isNotEmpty &&
          provider.baseUrl.toLowerCase().contains('senseaudio.cn') &&
          provider.keychainKeyId.isNotEmpty) {
        final key = await KeychainService.instance.readSecret(provider.keychainKeyId);
        if (key != null && key.trim().isNotEmpty) {
          return key.trim();
        }
      }
    }

    return null;
  }

  static String _cleanBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) url = defaultEndpoint;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/v1')) {
      url = '$url/v1';
    }
    return url;
  }

  @override
  Future<File> generate(ImageGenRequest request) async {
    final key = await _resolveApiKey();
    if (key == null || key.isEmpty) {
      throw StateError(
        '未检测到 SenseAudio API Key，请先在「AI 基础设施配置」中为 SenseAudio 供应商保存 API Key。',
      );
    }

    final targetModel = model.trim().isNotEmpty ? model.trim() : defaultModelId;
    final snappedSize = snapToSupportedSenseAudioSize(
      request.width,
      request.height,
      targetModel,
    );

    String? referenceDataUri;
    if (request.referenceImagePath != null && request.referenceImagePath!.isNotEmpty) {
      try {
        final refFile = File(request.referenceImagePath!);
        if (await refFile.exists()) {
          final refBytes = await refFile.readAsBytes();
          if (refBytes.isNotEmpty) {
            referenceDataUri = 'data:image/png;base64,${base64Encode(refBytes)}';
          }
        }
      } catch (_) {}
    }

    final payload = <String, dynamic>{
      'model': targetModel,
      'prompt': request.prompt,
      'size': snappedSize,
      if (referenceDataUri != null) 'reference': referenceDataUri,
    };

    // 方案 C: 默认优先调用同步接口，遇超时或服务端排队状态时平滑降级为异步轮询
    try {
      return await _generateSync(request, key, payload);
    } catch (e) {
      final errMsg = e.toString();
      final shouldFallbackToAsync = errMsg.contains('500000') ||
          errMsg.contains('429') ||
          errMsg.contains('408') ||
          errMsg.contains('504') ||
          errMsg.contains('Timeout') ||
          errMsg.contains('timed out');
      if (shouldFallbackToAsync) {
        return await _generateAsync(request, key, payload);
      }
      rethrow;
    }
  }

  Future<File> _generateSync(
    ImageGenRequest request,
    String key,
    Map<String, dynamic> payload,
  ) async {
    final cleanBase = _cleanBaseUrl(baseUrl);
    final syncUri = Uri.parse('$cleanBase/image/sync');

    final stopwatch = Stopwatch()..start();
    AiLogger.logRequest(
      providerName: 'SenseAudio',
      protocol: 'senseaudio',
      model: payload['model'] as String? ?? defaultModelId,
      endpoint: syncUri.toString(),
      promptSummary: payload['prompt'] as String?,
    );

    final req = http.Request('POST', syncUri)
      ..headers['Authorization'] = 'Bearer $key'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(payload);

    final http.Response response;
    if (_httpFn != null) {
      response = await _httpFn(req);
    } else {
      final client = _client ?? AppHttpClient.create();
      response = await client.send(req).then(http.Response.fromStream);
    }
    stopwatch.stop();

    if (response.statusCode != 200) {
      final errorMsg =
          'SenseAudio 同步生图失败 (HTTP ${response.statusCode}): ${SiliconFlowImageAdapter._extractError(response.body)}';
      AiLogger.logError(
        errorMsg,
        providerName: 'SenseAudio',
      );
      throw StateError(errorMsg);
    }

    AiLogger.logResponse(
      providerName: 'SenseAudio',
      statusCode: response.statusCode,
      durationMs: stopwatch.elapsedMilliseconds,
      bodyPreview: response.body,
    );

    final decoded = jsonDecode(response.body);
    final url = decoded is Map ? decoded['url'] as String? : null;
    if (url == null || url.isEmpty) {
      throw const FormatException('SenseAudio 同步返回体未包含有效的 url 字段');
    }

    return await _downloadImage(url, request.outputFile);
  }

  Future<File> _generateAsync(
    ImageGenRequest request,
    String key,
    Map<String, dynamic> payload,
  ) async {
    final cleanBase = _cleanBaseUrl(baseUrl);
    final asyncUri = Uri.parse('$cleanBase/image/async');

    final stopwatch = Stopwatch()..start();
    AiLogger.logRequest(
      providerName: 'SenseAudio',
      protocol: 'senseaudio',
      model: payload['model'] as String? ?? defaultModelId,
      endpoint: asyncUri.toString(),
      promptSummary: payload['prompt'] as String?,
    );

    final req = http.Request('POST', asyncUri)
      ..headers['Authorization'] = 'Bearer $key'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(payload);

    final http.Response response;
    if (_httpFn != null) {
      response = await _httpFn(req);
    } else {
      final client = _client ?? AppHttpClient.create();
      response = await client.send(req).then(http.Response.fromStream);
    }

    if (response.statusCode != 200) {
      final errorMsg =
          'SenseAudio 异步任务创建失败 (HTTP ${response.statusCode}): ${SiliconFlowImageAdapter._extractError(response.body)}';
      AiLogger.logError(
        errorMsg,
        providerName: 'SenseAudio',
      );
      throw StateError(errorMsg);
    }

    final decoded = jsonDecode(response.body);
    final taskId = decoded is Map ? decoded['task_id'] as String? : null;
    if (taskId == null || taskId.isEmpty) {
      throw const FormatException('SenseAudio 异步任务创建未返回 task_id');
    }

    final pendingUri = Uri.parse('$cleanBase/image/pending?task_id=$taskId');
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));

      final pollReq = http.Request('GET', pendingUri)
        ..headers['Authorization'] = 'Bearer $key';

      final http.Response pollResp;
      if (_httpFn != null) {
        pollResp = await _httpFn(pollReq);
      } else {
        final client = _client ?? AppHttpClient.create();
        pollResp = await client.send(pollReq).then(http.Response.fromStream);
      }

      if (pollResp.statusCode != 200) {
        continue;
      }

      final pollData = jsonDecode(pollResp.body);
      if (pollData is! Map) continue;

      final status = pollData['status'] as String?;
      if (status == 'completed') {
        final imgUrl = pollData['url'] as String?;
        if (imgUrl == null || imgUrl.isEmpty) {
          throw StateError('SenseAudio 异步任务成功但未包含图片地址');
        }
        stopwatch.stop();
        AiLogger.logResponse(
          providerName: 'SenseAudio',
          statusCode: 200,
          durationMs: stopwatch.elapsedMilliseconds,
          bodyPreview: pollResp.body,
        );
        return await _downloadImage(imgUrl, request.outputFile);
      } else if (status == 'failed') {
        final failMsg = pollData['error_message']?.toString() ?? '未知原因';
        final err = 'SenseAudio 异步任务生成失败: $failMsg';
        AiLogger.logError(
          err,
          providerName: 'SenseAudio',
        );
        throw StateError(err);
      }
    }
    throw StateError('SenseAudio 异步图像生成超时 (超过 5 分钟)');
  }

  Future<File> _downloadImage(String url, File outputFile) async {
    await outputFile.parent.create(recursive: true);
    final http.Response imageResp;
    if (_httpFn != null) {
      imageResp = await _httpFn(http.Request('GET', Uri.parse(url)));
    } else {
      final client = _client ?? AppHttpClient.create();
      imageResp = await client.get(Uri.parse(url));
    }
    if (imageResp.statusCode != 200) {
      throw StateError('下载生成图失败 (HTTP ${imageResp.statusCode})');
    }
    final bytes = imageResp.bodyBytes;
    if (bytes.length < 128) {
      throw const FormatException('下载到的图像数据异常（过小）');
    }
    await outputFile.writeAsBytes(bytes, flush: true);
    return outputFile;
  }

  void disposeForTesting() {
    _client?.close();
  }
}

/// 系统全局 AI 配置图像生成适配器。
///
/// 动态获取系统全局 `image` 槽位中绑定的首选供应商凭证与模型。
/// 若系统当前绑定的图像供应商为 SenseAudio，自适应路由至 [SenseAudioImageAdapter]；
/// 否则遵循标准 OpenAI 兼容文生图协议（`POST /v1/images/generations`）。
class SystemAiImageAdapter implements ImageGenAdapter {
  SystemAiImageAdapter({
    this.baseUrl,
    this.model,
    this.apiKey,
    this.providerId,
    this.keychainKeyId,
    http.Client? client,
    ImageHttpFn? httpFn,
  })  : _client = client,
        _httpFn = httpFn;

  final String? baseUrl;
  final String? model;
  final String? apiKey;
  final String? providerId;
  final String? keychainKeyId;
  final http.Client? _client;
  final ImageHttpFn? _httpFn;

  @override
  String get id => 'system-image';

  @override
  String get label => '跟随系统全局配置（自适应协议）';

  AiProviderConfig _resolveActiveProvider() {
    if (providerId != null && providerId!.isNotEmpty) {
      final p = AiConfigStore.instance.providers.firstWhere(
        (prov) => prov.id == providerId,
        orElse: () => const AiProviderConfig(
          id: '',
          name: '',
          protocol: AiProtocolType.openai,
          baseUrl: '',
          keychainKeyId: '',
        ),
      );
      if (p.id.isNotEmpty) return p;
    }
    final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
    for (final candidate in imageCandidates) {
      final p = AiConfigStore.instance.providers.firstWhere(
        (prov) => prov.id == candidate.providerId && prov.enabled,
        orElse: () => const AiProviderConfig(
          id: '',
          name: '',
          protocol: AiProtocolType.openai,
          baseUrl: '',
          keychainKeyId: '',
        ),
      );
      if (p.id.isNotEmpty) return p;
    }
    return const AiProviderConfig(
      id: '',
      name: '',
      protocol: AiProtocolType.openai,
      baseUrl: '',
      keychainKeyId: '',
    );
  }

  @override
  Future<bool> isAvailable() async {
    final key = await _resolveApiKey();
    final url = _resolveEndpoint();
    return (key?.isNotEmpty ?? false) && url.isNotEmpty;
  }

  Future<String?> _resolveApiKey() async {
    if (apiKey != null && apiKey!.trim().isNotEmpty) return apiKey!.trim();
    if (keychainKeyId != null && keychainKeyId!.isNotEmpty) {
      final key = await KeychainService.instance.readSecret(keychainKeyId!);
      if (key != null && key.trim().isNotEmpty) return key.trim();
    }

    // 动态回退到 AiConfigStore 的 image 槽位
    final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
    for (final candidate in imageCandidates) {
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
      if (provider.id.isNotEmpty && provider.keychainKeyId.isNotEmpty) {
        final key = await KeychainService.instance.readSecret(provider.keychainKeyId);
        if (key != null && key.trim().isNotEmpty) {
          return key.trim();
        }
      }
    }
    return null;
  }

  String _resolveEndpoint() {
    var rawUrl = baseUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
      for (final candidate in imageCandidates) {
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
          rawUrl = provider.baseUrl.trim();
          break;
        }
      }
    }

    String url = rawUrl ?? '';
    if (url.isEmpty) {
      url = 'https://api.openai.com/v1';
    }

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    if (url.endsWith('/images/generations')) {
      return url;
    } else if (url.endsWith('/v1')) {
      return '$url/images/generations';
    } else {
      return '$url/v1/images/generations';
    }
  }

  String _resolveModel() {
    if (model != null && model!.trim().isNotEmpty) return model!.trim();
    final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
    for (final candidate in imageCandidates) {
      if (candidate.model.trim().isNotEmpty) {
        return candidate.model.trim();
      }
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
      if (provider.imageModels.isNotEmpty) {
        return provider.imageModels.first;
      }
    }
    return 'black-forest-labs/FLUX.1-schnell';
  }

  @override
  Future<File> generate(ImageGenRequest request) async {
    final key = await _resolveApiKey();
    if (key == null || key.isEmpty) {
      throw StateError(
        '未检测到可用的系统图像模型 API Key，请先在「AI 基础设施配置」中为全局图像槽位绑定供应商及密钥。',
      );
    }

    final activeProvider = _resolveActiveProvider();
    final rawBaseUrl = (baseUrl ?? activeProvider.baseUrl).trim();
    final targetModel = _resolveModel();
    final isSenseAudio = rawBaseUrl.toLowerCase().contains('senseaudio.cn') ||
        activeProvider.name.toLowerCase().contains('senseaudio') ||
        targetModel.toLowerCase().startsWith('senseaudio-');

    if (isSenseAudio) {
      final senseAdapter = SenseAudioImageAdapter(
        baseUrl: rawBaseUrl.isNotEmpty ? rawBaseUrl : SenseAudioImageAdapter.defaultEndpoint,
        model: targetModel,
        apiKey: key,
        providerId: activeProvider.id.isNotEmpty ? activeProvider.id : providerId,
        keychainKeyId: activeProvider.keychainKeyId.isNotEmpty
            ? activeProvider.keychainKeyId
            : keychainKeyId,
        client: _client,
        httpFn: _httpFn,
      );
      return await senseAdapter.generate(request);
    }

    final endpoint = _resolveEndpoint();
    final modelName = targetModel;

    final payload = <String, dynamic>{
      'model': modelName,
      'prompt': request.prompt,
      'size': '${request.width}x${request.height}',
      'image_size': '${request.width}x${request.height}', // 兼容 SiliconFlow / Flux 扩展
      'n': 1,
      if (request.negativePrompt.trim().isNotEmpty)
        'negative_prompt': request.negativePrompt.trim(),
    };

    final stopwatch = Stopwatch()..start();
    AiLogger.logRequest(
      providerName: activeProvider.name.isNotEmpty ? activeProvider.name : 'OpenAI-Compatible',
      protocol: 'openai',
      model: modelName,
      endpoint: endpoint,
      promptSummary: request.prompt,
    );

    final req = http.Request('POST', Uri.parse(endpoint))
      ..headers['Authorization'] = 'Bearer $key'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(payload);

    final http.Response response;
    if (_httpFn != null) {
      response = await _httpFn(req);
    } else {
      response = await (_client ?? AppHttpClient.create())
          .send(req)
          .then(http.Response.fromStream);
    }
    stopwatch.stop();

    if (response.statusCode != 200) {
      final err = '图像生成请求失败 (HTTP ${response.statusCode}): '
          '${SiliconFlowImageAdapter._truncate(SiliconFlowImageAdapter._extractError(response.body), 200)}';
      AiLogger.logError(
        err,
        providerName: activeProvider.name.isNotEmpty ? activeProvider.name : 'OpenAI-Compatible',
      );
      throw StateError(err);
    }

    AiLogger.logResponse(
      providerName: activeProvider.name.isNotEmpty ? activeProvider.name : 'OpenAI-Compatible',
      statusCode: response.statusCode,
      durationMs: stopwatch.elapsedMilliseconds,
      bodyPreview: response.body,
    );

    final decoded = jsonDecode(response.body);
    // 标准 OpenAI 结构为 {"data": [{"url": "..."}]} 或 {"data": [{"b64_json": "..."}]}
    // 硅基流动 Flux 结构可能为 {"images": [{"url": "..."}]} 或标准 data
    List<dynamic>? items;
    if (decoded is Map) {
      if (decoded['data'] is List && (decoded['data'] as List).isNotEmpty) {
        items = decoded['data'] as List;
      } else if (decoded['images'] is List && (decoded['images'] as List).isNotEmpty) {
        items = decoded['images'] as List;
      }
    }

    if (items == null || items.isEmpty) {
      throw const FormatException('接口返回体中未包含有效的图像数据 (缺少 data 或 images 字段)');
    }

    final first = items.first;
    if (first is! Map) {
      throw const FormatException('接口返回的图像格式异常');
    }

    final b64 = first['b64_json'] as String?;
    final url = first['url'] as String?;

    await request.outputFile.parent.create(recursive: true);

    if (b64 != null && b64.isNotEmpty) {
      final bytes = base64Decode(b64);
      await request.outputFile.writeAsBytes(bytes, flush: true);
      return request.outputFile;
    }

    if (url != null && url.isNotEmpty) {
      final http.Response imageResp;
      if (_httpFn != null) {
        imageResp = await _httpFn(http.Request('GET', Uri.parse(url)));
      } else {
        imageResp = await (_client ?? AppHttpClient.create())
            .get(Uri.parse(url));
      }
      if (imageResp.statusCode != 200) {
        throw StateError('下载生成图失败 (HTTP ${imageResp.statusCode})');
      }
      final bytes = imageResp.bodyBytes;
      if (bytes.length < 128) {
        throw const FormatException('下载到的图像数据异常（过小）');
      }
      await request.outputFile.writeAsBytes(bytes, flush: true);
      return request.outputFile;
    }

    throw const FormatException('返回体中既无 image url 也无 b64_json');
  }

  void disposeForTesting() {
    _client?.close();
  }
}

/// 本地占位图适配器：无任何 API Key 时兜底。
///
/// 产出纯色块 + 分镜编号文字，让用户能把整条流水线（拆镜→生图→合成→导出）
/// 在零成本下完整走一遍；分镜编号让占位图仍可辨认对应关系。
class LocalStubImageAdapter implements ImageGenAdapter {
  const LocalStubImageAdapter();

  @override
  String get id => 'local-stub';

  @override
  String get label => '本地占位图（免费，无 API Key）';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<File> generate(ImageGenRequest request) async {
    final bytes = _buildPlaceholderPng(
      width: request.width,
      height: request.height,
      shotNumber: request.shotNumber,
      prompt: request.prompt,
    );
    await request.outputFile.parent.create(recursive: true);
    await request.outputFile.writeAsBytes(bytes, flush: true);
    return request.outputFile;
  }

  /// 生成一张最小合法 PNG：底色 + 一条横向分隔带 + 镜号大字。
  ///
  /// 不引 `image` 包：这张图只需要能显示、能当 Ken Burns 的输入，
  /// 手写 PNG（zlib 压缩的原始扫描线）比引入重依赖划算。
  static Uint8List _buildPlaceholderPng({
    required int width,
    required int height,
    required int shotNumber,
    required String prompt,
  }) {
    // 底色随镜号在冷色区间内偏移，相邻分镜的占位图不至于完全一样。
    final hue = (shotNumber * 37) % 360;
    final (r, g, b) = _hsvToRgb(hue / 360.0, 0.35, 0.55);

    final rowBytes = width * 3 + 1; // 每行 1 字节 filter type + RGB
    final raw = ByteData(rowBytes * height);
    var offset = 0;
    final bandTop = (height * 0.42).round();
    final bandBottom = (height * 0.58).round();
    // 5×7 点阵数字，够显示镜号且不需要字体资源。
    final glyphRows = _digits5x7(shotNumber.toString());
    final glyphScale = (width * 0.012).round().clamp(6, 20);
    final glyphWidth = glyphRows.isEmpty ? 0 : glyphRows.first.length;
    final glyphLeft = (width / 2 - glyphWidth * glyphScale / 2).round();
    final glyphTop = (height / 2 - glyphRows.length * glyphScale / 2).round();

    for (var y = 0; y < height; y++) {
      raw.setUint8(offset, 0); // filter: none
      offset++;
      for (var x = 0; x < width; x++) {
        var pr = r, pg = g, pb = b;
        final inBand = y >= bandTop && y < bandBottom;
        if (inBand) {
          pr = (pr * 0.55).round();
          pg = (pg * 0.55).round();
          pb = (pb * 0.55).round();
        }
        final inGlyph = _isGlyphPixel(
          glyphRows: glyphRows,
          x: x,
          y: y,
          left: glyphLeft,
          top: glyphTop,
          scale: glyphScale,
        );
        if (inGlyph) {
          pr = 255;
          pg = 255;
          pb = 255;
        }
        raw.setUint8(offset++, pr);
        raw.setUint8(offset++, pg);
        raw.setUint8(offset++, pb);
      }
    }

    final compressed = _zlibCompress(raw.buffer.asUint8List());
    return _buildPng(width: width, height: height, idat: compressed);
  }

  static bool _isGlyphPixel({
    required List<String> glyphRows,
    required int x,
    required int y,
    required int left,
    required int top,
    required int scale,
  }) {
    for (var row = 0; row < glyphRows.length; row++) {
      final line = glyphRows[row];
      for (var col = 0; col < line.length; col++) {
        if (line[col] != '1') continue;
        final px = left + col * scale;
        final py = top + row * scale;
        if (x >= px && x < px + scale && y >= py && y < py + scale) {
          return true;
        }
      }
    }
    return false;
  }

  /// 5×7 点阵字形表（只覆盖数字与少量符号）。
  static List<String> _digits5x7(String text) {
    const font = <String, List<String>>{
      '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
      '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
      '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
      '3': ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
      '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
      '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
      '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
      '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
      '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
      '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
      '#': ['01010', '01010', '11111', '01010', '11111', '01010', '01010'],
    };
    // 所有字形横向拼接，中间隔一列空白。
    final rows = List<String>.filled(7, '');
    for (final ch in text.split('')) {
      final glyph = font[ch] ?? font['#']!;
      for (var i = 0; i < 7; i++) {
        rows[i] = '${rows[i]}0${glyph[i]}';
      }
    }
    return rows;
  }

  /// HSV → RGB，用于给占位图挑一个可辨识的底色。
  static (int, int, int) _hsvToRgb(double h, double s, double v) {
    final i = (h * 6).floor();
    final f = h * 6 - i;
    final pp = v * (1 - s);
    final qq = v * (1 - f * s);
    final tt = v * (1 - (1 - f) * s);
    final (r, g, b) = switch (i % 6) {
      0 => (v, tt, pp),
      1 => (qq, v, pp),
      2 => (pp, v, tt),
      3 => (pp, qq, v),
      4 => (tt, pp, v),
      _ => (v, pp, qq),
    };
    return ((r * 255).round(), (g * 255).round(), (b * 255).round());
  }

  /// 拼装 PNG：签名 + IHDR + IDAT + IEND。
  static Uint8List _buildPng({
    required int width,
    required int height,
    required Uint8List idat,
  }) {
    final out = BytesBuilder(copy: false);
    out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    void chunk(String type, List<int> data) {
      final length = data.length;
      out.add([
        (length >> 24) & 0xFF,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ]);
      final body = [...utf8.encode(type), ...data];
      out.add(body);
      final crc = _crc32(body);
      out.add([
        (crc >> 24) & 0xFF,
        (crc >> 16) & 0xFF,
        (crc >> 8) & 0xFF,
        crc & 0xFF,
      ]);
    }

    chunk('IHDR', [
      (width >> 24) & 0xFF,
      (width >> 16) & 0xFF,
      (width >> 8) & 0xFF,
      width & 0xFF,
      (height >> 24) & 0xFF,
      (height >> 16) & 0xFF,
      (height >> 8) & 0xFF,
      height & 0xFF,
      8, // bit depth
      2, // color type: truecolor RGB
      0, // compression
      0, // filter
      0, // interlace
    ]);
    chunk('IDAT', idat);
    chunk('IEND', const []);
    return out.takeBytes();
  }

  /// CRC-32（PNG 用的正是 zlib 标准多项式 0xEDB88320）。
  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var k = 0; k < 8; k++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}

/// 按 API Key 配置情况选择图像引擎。
///
/// 优先级：用户显式选择 > 付费引擎（有 Key 时）> 本地占位。spec 要求默认走
/// 免费方案且不提示功能不可用，所以兜底必须是「能出图」而不是「报错」。
class ImageGenAdapterFactory {
  ImageGenAdapterFactory._();

  /// `settings` 由设置页写入（`config/ai-video-studio.json`）。
  static Future<ImageGenAdapter> create({String? preferredEngineId}) async {
    // 1. 显式偏好匹配
    if (preferredEngineId != null && preferredEngineId.isNotEmpty) {
      final adapter = await _byId(preferredEngineId);
      if (adapter != null) return adapter;
    }

    // 2. 优先检查系统全局配置的 image 槽位候选供应商
    final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
    for (final candidate in imageCandidates) {
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
              : (provider.imageModels.isNotEmpty
                  ? provider.imageModels.first
                  : 'black-forest-labs/FLUX.1-schnell');
          return SystemAiImageAdapter(
            baseUrl: provider.baseUrl,
            model: modelName,
            apiKey: key.trim(),
            providerId: provider.id,
            keychainKeyId: provider.keychainKeyId,
          );
        }
      }
    }

    // 3. 回退检查独立配置的硅基流动
    final silicon = SiliconFlowImageAdapter();
    if (await silicon.isAvailable()) return silicon;

    // 4. 回退到本地占位实现
    return const LocalStubImageAdapter();
  }

  static Future<ImageGenAdapter?> _byId(String id) async {
    if (id == 'siliconflow-flux-schnell') return SiliconFlowImageAdapter();
    if (id == 'local-stub') return const LocalStubImageAdapter();
    if (id == 'senseaudio-image') return SenseAudioImageAdapter();
    if (id == 'system-image') {
      final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
      for (final candidate in imageCandidates) {
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
          return SystemAiImageAdapter(
            baseUrl: provider.baseUrl,
            model: candidate.model.isNotEmpty
                ? candidate.model
                : (provider.imageModels.isNotEmpty
                    ? provider.imageModels.first
                    : 'black-forest-labs/FLUX.1-schnell'),
            apiKey: key?.trim(),
            providerId: provider.id,
            keychainKeyId: provider.keychainKeyId,
          );
        }
      }
      return SystemAiImageAdapter();
    }
    return null;
  }

  /// 获取当前系统配置绑定的图像模型摘要信息（供工坊设置 UI 呈现）。
  static ({
    bool isConfigured,
    String providerName,
    String modelName,
    String description,
  }) getSystemImageConfigSummary() {
    final imageCandidates = AiConfigStore.instance.slotBindings['image'] ?? [];
    for (final candidate in imageCandidates) {
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
            : (provider.imageModels.isNotEmpty
                ? provider.imageModels.first
                : 'black-forest-labs/FLUX.1-schnell');
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
      description: '未配置图像模型',
    );
  }

  static List<ImageGenAdapter> allAdapters() => [
    SystemAiImageAdapter(),
    SenseAudioImageAdapter(),
    const LocalStubImageAdapter(),
    SiliconFlowImageAdapter(),
  ];

  /// 测试用：释放工厂创建的客户端。
  static void disposeForTesting(ImageGenAdapter adapter) {
    if (adapter is SiliconFlowImageAdapter) {
      adapter.disposeForTesting();
    } else if (adapter is SenseAudioImageAdapter) {
      adapter.disposeForTesting();
    } else if (adapter is SystemAiImageAdapter) {
      adapter.disposeForTesting();
    }
  }
}

extension on SiliconFlowImageAdapter {
  /// 测试辅助：关闭工厂路径上创建的客户端。
  void disposeForTesting() {
    _client?.close();
  }
}

/// PNG 的 IDAT 需要**带 zlib 头**的 deflate 流（RFC 1950），不是裸 deflate。
///
/// 这一点是实测出来的：`ZLibCodec(raw: true)` 产出裸 deflate，写进 PNG 后
/// FFmpeg 报 `inflate returned error -3`（incorrect header check），表现是
/// 合成时静默产出 0 字节文件并挂住。默认构造（`raw: false, gzip: false`）
/// 才是 zlib 格式，与 PNG 规范一致。
Uint8List _zlibCompress(Uint8List data) {
  final codec = ZLibCodec(level: 6);
  return Uint8List.fromList(codec.encode(data));
}
