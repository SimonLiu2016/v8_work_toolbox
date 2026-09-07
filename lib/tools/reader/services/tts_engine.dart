import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../../../services/ai_config_store.dart';
import '../../../../services/ai_logger.dart';
import '../../../../services/keychain_service.dart';
import '../models/reader_models.dart';

/// 抽象 TTS 语音合成引擎
abstract class TtsEngine {
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config);
  Future<bool> isAvailable();
}

/// 1. 微软 Edge-TTS 神经网络语音引擎 (免 API Key，高保真神经音质)
class EdgeTtsEngine implements TtsEngine {
  static const String _trustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _wsHost = 'speech.platform.bing.com';
  static const String _wsPath = '/consumer/speech/synthesize/readahead/edge/v1';

  final _uuid = const Uuid();

  @override
  Future<bool> isAvailable() async {
    return true;
  }

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    final connectionId = _uuid.v4().replaceAll('-', '');
    final requestId = _uuid.v4().replaceAll('-', '');
    final uri = Uri.parse(
      'wss://$_wsHost$_wsPath?TrustedClientToken=$_trustedToken&ConnectionId=$connectionId',
    );

    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0',
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      },
    ).timeout(const Duration(seconds: 10));

    final completer = Completer<Uint8List>();
    final audioChunks = <int>[];

    // 发送音质协议头
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final configHeader =
        'X-Timestamp:$timestamp\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
    socket.add(configHeader);

    // 计算语速百分比偏移 (例如 1.0 -> +0%, 1.25 -> +25%, 0.8 -> -20%)
    final speedPercent = ((config.speed - 1.0) * 100).round();
    final speedStr = speedPercent >= 0 ? '+$speedPercent%' : '$speedPercent%';

    final voice = config.voiceId.isNotEmpty ? config.voiceId : 'zh-CN-XiaoxiaoNeural';
    final lang = voice.split('-').length >= 2 ? '${voice.split('-')[0]}-${voice.split('-')[1]}' : 'zh-CN';
    final escapedText = _escapeXml(text);

    final ssml =
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="$lang">'
        '<voice name="$voice">'
        '<prosody pitch="+0Hz" rate="$speedStr" volume="+0%">'
        '$escapedText'
        '</prosody>'
        '</voice>'
        '</speak>';

    final ssmlHeader =
        'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:$timestamp\r\n'
        'Path:ssml\r\n\r\n'
        '$ssml';

    socket.add(ssmlHeader);

    final stopwatch = Stopwatch()..start();
    AiLogger.logRequest(
      providerName: 'Microsoft Edge-TTS',
      protocol: 'websocket-edge-tts',
      model: voice,
      endpoint: 'wss://$_wsHost$_wsPath',
      promptSummary: 'TTS 合成 [语速: ${config.speed}x]: $text',
    );

    StreamSubscription? sub;
    sub = socket.listen(
      (data) {
        if (data is List<int>) {
          // 二进制帧：前 2 字节为头长度，随后是头信息，再后面是真实 MP3 帧数据
          if (data.length > 2) {
            final headerLen = (data[0] << 8) | data[1];
            if (data.length > headerLen + 2) {
              final mp3Bytes = data.sublist(headerLen + 2);
              audioChunks.addAll(mp3Bytes);
            }
          }
        } else if (data is String) {
          if (data.contains('Path:turn.end')) {
            sub?.cancel();
            socket.close();
            if (!completer.isCompleted) {
              final bytes = Uint8List.fromList(audioChunks);
              AiLogger.logResponse(
                providerName: 'Microsoft Edge-TTS',
                statusCode: 200,
                durationMs: stopwatch.elapsedMilliseconds,
                bodyPreview: 'Edge-TTS 帧接收完成，大小: ${bytes.length} bytes',
              );
              completer.complete(bytes);
            }
          }
        }
      },
      onError: (err) {
        sub?.cancel();
        socket.close();
        if (!completer.isCompleted) {
          final e = Exception('Edge-TTS 连接异常: $err');
          AiLogger.logError(e.toString(), providerName: 'Microsoft Edge-TTS');
          completer.completeError(e);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          if (audioChunks.isNotEmpty) {
            final bytes = Uint8List.fromList(audioChunks);
            AiLogger.logResponse(
              providerName: 'Microsoft Edge-TTS',
              statusCode: 200,
              durationMs: stopwatch.elapsedMilliseconds,
              bodyPreview: 'Edge-TTS 接收完成，大小: ${bytes.length} bytes',
            );
            completer.complete(bytes);
          } else {
            const err = 'Edge-TTS 未返回音频数据';
            AiLogger.logError(err, providerName: 'Microsoft Edge-TTS');
            completer.completeError(Exception(err));
          }
        }
      },
      cancelOnError: true,
    );

    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        sub?.cancel();
        socket.close();
        if (audioChunks.isNotEmpty) {
          final bytes = Uint8List.fromList(audioChunks);
          AiLogger.logResponse(
            providerName: 'Microsoft Edge-TTS',
            statusCode: 200,
            durationMs: stopwatch.elapsedMilliseconds,
            bodyPreview: 'Edge-TTS 超时前已接收部分音频，大小: ${bytes.length} bytes',
          );
          return bytes;
        }
        const err = 'Edge-TTS 合成超时 (25s)';
        AiLogger.logError(err, providerName: 'Microsoft Edge-TTS');
        throw TimeoutException(err);
      },
    );
  }

  String _escapeXml(String str) {
    return str
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

/// 2. OpenAI-Compatible 自定义 AI TTS 引擎 (接入商业大模型语音及 Chat Audio 规范)
class OpenAiTtsEngine implements TtsEngine {
  final http.Client _client = http.Client();

  @override
  Future<bool> isAvailable() async {
    return true;
  }

  /// 判断目标模型或服务端是否采用 OpenAI Chat Audio Completions 规范
  static bool isChatAudioModel(String model, {String? baseUrl, String? providerName}) {
    final m = model.toLowerCase();
    final url = (baseUrl ?? '').toLowerCase();
    final name = (providerName ?? '').toLowerCase();

    if (m.startsWith('mimo-') || url.contains('xiaomimimo.com') || name.contains('mimo')) {
      return true;
    }
    if (m.contains('audio-preview') || m.contains('gpt-4o-audio') || m.contains('chat-audio')) {
      return true;
    }
    return false;
  }

  /// 判断目标是否属于小米 MiMo
  static bool isMimoModel(String model, {String? baseUrl, String? providerName}) {
    final m = model.toLowerCase();
    final url = (baseUrl ?? '').toLowerCase();
    final name = (providerName ?? '').toLowerCase();
    return m.startsWith('mimo-') || url.contains('xiaomimimo.com') || name.contains('mimo');
  }

  /// 解析系统 AI 配置下的 TTS 目标模型
  static String resolveSystemModel({
    AiProviderConfig? provider,
    String? configuredModel,
    AiConfigStore? store,
  }) {
    final s = store ?? AiConfigStore.instance;
    String resolved = '';

    if (provider != null) {
      final candidates = s.slotBindings['tts'] ?? [];
      // 1. 优先从 slotBindings['tts'] 中寻找匹配当前 provider 的模型
      for (final cand in candidates) {
        if (cand.providerId == provider.id && cand.model.trim().isNotEmpty) {
          resolved = cand.model.trim();
          break;
        }
      }

      // 2. 若当前 provider 未在 slot 中指定具体模型，查看 slot 中是否有任何非空候选模型
      if (resolved.isEmpty) {
        for (final cand in candidates) {
          if (cand.model.trim().isNotEmpty) {
            resolved = cand.model.trim();
            break;
          }
        }
      }

      // 3. 从 provider.ttsModels 获取
      if (resolved.isEmpty && provider.ttsModels.isNotEmpty) {
        resolved = provider.ttsModels.first.trim();
      }

      // 4. 从 provider 的所有模型列表中查找包含 'tts' 的模型
      if (resolved.isEmpty) {
        final allModels = [
          ...provider.ttsModels,
          ...provider.textModels,
          ...provider.multimodalModels,
          ...provider.sttModels,
        ];
        for (final m in allModels) {
          if (m.toLowerCase().contains('tts')) {
            resolved = m.trim();
            break;
          }
        }
      }
    }

    final isMimo = isMimoModel(
      resolved,
      baseUrl: provider?.baseUrl,
      providerName: provider?.name,
    );

    // 5. 若是小米 MiMo 供应商，且仍未解析出或者为 tts-1，兜底使用 mimo-v2.5-tts
    if (isMimo && (resolved.isEmpty || resolved == 'tts-1')) {
      return 'mimo-v2.5-tts';
    }

    if (resolved.isNotEmpty) {
      return resolved;
    }

    if (configuredModel != null && configuredModel.trim().isNotEmpty) {
      final cm = configuredModel.trim();
      if (isMimo && (cm.isEmpty || cm == 'tts-1')) {
        return 'mimo-v2.5-tts';
      }
      return cm;
    }

    return isMimo ? 'mimo-v2.5-tts' : 'tts-1';
  }

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    String endpoint = (config.customEndpoint ?? '').trim();
    String apiKey = (config.customApiKey ?? '').trim();
    String model = (config.customModel ?? 'tts-1').trim();
    String? providerName;

    // 优先从系统全局 AI 配置中动态解析
    if (config.useSystemAiConfig) {
      final store = AiConfigStore.instance;
      AiProviderConfig? provider;

      // 1. 若显式指定了系统供应商 ID
      if (config.systemProviderId != null && config.systemProviderId!.isNotEmpty) {
        provider = store.providers.cast<AiProviderConfig?>().firstWhere(
          (p) => p?.id == config.systemProviderId,
          orElse: () => null,
        );
      }

      // 2. 否则从默认 TTS 槽位查找首选候选供应商
      if (provider == null) {
        final candidates = store.slotBindings['tts'] ?? [];
        for (final cand in candidates) {
          final matched = store.providers.cast<AiProviderConfig?>().firstWhere(
            (p) => p?.id == cand.providerId && p?.enabled == true,
            orElse: () => null,
          );
          if (matched != null) {
            provider = matched;
            break;
          }
        }
      }

      // 3. 槽位未绑定时，回退到首个已启用的 OpenAI 协议供应商或带 TTS 模型的供应商
      if (provider == null) {
        provider = store.providers.cast<AiProviderConfig?>().firstWhere(
          (p) => p != null && p.enabled && (p.protocol == AiProtocolType.openai || p.ttsModels.isNotEmpty),
          orElse: () => null,
        );
      }

      if (provider != null) {
        endpoint = provider.baseUrl;
        providerName = provider.name;
        final key = await KeychainService.instance.readSecret(provider.keychainKeyId);
        if (key != null && key.isNotEmpty) {
          apiKey = key;
        }
        model = resolveSystemModel(
          provider: provider,
          configuredModel: config.customModel,
          store: store,
        );
      } else {
        if (endpoint.isEmpty) {
          throw Exception('系统「AI能力配置」中尚未找到可用的 TTS 槽位或 OpenAI 兼容供应商，请前往配置或切换为自定义手动模式。');
        }
      }
    }

    if (endpoint.isEmpty) {
      endpoint = 'https://api.openai.com/v1';
    }

    while (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }

    // 强化防御：若为 MiMo 且模型仍为 tts-1 或空，强制更正为 mimo-v2.5-tts
    if (isMimoModel(model, baseUrl: endpoint, providerName: providerName)) {
      if (model.isEmpty || model == 'tts-1') {
        model = 'mimo-v2.5-tts';
      }
    }

    final isChatAudio = isChatAudioModel(model, baseUrl: endpoint, providerName: providerName);
    final isMimo = isMimoModel(model, baseUrl: endpoint, providerName: providerName);

    // 解析音色并进行兼容性防御兜底
    String voice = config.effectiveVoiceId.trim();
    if (isMimo) {
      // 若当前音色不在 MiMo 允许的音色列表中（如继承了 Edge 或 OpenAI 的音色），兜底为 mimo_default
      if (voice.isEmpty || !TtsVoiceOption.mimoSupportedVoiceIds.contains(voice)) {
        voice = 'mimo_default';
      }
    } else {
      if (voice.isEmpty) {
        voice = 'alloy';
      }
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) ...{
        'Authorization': 'Bearer $apiKey',
        'api-key': apiKey,
      },
    };

    final pName = providerName ?? (isMimo ? 'Xiaomi MiMo' : 'OpenAI-Compatible TTS');

    if (isChatAudio) {
      // 采用 OpenAI Chat Audio Completions 规范 (POST /v1/chat/completions)
      String chatEndpoint = endpoint;
      if (chatEndpoint.endsWith('/chat/completions')) {
        // 已有完整后缀
      } else if (chatEndpoint.endsWith('/v1')) {
        chatEndpoint = '$chatEndpoint/chat/completions';
      } else {
        chatEndpoint = '$chatEndpoint/v1/chat/completions';
      }

      final url = Uri.parse(chatEndpoint);
      final body = jsonEncode({
        'model': model.isNotEmpty ? model : 'mimo-v2.5-tts',
        'messages': [
          {
            'role': 'assistant',
            'content': text,
          }
        ],
        'audio': {
          'format': 'wav',
          'voice': voice,
        },
      });

      final stopwatch = Stopwatch()..start();
      AiLogger.logRequest(
        providerName: pName,
        protocol: 'openai-chat-audio',
        model: model,
        endpoint: chatEndpoint,
        promptSummary: 'TTS 合成 [音色: $voice, 语速: ${config.speed}x]: $text',
      );

      http.Response response;
      try {
        response = await _client
            .post(url, headers: headers, body: body)
            .timeout(const Duration(seconds: 45));
      } catch (e) {
        AiLogger.logError('Chat Audio 请求网络异常: $e', providerName: pName);
        rethrow;
      }

      if (response.statusCode == 200) {
        final decodedJson = jsonDecode(utf8.decode(response.bodyBytes));
        if (decodedJson is Map<String, dynamic>) {
          final choices = decodedJson['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final firstChoice = choices.first as Map<String, dynamic>?;
            final message = firstChoice?['message'] as Map<String, dynamic>?;
            final audio = message?['audio'] as Map<String, dynamic>?;
            final base64Data = audio?['data'] as String?;
            if (base64Data != null && base64Data.isNotEmpty) {
              final bytes = base64Decode(base64Data);
              AiLogger.logResponse(
                providerName: pName,
                statusCode: 200,
                durationMs: stopwatch.elapsedMilliseconds,
                bodyPreview: '音频流解码成功, 大小: ${bytes.length} bytes (WAV)',
              );
              return bytes;
            }
          }
        }
        final err = 'Chat Audio 接口响应中未包含有效的音频数据: ${response.body}';
        AiLogger.logError(err, providerName: pName);
        throw Exception(err);
      } else {
        final errorMsg = utf8.decode(response.bodyBytes, allowMalformed: true);
        AiLogger.logResponse(
          providerName: pName,
          statusCode: response.statusCode,
          durationMs: stopwatch.elapsedMilliseconds,
          bodyPreview: errorMsg,
        );
        AiLogger.logError('Chat Audio TTS 合成失败 (HTTP ${response.statusCode}): $errorMsg', providerName: pName);
        throw Exception('Chat Audio TTS 合成失败 (HTTP ${response.statusCode}): $errorMsg');
      }
    } else {
      // 采用传统 OpenAI Audio Speech 规范 (POST /v1/audio/speech)
      String speechEndpoint = endpoint;
      if (speechEndpoint.endsWith('/audio/speech')) {
        // 已有完整后缀
      } else if (speechEndpoint.endsWith('/v1')) {
        speechEndpoint = '$speechEndpoint/audio/speech';
      } else {
        speechEndpoint = '$speechEndpoint/v1/audio/speech';
      }

      final url = Uri.parse(speechEndpoint);
      final body = jsonEncode({
        'model': model.isNotEmpty ? model : 'tts-1',
        'input': text,
        'voice': voice,
        'speed': config.speed,
        'response_format': 'mp3',
      });

      final stopwatch = Stopwatch()..start();
      AiLogger.logRequest(
        providerName: pName,
        protocol: 'openai-speech',
        model: model,
        endpoint: speechEndpoint,
        promptSummary: 'TTS 合成 [音色: $voice, 语速: ${config.speed}x]: $text',
      );

      http.Response response;
      try {
        response = await _client
            .post(url, headers: headers, body: body)
            .timeout(const Duration(seconds: 45));
      } catch (e) {
        AiLogger.logError('OpenAI TTS 请求网络异常: $e', providerName: pName);
        rethrow;
      }

      if (response.statusCode == 200) {
        AiLogger.logResponse(
          providerName: pName,
          statusCode: 200,
          durationMs: stopwatch.elapsedMilliseconds,
          bodyPreview: '音频流获取成功, 大小: ${response.bodyBytes.length} bytes',
        );
        return response.bodyBytes;
      } else {
        final errorMsg = utf8.decode(response.bodyBytes, allowMalformed: true);
        AiLogger.logResponse(
          providerName: pName,
          statusCode: response.statusCode,
          durationMs: stopwatch.elapsedMilliseconds,
          bodyPreview: errorMsg,
        );
        AiLogger.logError('OpenAI TTS 合成失败 (HTTP ${response.statusCode}): $errorMsg', providerName: pName);
        throw Exception('OpenAI TTS 合成失败 (HTTP ${response.statusCode}): $errorMsg');
      }
    }
  }
}

