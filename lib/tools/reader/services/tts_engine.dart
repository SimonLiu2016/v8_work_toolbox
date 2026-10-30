import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../../../services/ai_config_store.dart';
import '../../../../services/ai_logger.dart';
import '../../../../services/app_http_client.dart';
import '../../../../services/keychain_service.dart';
import '../../../tools/tool_definition.dart';
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
  http.Client _client;
  final http.Client Function()? _clientFactory;

  OpenAiTtsEngine({http.Client? client, http.Client Function()? clientFactory})
      : _clientFactory = clientFactory,
        _client = client ??
            (clientFactory != null
                ? clientFactory()
                : AppHttpClient.create(toolId: kToolIdDocAudioReader));

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

  /// 判断目标是否属于阶跃星辰 (StepFun / StepAudio)
  static bool isStepFunModel(String model, {String? baseUrl, String? providerName}) {
    final m = model.toLowerCase();
    final url = (baseUrl ?? '').toLowerCase();
    final name = (providerName ?? '').toLowerCase();
    return m.contains('stepaudio') ||
        m.contains('stepfun') ||
        url.contains('stepfun.com') ||
        name.contains('阶跃') ||
        name.contains('stepfun');
  }

  /// 判断目标是否属于通义千问 / 阿里云百炼 (Qwen / DashScope / CosyVoice)
  static bool isQwenModel(String model, {String? baseUrl, String? providerName}) {
    final m = model.toLowerCase();
    final url = (baseUrl ?? '').toLowerCase();
    final name = (providerName ?? '').toLowerCase();
    return m.contains('cosyvoice') ||
        m.contains('qwen-audio') ||
        m.contains('qwen3-tts') ||
        m.contains('qwen-tts') ||
        url.contains('qianwenaiapi.com') ||
        url.contains('dashscope.aliyuncs.com') ||
        name.contains('千问') ||
        name.contains('qwen');
  }

  /// 判断目标是否为 OpenAI 官方或默认端点
  static bool isOpenAiProvider({String? baseUrl, String? providerName}) {
    final url = (baseUrl ?? '').toLowerCase();
    final name = (providerName ?? '').toLowerCase();
    return url.contains('api.openai.com') || name.contains('openai');
  }

  /// 判断音色是否具有男性角色倾向
  static bool _isMaleVoice(String voice) {
    final v = voice.toLowerCase();
    const maleVoiceIds = {
      'boyinnansheng',
      'cixingnansheng',
      'ruyananshi',
      'shenchennanyin',
      'dushexiaoyu',
      'echo',
      'onyx',
      'fable',
      'longanlufeng',
      'longcheng',
      'longshuo',
      'longyuan',
      'longfei',
    };
    if (maleVoiceIds.contains(v)) return true;
    if (v.contains('male') || v.contains('nan') || v.contains('boy')) return true;
    return false;
  }

  /// 根据目标平台自适应映射与防御音色
  static String adaptVoiceForProvider(
    String requestedVoice, {
    required bool isQwen,
    required bool isMimo,
    required bool isStepFun,
    required bool isOpenAi,
  }) {
    final v = requestedVoice.trim();

    if (isMimo) {
      if (v.isEmpty || !TtsVoiceOption.mimoSupportedVoiceIds.contains(v)) {
        return 'mimo_default';
      }
      return v;
    }

    if (isQwen) {
      const qwenVoices = {
        'longanlingxin',
        'longanlufeng',
        'longanlingxin_v3.1',
        'longanhuan_v3.1',
        'longanfengyue_v3.1',
        'longxiaochun',
        'longwan',
        'longcheng',
        'longshuo',
      };
      if (qwenVoices.contains(v.toLowerCase())) {
        return v;
      }
      // 跨厂商音色自适应：如果是已知男声，映射为 longanlufeng；其余全部防御为 longanlingxin
      return _isMaleVoice(v) ? 'longanlufeng' : 'longanlingxin';
    }

    if (isStepFun) {
      const stepVoices = {
        'zhixingjiejie',
        'cixingnansheng',
        'boyinnansheng',
        'step_boy',
        'dushexiaoyu',
        'ruyananshi',
        'shenchennanyin',
        'elegantgentle-female',
        'livelybreezy-female',
      };
      if (stepVoices.contains(v.toLowerCase())) {
        return v;
      }
      return _isMaleVoice(v) ? 'cixingnansheng' : 'zhixingjiejie';
    }

    // 默认 OpenAI 兼容规范
    const openAiVoices = {'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'};
    if (openAiVoices.contains(v.toLowerCase())) {
      return v;
    }
    if (_isMaleVoice(v)) {
      return 'echo';
    }
    return 'alloy';
  }

  /// 构造 MiMo 的 user 消息风格指令。
  ///
  /// MiMo 没有 `speed`/`pitch` 数值参数，其「快慢/语调/情绪」全靠自然语言
  /// 指令表达。这里把配置中的 [TtsSynthesisConfig.speed] 翻译成语速片段，
  /// 拼接到用户配置的 [TtsSynthesisConfig.styleInstruction] 之后。非 MiMo
  /// 引擎不会调用此方法（由调用方以 `isMimo` 门控）。
  static String? _buildMimoStyleInstruction(TtsSynthesisConfig config) {
    final base = config.styleInstruction.trim();
    final speed = config.speed;

    String? speedFragment;
    if (speed > 1.5) {
      speedFragment = '语速很快';
    } else if (speed > 1.0) {
      speedFragment = '语速加快';
    } else if (speed < 0.75) {
      speedFragment = '语速很慢';
    } else if (speed < 1.0) {
      speedFragment = '语速放慢';
    }

    if (speedFragment == null) return base.isEmpty ? null : base;
    if (base.isEmpty) return speedFragment;
    return '$base，$speedFragment';
  }

  /// 解析系统 AI 配置下的 TTS 目标模型
  static String resolveSystemModel({
    AiProviderConfig? provider,
    String? configuredModel,
    AiConfigStore? store,
  }) {    final s = store ?? AiConfigStore.instance;
    String resolved = '';

    if (provider != null) {
      final candidates = s.slotBindings['tts'] ?? [];
      // 1. 严格仅从 slotBindings['tts'] 中寻找匹配当前 provider 的模型（禁止跨厂商候选项渗透）
      for (final cand in candidates) {
        if (cand.providerId == provider.id && cand.model.trim().isNotEmpty) {
          final m = cand.model.trim();
          if (m != 'qwen-audio-tts' && !m.startsWith('cosyvoice')) {
            resolved = m;
            break;
          }
        }
      }

      // 2. 从 provider.ttsModels 获取可用模型（排除非法的 qwen-audio-tts 及不支持的 cosyvoice）
      if (resolved.isEmpty && provider.ttsModels.isNotEmpty) {
        for (final tm in provider.ttsModels) {
          final t = tm.trim();
          if (t.isNotEmpty && t != 'qwen-audio-tts' && !t.startsWith('cosyvoice')) {
            resolved = t;
            break;
          }
        }
      }

      // 3. 从 provider 的所有模型列表中查找包含 'tts' 的模型
      if (resolved.isEmpty) {
        final allModels = [
          ...provider.ttsModels,
          ...provider.textModels,
          ...provider.multimodalModels,
          ...provider.sttModels,
        ];
        for (final m in allModels) {
          final trimmed = m.trim();
          if (trimmed.toLowerCase().contains('tts') &&
              trimmed != 'qwen-audio-tts' &&
              !trimmed.startsWith('cosyvoice')) {
            resolved = trimmed;
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
    final isQwen = isQwenModel(
      resolved,
      baseUrl: provider?.baseUrl,
      providerName: provider?.name,
    );
    final isStepFun = isStepFunModel(
      resolved,
      baseUrl: provider?.baseUrl,
      providerName: provider?.name,
    );

    // 4. 若为千问，且模型仍未解析出、为 tts-1 或历史遗留的 qwen-audio-tts/cosyvoice，统一使用官方稳定的 qwen-audio-3.0-tts-plus
    if (isQwen &&
        (resolved.isEmpty ||
            resolved == 'tts-1' ||
            resolved == 'qwen-audio-tts' ||
            resolved.startsWith('cosyvoice'))) {
      return 'qwen-audio-3.0-tts-plus';
    }

    // 5. 若是小米 MiMo 供应商，且仍未解析出或者为 tts-1，兜底使用 mimo-v2.5-tts
    if (isMimo && (resolved.isEmpty || resolved == 'tts-1')) {
      return 'mimo-v2.5-tts';
    }

    // 6. 若是阶跃 StepFun 供应商，且仍未解析出或者为 tts-1，兜底使用 stepaudio-2.5-tts
    if (isStepFun && (resolved.isEmpty || resolved == 'tts-1')) {
      return 'stepaudio-2.5-tts';
    }

    if (resolved.isNotEmpty &&
        resolved != 'qwen-audio-tts' &&
        !resolved.startsWith('cosyvoice')) {
      return resolved;
    }

    if (configuredModel != null && configuredModel.trim().isNotEmpty) {
      final cm = configuredModel.trim();
      if (isMimo && (cm.isEmpty || cm == 'tts-1')) {
        return 'mimo-v2.5-tts';
      }
      if (isQwen &&
          (cm.isEmpty ||
              cm == 'tts-1' ||
              cm == 'qwen-audio-tts' ||
              cm.startsWith('cosyvoice'))) {
        return 'qwen-audio-3.0-tts-plus';
      }
      if (isStepFun && (cm.isEmpty || cm == 'tts-1')) {
        return 'stepaudio-2.5-tts';
      }
      return cm;
    }

    if (isMimo) return 'mimo-v2.5-tts';
    if (isQwen) return 'qwen-audio-3.0-tts-plus';
    if (isStepFun) return 'stepaudio-2.5-tts';
    return 'tts-1';
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

    final isMimo = isMimoModel(model, baseUrl: endpoint, providerName: providerName);
    final isQwen = isQwenModel(model, baseUrl: endpoint, providerName: providerName);
    final isStepFun = isStepFunModel(model, baseUrl: endpoint, providerName: providerName);
    final isOpenAi = isOpenAiProvider(baseUrl: endpoint, providerName: providerName);

    // 强化防御：多平台模型自适应归一化
    if (isQwen) {
      if (model.isEmpty ||
          model == 'tts-1' ||
          model == 'qwen-audio-tts' ||
          model.startsWith('cosyvoice')) {
        model = 'qwen-audio-3.0-tts-plus';
      }
    } else if (isMimo) {
      if (model.isEmpty || model == 'tts-1') {
        model = 'mimo-v2.5-tts';
      }
    } else if (isStepFun) {
      if (model.isEmpty || model == 'tts-1') {
        model = 'stepaudio-2.5-tts';
      }
    }

    final isChatAudio = isChatAudioModel(model, baseUrl: endpoint, providerName: providerName);

    // 解析音色并进行全平台跨厂商自适应与防御兜底
    final voice = adaptVoiceForProvider(
      config.effectiveVoiceId,
      isQwen: isQwen,
      isMimo: isMimo,
      isStepFun: isStepFun,
      isOpenAi: isOpenAi,
    );

    // MiMo 没有 speed/pitch 数值参数，其语速靠自然语言指令表达。
    // 这里把用户选的速度倍率翻译成指令片段，拼到风格指令末尾。
    final mimoStyle = isMimo ? _buildMimoStyleInstruction(config) : null;

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Connection': 'close',
      if (apiKey.isNotEmpty) ...{
        'Authorization': 'Bearer $apiKey',
        'api-key': apiKey,
      },
    };

    final pName = providerName ??
        (isMimo ? 'Xiaomi MiMo' : (isQwen ? '千问 (Qwen)' : 'OpenAI-Compatible TTS'));

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
          // MiMo 的风格指令以 user 消息承载；有内容才注入，避免空 user 消息
          // 破坏请求（MiMo 要求 TTS 请求必须含 assistant 角色消息）。
          if (mimoStyle != null && mimoStyle.trim().isNotEmpty)
            {'role': 'user', 'content': mimoStyle.trim()},
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

      http.Response? response;
      int retryCount = 0;
      const maxRetries = 3;

      while (true) {
        final stopwatch = Stopwatch()..start();
        AiLogger.logRequest(
          providerName: pName,
          protocol: 'openai-chat-audio',
          model: model,
          endpoint: chatEndpoint,
          promptSummary: 'TTS 合成 [音色: $voice, 语速: ${config.speed}x]: $text',
        );

        try {
          response = await _client
              .post(url, headers: headers, body: body)
              .timeout(const Duration(seconds: 90));
        } catch (e) {
          if (retryCount < maxRetries) {
            retryCount++;
            AiLogger.logWarning(
              '商用 TTS 网络连接波动 ($e)，重置连接并在 1.5s 后进行第 $retryCount 次重试...',
              providerName: pName,
            );
            try {
              _client.close();
            } catch (_) {}
            _client = _clientFactory?.call() ??
                AppHttpClient.create(toolId: kToolIdDocAudioReader);
            await Future.delayed(const Duration(milliseconds: 1500));
            continue;
          }
          AiLogger.logError('Chat Audio 请求网络异常: $e', providerName: pName);
          rethrow;
        }

        if (response.statusCode == 429 && retryCount < maxRetries) {
          retryCount++;
          const steppedDelays = [4000, 10000, 20000];
          int delayMs = steppedDelays[retryCount - 1];
          final retryAfterHeader = response.headers['retry-after'];
          if (retryAfterHeader != null) {
            final parsedSeconds = int.tryParse(retryAfterHeader.trim());
            if (parsedSeconds != null && parsedSeconds > 0) {
              final headerMs = parsedSeconds * 1000;
              if (headerMs > delayMs) delayMs = headerMs;
            }
          }
          final errorMsg = utf8.decode(response.bodyBytes, allowMalformed: true);
          AiLogger.logWarning(
            '商用 TTS 触发并发频率限制 (HTTP 429)，等待 ${delayMs ~/ 1000}s 后进行第 $retryCount 次自动重试... [响应: $errorMsg]',
            providerName: pName,
          );
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
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
      }
    } else if (isQwen) {
      // 采用阿里云百炼 DashScope 原生 SpeechSynthesizer 规范 (POST /api/v1/services/audio/tts/SpeechSynthesizer)
      String dashscopeEndpoint = endpoint;
      if (dashscopeEndpoint.contains('/compatible-mode/v1')) {
        dashscopeEndpoint = dashscopeEndpoint.replaceAll(
          '/compatible-mode/v1',
          '/api/v1/services/audio/tts/SpeechSynthesizer',
        );
      } else if (dashscopeEndpoint.endsWith('/v1')) {
        dashscopeEndpoint = dashscopeEndpoint.replaceAll(
          RegExp(r'/v1$'),
          '/api/v1/services/audio/tts/SpeechSynthesizer',
        );
      } else if (!dashscopeEndpoint.contains('/SpeechSynthesizer')) {
        while (dashscopeEndpoint.endsWith('/')) {
          dashscopeEndpoint = dashscopeEndpoint.substring(0, dashscopeEndpoint.length - 1);
        }
        dashscopeEndpoint = '$dashscopeEndpoint/api/v1/services/audio/tts/SpeechSynthesizer';
      }

      final url = Uri.parse(dashscopeEndpoint);
      final body = jsonEncode({
        'model': model.isNotEmpty ? model : 'qwen-audio-3.0-tts-plus',
        'input': {
          'text': text,
          'voice': voice,
          'format': 'mp3',
        },
      });

      http.Response? response;
      int retryCount = 0;
      const maxRetries = 3;

      while (true) {
        final stopwatch = Stopwatch()..start();
        AiLogger.logRequest(
          providerName: pName,
          protocol: 'dashscope-speech-synthesizer',
          model: model,
          endpoint: dashscopeEndpoint,
          promptSummary: 'TTS 合成 [音色: $voice, 语速: ${config.speed}x]: $text',
        );

        try {
          response = await _client
              .post(url, headers: headers, body: body)
              .timeout(const Duration(seconds: 90));
        } catch (e) {
          if (retryCount < maxRetries) {
            retryCount++;
            AiLogger.logWarning(
              '百炼 TTS 网络连接波动 ($e)，重置连接并在 1.5s 后进行第 $retryCount 次重试...',
              providerName: pName,
            );
            try {
              _client.close();
            } catch (_) {}
            _client = _clientFactory?.call() ??
                AppHttpClient.create(toolId: kToolIdDocAudioReader);
            await Future.delayed(const Duration(milliseconds: 1500));
            continue;
          }
          AiLogger.logError('百炼 TTS 请求网络异常: $e', providerName: pName);
          rethrow;
        }

        if (response.statusCode == 429 && retryCount < maxRetries) {
          retryCount++;
          const steppedDelays = [4000, 10000, 20000];
          int delayMs = steppedDelays[retryCount - 1];
          final retryAfterHeader = response.headers['retry-after'];
          if (retryAfterHeader != null) {
            final parsedSeconds = int.tryParse(retryAfterHeader.trim());
            if (parsedSeconds != null && parsedSeconds > 0) {
              final headerMs = parsedSeconds * 1000;
              if (headerMs > delayMs) delayMs = headerMs;
            }
          }
          final errorMsg = utf8.decode(response.bodyBytes, allowMalformed: true);
          AiLogger.logWarning(
            '百炼 TTS 触发并发频率限制 (HTTP 429)，等待 ${delayMs ~/ 1000}s 后重试... [响应: $errorMsg]',
            providerName: pName,
          );
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        if (response.statusCode == 200) {
          final bodyStr = utf8.decode(response.bodyBytes, allowMalformed: true);
          try {
            final jsonMap = jsonDecode(bodyStr);
            if (jsonMap is Map<String, dynamic>) {
              final output = jsonMap['output'];
              if (output is Map<String, dynamic>) {
                final audio = output['audio'];
                if (audio is Map<String, dynamic>) {
                  // 1. 若直接携带 base64 数据
                  final data = (audio['data'] as String?)?.trim();
                  if (data != null && data.isNotEmpty) {
                    final bytes = base64Decode(data);
                    AiLogger.logResponse(
                      providerName: pName,
                      statusCode: 200,
                      durationMs: stopwatch.elapsedMilliseconds,
                      bodyPreview: '百炼 TTS base64 音频解码成功: ${bytes.length} bytes',
                    );
                    return bytes;
                  }
                  // 2. 若携带音频临时下载地址 url
                  final audioUrl = (audio['url'] as String?)?.trim();
                  if (audioUrl != null && audioUrl.isNotEmpty) {
                    final dlResp = await _client.get(Uri.parse(audioUrl)).timeout(const Duration(seconds: 30));
                    if (dlResp.statusCode == 200 && dlResp.bodyBytes.isNotEmpty) {
                      AiLogger.logResponse(
                        providerName: pName,
                        statusCode: 200,
                        durationMs: stopwatch.elapsedMilliseconds,
                        bodyPreview: '百炼 TTS url 下载成功: ${dlResp.bodyBytes.length} bytes',
                      );
                      return dlResp.bodyBytes;
                    }
                  }
                }
              }
            }
          } catch (_) {}

          if (response.bodyBytes.isNotEmpty && !bodyStr.trim().startsWith('{')) {
            return response.bodyBytes;
          }

          final err = '百炼 TTS 响应成功但未解析到音频内容: $bodyStr';
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
          AiLogger.logError('百炼 TTS 合成失败 (HTTP ${response.statusCode}): $errorMsg', providerName: pName);
          throw Exception('百炼 TTS 合成失败 (HTTP ${response.statusCode}): $errorMsg');
        }
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

      http.Response? response;
      int retryCount = 0;
      const maxRetries = 3;

      while (true) {
        final stopwatch = Stopwatch()..start();
        AiLogger.logRequest(
          providerName: pName,
          protocol: 'openai-speech',
          model: model,
          endpoint: speechEndpoint,
          promptSummary: 'TTS 合成 [音色: $voice, 语速: ${config.speed}x]: $text',
        );

        try {
          response = await _client
              .post(url, headers: headers, body: body)
              .timeout(const Duration(seconds: 90));
        } catch (e) {
          if (retryCount < maxRetries) {
            retryCount++;
            AiLogger.logWarning(
              '商用 TTS 网络连接波动 ($e)，重置连接并在 1.5s 后进行第 $retryCount 次重试...',
              providerName: pName,
            );
            try {
              _client.close();
            } catch (_) {}
            _client = _clientFactory?.call() ??
                AppHttpClient.create(toolId: kToolIdDocAudioReader);
            await Future.delayed(const Duration(milliseconds: 1500));
            continue;
          }
          AiLogger.logError('OpenAI TTS 请求网络异常: $e', providerName: pName);
          rethrow;
        }

        if (response.statusCode == 429 && retryCount < maxRetries) {
          retryCount++;
          const steppedDelays = [4000, 10000, 20000];
          int delayMs = steppedDelays[retryCount - 1];
          final retryAfterHeader = response.headers['retry-after'];
          if (retryAfterHeader != null) {
            final parsedSeconds = int.tryParse(retryAfterHeader.trim());
            if (parsedSeconds != null && parsedSeconds > 0) {
              final headerMs = parsedSeconds * 1000;
              if (headerMs > delayMs) delayMs = headerMs;
            }
          }
          final errorMsg = utf8.decode(response.bodyBytes, allowMalformed: true);
          AiLogger.logWarning(
            '商用 TTS 触发并发频率限制 (HTTP 429)，等待 ${delayMs ~/ 1000}s 后进行第 $retryCount 次自动重试... [响应: $errorMsg]',
            providerName: pName,
          );
          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
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