/// 3. macOS 本地原生离线合成引擎 (完全脱网 say / afconvert 兜底)
class MacOsNativeTtsEngine implements TtsEngine {
  @override
  Future<bool> isAvailable() async {
    return Platform.isMacOS;
  }

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('原生离线引擎仅在 macOS 平台支持');
    }

    final tempDir = Directory.systemTemp;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final aiffFile = File('${tempDir.path}/native_tts_$id.aiff');
    final mp3File = File('${tempDir.path}/native_tts_$id.mp3');

    try {
      // 1. 调用 say 输出 aiff
      final voice = config.voiceId.isNotEmpty ? config.voiceId : 'Tingting';
      // 计算语速 (普通话基准约为 175 词/分)
      final rate = (175 * config.speed).round();

      final sayProc = await Process.run('say', [
        '-v', voice,
        '-r', rate.toString(),
        '-o', aiffFile.path,
        text,
      ]);

      if (sayProc.exitCode != 0 || !await aiffFile.exists() || await aiffFile.length() == 0) {
        throw Exception('say 命令生成音频失败: ${sayProc.stderr}');
      }

      // 2. 利用 macOS 原生 afconvert 将 aiff 快速转为高兼容 mp3
      final convertProc = await Process.run('afconvert', [
        '-f', 'MPG3',
        '-d', '.mp3',
        aiffFile.path,
        mp3File.path,
      ]);

      if (convertProc.exitCode == 0 && await mp3File.exists() && await mp3File.length() > 0) {
        return await mp3File.readAsBytes();
      } else {
        // 若缺少 mp3 编码器则直接以 aiff 兼容回传
        return await aiffFile.readAsBytes();
      }
    } finally {
      try {
        if (await aiffFile.exists()) await aiffFile.delete();
        if (await mp3File.exists()) await mp3File.delete();
      } catch (_) {}
    }
  }
}

/// TTS 引擎调度工厂
class TtsEngineFactory {
  static TtsEngine createEngine(TtsMode mode) {
    switch (mode) {
      case TtsMode.edge:
        return EdgeTtsEngine();
      case TtsMode.customAi:
        return OpenAiTtsEngine();
      case TtsMode.macosNative:
        return MacOsNativeTtsEngine();
    }
  }
}
